package hxn.me.cli;

import haxe.Json;
import haxe.io.Path;
import hxn.me.project.Toml;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	The hxn CLI hook of hxnme. Before a build, it reads `hxnme.toml` beside
	the program file and returns what the build needs from it: the Ash options
	of the app's metadata, and the class paths, defines and macros of the
	plugins it lists.
**/
class Tool {
	static function main() {
		var request:Dynamic = Json.parse(Sys.stdin().readAll().toString());
		if (request.kind != "hook") {
			Sys.stderr().writeString("hxn me has no commands yet. hxnme reads an app's plugins and metadata from hxnme.toml beside its program file.\n");
			Sys.exit(2);
		}
		var reply:Dynamic = {version: 1};
		var project:Dynamic = request.context.project;
		var file = Path.join([project.directory, "hxnme.toml"]);
		if (request.phase == "before-build" && FileSystem.exists(file)) {
			var toml:Dynamic = try Toml.parse(File.getContent(file), file) catch (error:String) fail(error);
			var app:Dynamic = toml.app;
			if (app != null && app.preset != null)
				reply.ash_args = [["--preset", string(app.preset, "app.preset", file)]];
			var plugins:Array<Dynamic> = toml.plugins == null ? [] : toml.plugins;
			if (!Std.isOfType(plugins, Array))
				fail('$file: `plugins` must be an array of haxelib names');
			var selected = project.hxml == null ? [] : libraries(File.getContent(project.hxml));
			var args = [];
			for (plugin in plugins)
				add(string(plugin, "plugins", file), project.directory, selected, args);
			if (args.length > 0)
				reply.haxe_args = args;
		}
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
			fail('hxnme.toml lists the plugin `$entry`, and $manifest does not exist');
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
		var process = new Process("haxelib", ["libpath", name]);
		var out = StringTools.trim(process.stdout.readAll().toString());
		var code = process.exitCode();
		process.close();
		if (code != 0 || out == "" || !FileSystem.exists(Path.join([out, "haxelib.json"])))
			fail('hxnme.toml lists the plugin `$name`, which haxelib does not have: install it with `haxelib install $name`');
		return out;
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
