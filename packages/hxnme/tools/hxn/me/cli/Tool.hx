package hxn.me.cli;

import haxe.Json;
import haxe.io.Path;
import hxn.me.project.Toml;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	The hxn CLI hook of hxnme. Before a build, it reads the `hxnme.toml` that
	is colocated with the program file, and returns what the build needs from it: the Ash options
	of the app's metadata, the class paths, defines and macros of the plugins
	it lists, and the path of the file as `-D hxnme_project`. `hxn run` and
	`hxn check` also get `-D hxnme_reload`, which makes the app loop check
	for a hot reload on HashLink each frame.

	Each plugin can also add haxelibs for the build's target. The plugin's
	manifest lists them under `hxnme.libraries`, and `[libraries.<plugin>]`
	in hxnme.toml replaces that list. This applies to the plugins that
	hxnme.toml lists and to the plugins that the program file selects with
	`-lib`.
**/
class Tool {
	// The target triple of the build, such as `aarch64-apple-darwin`, or "" when
	// the request has no target.
	static var triple = "";
	// The `[libraries]` table of hxnme.toml. For each plugin, it maps fragments of
	// a triple to lists of haxelibs.
	static var overrides:Dynamic = {};
	// The path of hxnme.toml, for error messages.
	static var file = "";

	static function main() {
		var request:Dynamic = Json.parse(Sys.stdin().readAll().toString());
		if (request.kind != "hook") {
			Sys.stderr().writeString("hxn me has no commands yet. hxnme reads an app's plugins and metadata from the hxnme.toml colocated with its program file.\n");
			Sys.exit(2);
		}
		var reply:Dynamic = {version: 1};
		var project:Dynamic = request.context.project;
		file = Path.join([project.directory, "hxnme.toml"]);
		var target:Dynamic = request.context.target;
		if (target != null)
			triple = target.triple != null ? target.triple : host();
		var args = [];
		var command = request.context.command;
		if (request.phase == "before-build" && (command == "run" || command == "check"))
			args.push(["-D", "hxnme_reload"]);
		if (request.phase == "before-build" && FileSystem.exists(file)) {
			args.push(["-D", 'hxnme_project=${Path.normalize(FileSystem.absolutePath(file))}']);
			var toml:Dynamic = try Toml.parse(File.getContent(file), file) catch (error:String) fail(error);
			var app:Dynamic = toml.app;
			if (app != null && app.preset != null)
				reply.ash_args = [["--preset", string(app.preset, "app.preset", file)]];
			var plugins:Array<Dynamic> = toml.plugins == null ? [] : toml.plugins;
			if (!Std.isOfType(plugins, Array))
				fail('$file: `plugins` must be an array of haxelib names');
			if (toml.libraries != null)
				overrides = toml.libraries;
			var selected = project.hxml == null ? [] : libraries(File.getContent(project.hxml));
			// The program file already selects these plugins, but the build does not
			// have their target libraries yet.
			var seen = selected.copy();
			for (name in selected) {
				var root = find(name);
				if (root != null)
					targetLibraries(Json.parse(File.getContent(Path.join([root, "haxelib.json"]))), root, project.directory, seen, args);
			}
			for (plugin in plugins)
				add(string(plugin, "plugins", file), project.directory, seen, args);
		}
		if (args.length > 0)
			reply.haxe_args = args;
		Sys.println(Json.stringify(reply));
	}

	// Adds the haxe arguments that `-lib` would give for `entry`, after those
	// of the haxelibs it depends on. `entry` is a haxelib name, or the path of
	// an in-project plugin's directory relative to `base`. Haxelibs in `seen`
	// are already selected.
	static function add(entry:String, base:String, seen:Array<String>, args:Array<Array<String>>) {
		var local = StringTools.startsWith(entry, ".") || entry.indexOf("/") >= 0;
		if (!local && seen.contains(entry))
			return;
		var root = local ? (Path.isAbsolute(entry) ? entry : Path.join([base, entry])) : libpath(entry);
		var manifest = Path.join([root, "haxelib.json"]);
		if (!FileSystem.exists(manifest))
			fail('hxnme.toml lists `$entry`, and $manifest does not exist');
		var info:Dynamic = Json.parse(File.getContent(manifest));
		var name:String = info.name;
		if (seen.contains(name))
			return;
		seen.push(name);
		var dependencies:Dynamic = info.dependencies == null ? {} : info.dependencies;
		for (dependency in Reflect.fields(dependencies))
			add(dependency, base, seen, args);
		args.push(["-cp", Path.join([root, info.classPath == null ? "" : info.classPath])]);
		args.push(["-D", '$name=${info.version}']);
		var extra = Path.join([root, "extraParams.hxml"]);
		if (FileSystem.exists(extra))
			for (pair in pairs(File.getContent(extra), extra))
				args.push(pair);
		targetLibraries(info, root, base, seen, args);
	}

	// Adds the haxelibs that a plugin's manifest lists for the target triple.
	// `hxnme.libraries` is an array of `{triple, use}`, and the first entry whose
	// `triple` is part of the target triple applies. `[libraries.<plugin>]` in
	// hxnme.toml maps fragments of a triple to lists instead, and the longest
	// fragment that matches applies. Paths in the manifest are relative to the
	// plugin's directory `root`. Paths in hxnme.toml are relative to the project
	// directory `base`.
	static function targetLibraries(info:Dynamic, root:String, base:String, seen:Array<String>, args:Array<Array<String>>) {
		var section:Dynamic = info.hxnme;
		if (section == null || triple == "")
			return;
		var name:String = info.name;
		var chosen:Null<Array<Dynamic>> = null;
		var from = base;
		var replaced:Dynamic = Reflect.field(overrides, name);
		if (replaced != null) {
			var best = -1;
			for (fragment in Reflect.fields(replaced))
				if (triple.indexOf(fragment) >= 0 && fragment.length > best) {
					best = fragment.length;
					chosen = list(Reflect.field(replaced, fragment), 'libraries.$name.$fragment', file);
				}
		}
		if (chosen == null && section.libraries != null) {
			from = root;
			var manifest = '${name}\'s haxelib.json';
			if (!Std.isOfType(section.libraries, Array))
				fail('$manifest: `hxnme.libraries` must be an array of {triple, use}');
			for (entry in (section.libraries : Array<Dynamic>)) {
				var fragment = string(entry.triple, "hxnme.libraries[].triple", manifest);
				if (triple.indexOf(fragment) >= 0) {
					chosen = list(entry.use, "hxnme.libraries[].use", manifest);
					break;
				}
			}
		}
		if (chosen != null)
			for (library in chosen)
				add(library, from, seen, args);
	}

	// Returns the target triple of the host. hxn gives a triple only for a cross
	// build or a wasm build, and a native build is for the machine that runs the hook.
	static function host():String {
		var system = Sys.systemName();
		if (system == "Windows")
			return (Sys.getEnv("PROCESSOR_ARCHITECTURE") == "ARM64" ? "aarch64" : "x86_64") + "-pc-windows-msvc";
		var machine = try {
			var process = new Process("uname", ["-m"]);
			var out = StringTools.trim(process.stdout.readAll().toString());
			process.close();
			out;
		} catch (_:Dynamic) "";
		var arch = machine == "arm64" || machine == "aarch64" ? "aarch64" : "x86_64";
		return system == "Mac" ? '$arch-apple-darwin' : '$arch-unknown-linux-gnu';
	}

	static function list(value:Dynamic, key:String, source:String):Array<Dynamic> {
		if (!Std.isOfType(value, Array))
			fail('$source: `$key` must be an array of haxelib names');
		for (item in (value : Array<Dynamic>))
			string(item, key, source);
		return value;
	}

	// The flags of an extraParams.hxml, each with its value. hxn's hooks take
	// -D, -cp and --macro.
	static function pairs(text:String, source:String):Array<Array<String>> {
		var out = [];
		for (line in text.split("\n")) {
			line = StringTools.trim(line);
			if (line == "" || StringTools.startsWith(line, "#"))
				continue;
			var space = line.indexOf(" ");
			var flag = space < 0 ? line : line.substr(0, space);
			var value = space < 0 ? "" : StringTools.trim(line.substr(space + 1));
			switch flag {
				case "-D" | "--define":
					out.push(["-D", value]);
				case "-cp" | "-p" | "--class-path":
					out.push(["-cp", Path.isAbsolute(value) ? value : Path.join([Path.directory(source), value])]);
				case "--macro":
					out.push(["--macro", value]);
				case _:
					fail('$source: hxnme passes -D, -cp and --macro from a plugin\'s extraParams.hxml, not `$flag`');
			}
		}
		return out;
	}

	// The haxelibs a program file selects with -lib, -L or --library.
	static function libraries(text:String):Array<String> {
		var found = [];
		var words = [for (word in ~/\s+/g.split(text)) if (word != "") word];
		for (i in 0...words.length - 1)
			if (words[i] == "-lib" || words[i] == "-L" || words[i] == "--library")
				found.push(words[i + 1].split(":")[0]);
		return found;
	}

	static function libpath(name:String):String {
		var out = find(name);
		if (out == null)
			fail('the build needs the haxelib `$name`, which haxelib does not have: install it with `haxelib install $name`');
		return out;
	}

	// Returns the directory of the haxelib `name`, or null when haxelib does not have it.
	static function find(name:String):Null<String> {
		var process = new Process("haxelib", ["libpath", name]);
		var out = StringTools.trim(process.stdout.readAll().toString());
		var code = process.exitCode();
		process.close();
		return code != 0 || out == "" || !FileSystem.exists(Path.join([out, "haxelib.json"])) ? null : out;
	}

	static function string(value:Dynamic, key:String, file:String):String {
		if (!Std.isOfType(value, String))
			fail('$file: `$key` must be a string');
		return value;
	}

	static function fail(message:String):Dynamic {
		Sys.stderr().writeString(message + "\n");
		Sys.exit(1);
		return null;
	}
}
