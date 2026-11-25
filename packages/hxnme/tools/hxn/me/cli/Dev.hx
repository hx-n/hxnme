package hxn.me.cli;

import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Path;
import hxn.me.cli.Tool.Failure;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import sys.thread.Deque;
import sys.thread.Thread;

/**
	`Dev` runs an app on Ash while its sources change. It compiles the program file,
	starts it with `ash --hot-reload`, and compiles again when a file changes. One Haxe
	compiler stays in memory for every compile. The running program then gets the new
	bytecode, and the app loop reloads it at the start of a frame. The program restarts
	when a change cannot reload: a change to `hxnme.toml`, a program file or an asset, or
	a change that Ash refuses.

	Each compile writes to the `build` directory, and the program runs from the `run`
	directory. The compile copies the native libraries next to its output, and the
	program has its copies loaded.

	`Dev` itself runs on Ash. In Haxe's interpreter, where `Tool` runs, one thread that
	waits for output of the program stops every other thread.
**/
class Dev {
	// The number of seconds between two looks at the files, and the time that the files
	// must stay as they are before a compile, because editors can save in several writes.
	static inline final INTERVAL = 0.2;
	static inline final SETTLE = 0.05;
	// The number of seconds for which a file that changed is read again on each look.
	static inline final RECENT = 3;

	// Matches the line that Ash prints when it cannot load a change, with the reason.
	static final REFUSAL = ~/^\[hot-reload\] reload (?:refused|failed): (?:the program cannot reload in place: )?(.*)$/;

	final directory:String;
	final hxml:String;
	final ash:Array<String>;
	final built:String;
	final running:String;
	// Gets the reason each time that Ash refuses a reload.
	final refusals = new Deque<String>();
	final compiler = new Compiler();
	// The files that changed after the last compile.
	final uncompiled:Array<String> = [];

	var arguments:{haxe:Array<Array<String>>, ash:Array<Array<String>>};
	var program:Null<Process>;
	// Gets an entry from each reader of the program's output after it passed all of it on.
	var ended = new Deque<Bool>();

	static function main() {
		var dev = parse(Sys.args(), Sys.getCwd());
		var status = 1;
		try
			status = dev.run()
		catch (failure:Failure)
			Sys.stderr().writeString(failure.message + "\n");
		Sys.exit(status);
	}

	/**
		Compiles `Dev` and runs it on Ash with the arguments of `hxn me dev`. Returns its
		status, or null if the arguments are not valid.
	**/
	public static function launch(arguments:Array<String>, cwd:String, root:String):Null<Int> {
		var dev = parse(arguments, cwd);
		if (dev == null)
			return null;
		if (!FileSystem.exists(dev.hxml))
			throw new Failure('${dev.hxml} does not exist');
		var out = Path.directory(dev.built);
		FileSystem.createDirectory(out);
		var tool = Path.join([out, "dev.hl"]);
		var compile = Sys.command("haxe", [
			"-cp", Path.join([root, "tools"]), "-cp", Path.join([root, "src"]), "-main", "hxn.me.cli.Dev", "-hl", tool
		]);
		return compile != 0 ? compile : Sys.command(dev.ash[0], [tool, dev.hxml, "--ash", dev.ash.join(" ")]);
	}

	/** Returns a `Dev` for the arguments of `hxn me dev`, or null if they are not valid. **/
	static function parse(arguments:Array<String>, cwd:String):Null<Dev> {
		var file = null;
		var ash = Sys.getEnv("HXN_ASH");
		var i = 0;
		while (i < arguments.length) {
			switch arguments[i] {
				case "--ash" if (i + 1 < arguments.length):
					ash = arguments[++i];
				case value if (file == null && StringTools.endsWith(value, ".hxml")):
					file = value;
				case _:
					return null;
			}
			i++;
		}
		if (file == null)
			file = "app.hxml";
		if (!Path.isAbsolute(file))
			file = Path.join([cwd, file]);
		return new Dev(Path.normalize(file), ash == null ? "ash" : ash);
	}

	function new(file:String, ash:String) {
		directory = Path.directory(file);
		hxml = file;
		this.ash = [for (word in ~/\s+/g.split(ash)) if (word != "") word];
		var out = Path.join([directory, "bin", Path.withoutExtension(Path.withoutDirectory(file)), "dev"]);
		built = Path.join([out, "build"]);
		running = Path.join([out, "run"]);
	}

	/** Runs the app until it exits with status 0, and returns the status for the command. **/
	public function run():Int {
		try {
			var status = loop();
			compiler.close();
			return status;
		} catch (failure:haxe.Exception) {
			// The program does not end with this command.
			stop();
			compiler.close();
			throw failure;
		}
	}

	function loop():Int {
		Sys.setCwd(directory);
		arguments = Tool.arguments(directory, hxml, built);
		var before = snapshot();
		if (compile())
			start();
		while (true) {
			Sys.sleep(INTERVAL);
			var status = program == null ? null : program.exitCode(false);
			if (status != null) {
				finish();
				if (status == 0)
					return 0;
				say('the app exited with status $status. It starts again after the next change.');
			}
			var refused = refusals.pop(false);
			if (refused != null && program != null)
				restart('Ash cannot reload this change ($refused)');
			var now = snapshot();
			var changed = difference(before, now);
			if (changed.length == 0)
				continue;
			while (true) {
				Sys.sleep(SETTLE);
				var later = snapshot();
				if (difference(now, later).length == 0)
					break;
				now = later;
			}
			changed = difference(before, now);
			before = now;
			apply(changed);
		}
	}

	function apply(changed:Array<String>) {
		for (path in changed)
			if (!uncompiled.contains(path))
				uncompiled.push(path);
		var sources = true;
		for (path in changed)
			if (Path.extension(path) != "hx")
				sources = false;
		if (!sources)
			try
				arguments = Tool.arguments(directory, hxml, built)
			catch (failure:Failure) {
				say(failure.message);
				return;
			}
		if (!compile())
			return;
		if (program == null)
			start();
		else if (sources)
			swap();
		else
			restart('${relative(changed)} changed');
	}

	// Compiles the program file. After an error, the running program stays as it is.
	function compile():Bool {
		FileSystem.createDirectory(built);
		var from = Sys.time();
		var args = [Path.withoutDirectory(hxml)];
		for (pair in arguments.haxe)
			for (word in pair)
				if (word != "")
					args.push(word);
		args = args.concat(["-hl", Path.join([built, "main.hl"])]);
		var result = compiler.compile(directory, args, uncompiled);
		uncompiled.resize(0);
		if (!result.success) {
			Sys.print(result.output);
			say(program == null ? "the app does not compile." : "the app does not compile, and the running program stays as it is.");
			return false;
		}
		say('compiled in ${Math.round((Sys.time() - from) * 10) / 10} s');
		return true;
	}

	// Copies the build to the directory that the program runs from, and starts it. The
	// directory is new for each start, because macOS refuses to load a library that was
	// written over a file it loaded before.
	function start() {
		remove(running);
		copy(built, running);
		while (refusals.pop(false) != null) {}
		var command = ash.slice(1).concat(["--hot-reload"]);
		for (entry in arguments.ash)
			if (!command.contains(entry[0]))
				command = command.concat(entry);
		command.push(Path.join([running, "main.hl"]));
		for (variable in ["DYLD_LIBRARY_PATH", "LD_LIBRARY_PATH"])
			Sys.putEnv(variable, running);
		if (Sys.systemName() == "Windows" && !paths.contains(running)) {
			paths.push(running);
			Sys.putEnv("PATH", running + ";" + Sys.getEnv("PATH"));
		}
		var started = new Process(ash[0], command);
		program = started;
		ended = new Deque();
		var ended = ended;
		Thread.create(() -> {
			var buffer = Bytes.alloc(4096);
			try
				while (true) {
					var read = started.stdout.readBytes(buffer, 0, buffer.length);
					Sys.stdout().writeBytes(buffer, 0, read);
					Sys.stdout().flush();
				}
			catch (_:Eof) {}
			ended.add(true);
		});
		Thread.create(() -> {
			try
				while (true) {
					var line = started.stderr.readLine();
					// Haxe's interpreter, which started this command, passes on its error output only at the end.
					Sys.stdout().writeString(line + "\n");
					Sys.stdout().flush();
					if (REFUSAL.match(line))
						refusals.add(REFUSAL.matched(1));
				}
			catch (_:Eof) {}
			ended.add(true);
		});
	}

	static final paths:Array<String> = [];

	// Ends the program if it runs, and waits until its output is passed on.
	function stop() {
		if (program == null)
			return;
		program.kill();
		program.exitCode();
		finish();
	}

	// Waits until the readers passed on the output of the program that ended.
	function finish() {
		for (_ in 0...2)
			ended.pop(true);
		program.close();
		program = null;
	}

	function restart(why:String) {
		say('$why, so the app restarts.');
		stop();
		start();
	}

	// Puts the new bytecode in place of the bytecode that the program runs, in one step, so
	// that Ash never reads a part of it.
	function swap() {
		var next = Path.join([running, "main.hl.next"]);
		File.copy(Path.join([built, "main.hl"]), next);
		FileSystem.rename(next, Path.join([running, "main.hl"]));
	}

	// Returns the state of each file that the app is made from.
	function snapshot():Map<String, String> {
		var found = new Map<String, String>();
		function note(path:String)
			try {
				found[path] = state(path);
			} catch (_:haxe.Exception) {}
		function walk(path:String, take:String->Bool)
			try
				for (entry in FileSystem.readDirectory(path)) {
					var child = Path.join([path, entry]);
					if (StringTools.startsWith(entry, ".") || child == Path.join([directory, "bin"]))
						continue;
					if (FileSystem.isDirectory(child))
						walk(child, take);
					else if (take(entry))
						note(child);
				}
			catch (_:haxe.Exception) {}
		for (path in classPaths())
			walk(path, name -> Path.extension(name) == "hx");
		walk(assets(), _ -> true);
		note(hxml);
		note(Path.join([directory, "hxnme.toml"]));
		return found;
	}

	// Returns the size, the time and the checksum of a file.
	function state(path:String):String {
		var stat = FileSystem.stat(path);
		var time = stat.mtime.getTime();
		var now = '$time ${stat.size}';
		var known = states[path];
		// A file can change twice in the second that its time is measured in, and keep its size.
		if (known == null || known.now != now || time > Date.now().getTime() - RECENT * 1000)
			states[path] = known = {now: now, sum: Crc32.make(File.getBytes(path))};
		return '$now ${known.sum}';
	}

	final states = new Map<String, {now:String, sum:Int}>();

	// Returns the class paths of the app: its directory, those of its program file, of the
	// haxelibs that the program file selects, and of its plugins.
	function classPaths():Array<String> {
		var found = [directory];
		function add(path:String) {
			var full = Path.removeTrailingSlashes(Path.normalize(Path.isAbsolute(path) ? path : Path.join([directory, path])));
			if (!found.contains(full))
				found.push(full);
		}
		var text = try File.getContent(hxml) catch (_:haxe.Exception) "";
		var words = [for (word in ~/\s+/g.split(text)) if (word != "") word];
		for (i in 0...words.length - 1)
			if (words[i] == "-cp" || words[i] == "-p" || words[i] == "--class-path")
				add(words[i + 1]);
		for (name in Tool.libraries(text)) {
			var root = roots.exists(name) ? roots[name] : Tool.find(name);
			roots[name] = root;
			if (root != null) {
				var info = haxe.Json.parse(File.getContent(Path.join([root, "haxelib.json"])));
				add(Path.join([root, info.classPath == null ? "" : info.classPath]));
			}
		}
		for (pair in arguments.haxe)
			if (pair[0] == "-cp")
				add(pair[1]);
		return found;
	}

	// The directories of the haxelibs that the program file selects. haxelib finds them, and takes too long to ask on each look.
	final roots = new Map<String, Null<String>>();

	// Returns the directory that hxn-assets bundles.
	function assets():String {
		for (pair in arguments.haxe)
			if (pair[0] == "-D" && StringTools.startsWith(pair[1], "hxn_assets_dir="))
				return pair[1].substr("hxn_assets_dir=".length);
		return Path.join([directory, "assets"]);
	}

	static function difference(before:Map<String, String>, after:Map<String, String>):Array<String> {
		var changed = [for (path => state in after) if (before[path] != state) path];
		for (path in before.keys())
			if (!after.exists(path))
				changed.push(path);
		return changed;
	}

	function relative(paths:Array<String>):String {
		var other = [
			for (path in paths)
				if (Path.extension(path) != "hx") StringTools.startsWith(path, directory + "/") ? path.substr(directory.length + 1) : path
		];
		return other.join(", ");
	}

	static function copy(from:String, into:String) {
		FileSystem.createDirectory(into);
		for (entry in FileSystem.readDirectory(from)) {
			var source = Path.join([from, entry]);
			var target = Path.join([into, entry]);
			if (FileSystem.isDirectory(source))
				copy(source, target);
			else
				File.copy(source, target);
		}
	}

	static function remove(path:String) {
		if (!FileSystem.exists(path))
			return;
		for (entry in FileSystem.readDirectory(path)) {
			var child = Path.join([path, entry]);
			if (FileSystem.isDirectory(child))
				remove(child);
			else
				FileSystem.deleteFile(child);
		}
		FileSystem.deleteDirectory(path);
	}

	static function say(message:String) {
		Sys.println('[dev] $message');
		Sys.stdout().flush();
	}
}
