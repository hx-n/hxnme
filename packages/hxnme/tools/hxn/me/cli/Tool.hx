package hxn.me.cli;

import haxe.Json;
import haxe.io.Path;
import hxn.cli.Cli;
import hxn.cli.Failure;
import hxn.cli.Reply;
import hxn.me.project.Toml;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	`Tool` answers the requests that the hxn command sends to hxnme. Before
	hxn compiles the app, the hook reads the `hxnme.toml` that is colocated
	with the program file, and returns what the compiler needs from it: the
	Ash options of the app's metadata, the class paths, defines and macros of
	the plugins that it lists, and the path of the file as
	`-D hxnme_project`. `hxn run` and `hxn check` also get `-D hxnme_reload`,
	which makes the app loop check for a hot reload on HashLink each frame.

	Each plugin can also add haxelibs for the target that the app compiles
	for. The plugin's manifest lists them under `hxnme.libraries`, and
	`[libraries.<plugin>]` in hxnme.toml replaces that list. This applies to
	the plugins that hxnme.toml lists and to the plugins that the program
	file selects with `-lib`.

	hxn runs build hooks only for the haxelibs that the program file selects.
	For each haxelib that hxnme.toml brings in, this hook runs that haxelib's
	hook for the same phase, and also returns what that hook returns, such as
	the browser agent of hxn-window as a file for the web page. The commands
	are `NewCommand` and `DevCommand`.
**/
class Tool {
	// Holds the target triple, such as `aarch64-apple-darwin`, or "" when the
	// request has no target.
	static var triple = "";
	// Holds the `[libraries]` table of hxnme.toml. For each plugin, it maps
	// fragments of a triple to lists of haxelibs.
	static var overrides:Dynamic = {};
	// Holds the path of hxnme.toml for error messages.
	static var file = "";
	// Holds the hook request. `forward` also sends it to the hooks of the haxelibs that hxnme.toml brings in.
	static var request:Dynamic;
	// These collect the Ash arguments and the web page files of the reply, including what those hooks return.
	static final ashArgs:Array<Array<String>> = [];
	static final pageFiles:Array<String> = [];

	// The command classes are built by a macro, which cannot run when a macro types this class.
	#if !macro
	static function main()
		hxn.cli.Plugin.main(new Cli("hxn me", "Creates hxnme apps, and runs them with hot reload.", [new NewCommand(), new DevCommand()]), hook);
	#end

	static function hook(phase:String, request:Dynamic):Reply {
		Tool.request = request;
		var reply = new Reply();
		if (phase == "before-build")
			for (pair in build())
				reply.haxeArgs.push(pair);
		for (flag in ashArgs)
			reply.ashArgs.push(flag);
		for (page in pageFiles)
			reply.pageFiles.push(page);
		return reply;
	}

	// Returns the haxe arguments for the app of the hook request, and collects its Ash
	// arguments and web page files.
	static function build():Array<Array<String>> {
		var project:Dynamic = request.context.project;
		file = Path.join([project.directory, "hxnme.toml"]);
		overrides = {};
		ashArgs.resize(0);
		pageFiles.resize(0);
		var target:Dynamic = request.context.target;
		if (target != null)
			triple = target.triple != null ? target.triple : host();
		var args = [];
		// Metal's shader compiler selects its SDK by these Haxe defines, not hxn_triple.
		if (triple.indexOf("apple-ios") >= 0)
			args.push(["-D", StringTools.endsWith(triple, "-sim") || StringTools.startsWith(triple, "x86_64-") ? "iphonesim" : "iphoneos"]);
		var command = request.context.command;
		if (command == "run" || command == "check")
			args.push(["-D", "hxnme_reload"]);
		if (!FileSystem.exists(file))
			return args;
		args.push(["-D", 'hxnme_project=${Path.normalize(FileSystem.absolutePath(file))}']);
		var toml:Dynamic = try Toml.parse(File.getContent(file), file) catch (error:String) fail(error);
		var app:Dynamic = toml.app;
		if (app != null && app.preset != null)
			ashArgs.push(["--preset", string(app.preset, "app.preset", file)]);
		// hxn names the app bundle for iOS by it.
		if (app != null && app.id != null)
			args.push(["-D", 'hxn_bundle_id=${string(app.id, "app.id", file)}']);
		var plugins:Array<Dynamic> = toml.plugins == null ? [] : toml.plugins;
		if (!Std.isOfType(plugins, Array))
			fail('$file: `plugins` must be an array of haxelib names');
		if (toml.libraries != null)
			overrides = toml.libraries;
		var selected = project.hxml == null ? [] : libraries(File.getContent(project.hxml));
		// The program file already selects these plugins, but the compiler does
		// not have their target libraries yet.
		var seen = selected.copy();
		for (name in selected) {
			var root = find(name);
			if (root != null)
				targetLibraries(Json.parse(File.getContent(Path.join([root, "haxelib.json"]))), root, project.directory, seen, args);
		}
		for (plugin in plugins)
			add(string(plugin, "plugins", file), project.directory, seen, args);
		return args;
	}

	/**
		Returns the haxe and Ash arguments that `hxn run hl` uses for the program file
		`hxml` in `directory`, whose output goes to `output`: those of this hook, and those
		of the hooks of the haxelibs that the program file selects, with their dependencies.
	**/
	@:allow(hxn.me.cli.Dev) static function arguments(directory:String, hxml:String, output:String):{haxe:Array<Array<String>>, ash:Array<Array<String>>} {
		request = {
			version: 1,
			kind: "hook",
			phase: "before-build",
			context: {
				command: "run",
				project: {directory: directory, hxml: hxml, library: null, haxelib: null},
				target: {runtime: "hl", wasm: false, threads: false, triple: null},
				output: output
			}
		};
		var args = build();
		var seen = ["hxnme"];
		for (phase in ["before-build", "after-build"]) {
			request.phase = phase;
			for (name in libraries(File.getContent(hxml)))
				forwardSelected(name, seen.copy(), args);
		}
		return {haxe: args, ash: ashArgs.copy()};
	}

	static function forwardSelected(name:String, seen:Array<String>, args:Array<Array<String>>) {
		var root = find(name);
		if (root == null)
			return;
		var info:Dynamic = Json.parse(File.getContent(Path.join([root, "haxelib.json"])));
		for (dependency in Reflect.fields(info.dependencies == null ? {} : info.dependencies))
			if (!seen.contains(dependency)) {
				seen.push(dependency);
				forwardSelected(dependency, seen, args);
			}
		if (name != "hxnme")
			forward(info, root, args);
	}

	// Copies the game template into `cwd/name`, with the app's id and title filled in.
	@:allow(hxn.me.cli.NewCommand) static function create(name:String, cwd:String, root:String):Void {
		if (!~/^[A-Za-z][A-Za-z0-9_-]*$/.match(name))
			fail('$name is not a directory name for a project: use letters, digits, - and _, starting with a letter');
		var into = Path.join([cwd, name]);
		if (FileSystem.exists(into))
			fail('$into already exists');
		var template = Path.join([root, "templates", "game"]);
		if (!FileSystem.isDirectory(template))
			fail('hxnme has no game template at $template');
		var title = [for (word in ~/[-_]+/g.split(name)) if (word.length > 0) word.charAt(0).toUpperCase() + word.substr(1)].join(" ");
		copy(template, into, ["{{id}}" => name.toLowerCase(), "{{title}}" => title]);
		Sys.println('Created $into. Run it with: cd $name && hxn run hl app.hxml');
	}

	static function copy(from:String, into:String, fill:Map<String, String>):Void {
		FileSystem.createDirectory(into);
		for (entry in FileSystem.readDirectory(from)) {
			var source = Path.join([from, entry]);
			// Packages can drop dotfiles, so the template keeps .gitignore without its dot.
			var target = Path.join([into, entry == "gitignore" ? ".gitignore" : entry]);
			if (FileSystem.isDirectory(source))
				copy(source, target, fill);
			else if (entry == "hxnme.toml") {
				var text = File.getContent(source);
				for (key => value in fill)
					text = text.split(key).join(value);
				File.saveContent(target, text);
			} else
				File.copy(source, target);
		}
	}

	// Adds the haxe arguments that `-lib` gives for `entry`, after those
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
		forward(info, root, args);
		var extra = Path.join([root, "extraParams.hxml"]);
		if (FileSystem.exists(extra))
			for (pair in pairs(File.getContent(extra), extra))
				args.push(pair);
		targetLibraries(info, root, base, seen, args);
	}

	// Runs the hook of the haxelib at `root` for this phase, if it registers one, as hxn does
	// for a haxelib that the program file selects, and adds what the hook returns to the reply.
	// hxn runs hooks only for the haxelibs that the program file selects, so a haxelib that
	// hxnme.toml brings in, such as hxn-window with its browser agent, gets its hook here.
	static function forward(info:Dynamic, root:String, args:Array<Array<String>>) {
		var cli:Dynamic = info.hxn == null ? null : info.hxn.cli;
		if (cli == null || cli.hooks == null || (cli.hooks : Array<String>).indexOf(request.phase) < 0)
			return;
		var command:Array<String> = [for (part in (cli.command : Array<String>)) StringTools.replace(part, "{root}", root)];
		var forwarded = Json.parse(Json.stringify(request));
		forwarded.library = info.name;
		forwarded.root = root;
		var process = new Process(command[0], command.slice(1));
		process.stdin.writeString(Json.stringify(forwarded));
		process.stdin.close();
		var out = process.stdout.readAll().toString();
		var err = process.stderr.readAll().toString();
		var code = process.exitCode();
		process.close();
		if (err.length > 0)
			Sys.stderr().writeString(err);
		if (code != 0)
			fail('the ${request.phase} hook of ${info.name} failed with status $code');
		var reply:Dynamic = try Json.parse(out) catch (e:Dynamic) fail('the ${request.phase} hook of ${info.name} returned no JSON reply: $out');
		if (reply.haxe_args != null)
			for (pair in (reply.haxe_args : Array<Array<String>>))
				args.push(pair);
		if (reply.ash_args != null)
			for (flag in (reply.ash_args : Array<Array<String>>))
				ashArgs.push(flag);
		if (reply.page_files != null)
			for (page in (reply.page_files : Array<String>))
				if (pageFiles.indexOf(page) < 0)
					pageFiles.push(page);
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

	// Returns the flags of an extraParams.hxml, each with its value. hxn's hooks take
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

	// Returns the haxelibs that a program file selects with -lib, -L or --library.
	@:allow(hxn.me.cli.Dev) static function libraries(text:String):Array<String> {
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
	@:allow(hxn.me.cli.Dev) static function find(name:String):Null<String> {
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

	static function fail(message:String):Dynamic
		throw new Failure(message);
}
