import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import sys.thread.Mutex;
import sys.thread.Thread;

/**
	Runs `hxn me dev` on an app without a window, changes the app's files, and checks what
	the running app and the command do. It runs on Ash, and `ASH` gives the Ash command,
	which is `ash` by default.
**/
class Main {
	// The number of seconds to wait for something to appear in the output.
	static inline final LIMIT = 90;
	#if !macro
	static final root = Path.normalize(Path.join([here(), "..", ".."]));
	static final app = Path.join([here(), "bin", "dev"]);
	#end
	static final lock = new Mutex();
	static final lines:Array<String> = [];
	static var command:Process;
	static var seen = 0;

	#if !macro
	static function main() {
		if (Sys.args()[0] == "web") {
			var ash = Sys.getEnv("ASH");
			Sys.exit(Sys.command("node", [Path.join([here(), "web.mjs"]), root, ash == null ? "ash" : ash]));
			return;
		}
		remove(app);
		FileSystem.createDirectory(app);
		write("app.hxml", "-lib hxnme\n-main App\n");
		write("hxnme.toml", "[app]\nrate = 60\n");
		write("App.hx", "class App {\n\tstatic function main()\n\t\thxn.me.App.run(Probe, Show);\n}\n");
		write("Probe.hx", probe('"one"'));
		write("Files.hx", FILES);
		write("Show.hx", show("first"));
		FileSystem.createDirectory(Path.join([app, "assets"]));
		for (name in ["text", "box", "pair", "closed"])
			write('assets/$name.txt', name + "1");
		write("assets/level.json", '{"name": "level1"}');
		write("assets/built.json", '{"name": "built1"}');
		var ash = Sys.getEnv("ASH");
		command = new Process("haxe", [
			"-lib",
			"hxn",
			"-cp",
			Path.join([root, "tools"]),
			"-cp",
			Path.join([root, "src"]),
			"--run",
			"hxn.me.cli.Tool"
		]);
		command.stdin.writeString(Json.stringify({
			version: 1,
			kind: "command",
			library: "hxnme",
			root: root,
			cwd: app,
			arguments: ["dev", "--ash", ash == null ? "ash" : ash]
		}));
		command.stdin.close();
		Thread.create(() -> read(command.stdout));
		Thread.create(() -> read(command.stderr));

		expect("the app starts", until("probe one ") != null);

		write("Probe.hx", probe('"two"'));
		var reloaded = until("probe two ");
		expect("a changed function runs in the running app", reloaded != null);
		expect("the app keeps its state", reloaded != null && count(reloaded) > 1);

		write("Probe.hx", probe('"three" + more()', "\tstatic function more():Int\n\t\treturn 14;\n\n"));
		expect("the command reports a change that Ash refuses", until("[dev] Ash cannot reload this change") != null);
		var restarted = until("probe three14 ");
		expect("the app restarts with the change", restarted != null && count(restarted) == 1);

		write("Probe.hx", probe("nothing"));
		expect("the command prints the compile error", until("Unknown identifier : nothing") != null);
		expect("the running app stays as it is", until("probe three14 ") != null);

		write("Probe.hx", probe('"four"', "\tstatic function more():Int\n\t\treturn 14;\n\n"));
		expect("the app reloads after the error is fixed", until("probe four ") != null);

		write("hxnme.toml", "[app]\nrate = 60\nstep = 30\n");
		expect("the app restarts after hxnme.toml changes", until("[dev] hxnme.toml changed") != null);
		expect("the app gets the new value", until("probe four 30 ") != null);

		write("hxnme.toml", "[app]\nrate = 60\nstep = \"often\"\n");
		expect("the command prints the error in hxnme.toml", until("`app.step` must be a number") != null);
		write("hxnme.toml", "[app]\nrate = 60\nstep = 60\n");
		expect("the app restarts after the error is fixed", until("probe four 60 ") != null);

		write("More.hx", more("one"));
		write("App.hx", "class App {\n\tstatic function main()\n\t\thxn.me.App.run(Probe, Show, More);\n}\n");
		expect("the app runs a system of a new class", until("more one") != null);
		write("More.hx", more("two"));
		expect("a changed system runs in the running app", until("more two") != null);
		write("App.hx", "class App {\n\tstatic function main()\n\t\thxn.me.App.run(Probe, Show);\n}\n");
		FileSystem.deleteFile(Path.join([app, "More.hx"]));
		expect("the app runs without the class after it is deleted", until("[dev] compiled") != null && stops("more two"));

		expect("the app shows its assets", until("first text1 0 level1 box1 pair1+box1 closed1 built1 ") != null);
		write("assets/text.txt", "text2");
		var changed = until("first text2 1 level1 ");
		expect("a changed text loads in the running app", changed != null && count(changed) > 1);
		write("assets/box.txt", "box2");
		expect("a value that the app keeps gets the change, and the value that depends on it", until(" box2 pair1+box2 ") != null);
		write("assets/level.json", '{"name": ');
		expect("the command reports data that does not load", until("[dev] level.json does not load") != null);
		expect("the app keeps the data from before", until(" level1 ") != null);
		write("assets/level.json", '{"name": "level2"}');
		expect("the data loads after it is fixed", until(" level2 ") != null);
		write("assets/text.txt", "text3");
		write("Show.hx", show("second"));
		expect("changed code runs with the text that changed with it", until("second text3 ") != null && !printed("second text2 "));
		write("assets/closed.txt", "closed2");
		expect("the app restarts for a type that cannot take a change", until("[dev] closed.txt changed, so the app restarts") != null);
		expect("the app shows the files after the restart", until("second text3 0 level2 box2 pair1+box2 closed2 built1 ") != null);
		write("assets/built.json", '{"name": "built2"}');
		expect("the app restarts for data in its code", until("[dev] built.json changed, so the app restarts") != null && until(" built2 ") != null);
		write("assets/notes.txt", "notes");
		write("assets/text.txt", "text4");
		expect("a file that the app does not declare changes nothing", until(" text4 1 ") != null);

		write("crash", "");
		expect("the command reports a crash", until("[dev] the app exited with status") != null);
		FileSystem.deleteFile(Path.join([app, "crash"]));
		write("Probe.hx", probe('"five"'));
		expect("the app starts again after the next change", until("probe five ") != null);

		write("stop", "");
		expect("the command ends with the app", command.exitCode() == 0);
		command.close();
		Sys.println("Dev checks passed");
	}

	// Returns the source of a system that prints `label` and a count ten times a second.
	static function probe(label:String, more = ""):String
		return 'import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

class Probe {
	static var printed = 0;

$more	static function label():String
		return $label;

	@:system(Update)
	static function tick(time:Res<Time>, lifecycle:ResMut<Lifecycle>) {
		if (time.frame % 6 == 0) {
			printed++;
			Sys.println("probe " + label() + " " + Math.round(1 / time.step) + " " + printed);
		}
		if (sys.FileSystem.exists("crash"))
			throw "crashed";
		if (sys.FileSystem.exists("stop"))
			lifecycle.quit();
	}
}
';

	// Returns the source of a class with a system that prints `label` ten times a second.
	static function more(label:String):String
		return 'import hxn.me.Res;
import hxn.me.Time;

class More {
	@:system(Update)
	static function tick(time:Res<Time>)
		if (time.frame % 6 == 0)
			Sys.println("more $label");
}
';

	// Declares files of types that the app can change in different ways.
	static final FILES = 'import hxn.Future;
import hxn.me.AssetRef;
import hxn.me.AssetType;

typedef Named = {name:String};

class Box {
	public var text:String;

	public function new(text:String)
		this.text = text;
}

class Types {
	public static final box = new AssetType<Box>("box", (bytes, _) -> Future.resolved(new Box(bytes.toString())), _ -> {}, (box, by) -> {
		box.text = by.text;
		true;
	});
	public static final pair = new AssetType<String>("pair", (bytes, context) -> context.load("box.txt", box).map(box -> bytes.toString() + "+" + box.text));
	public static final closed = new AssetType<String>("closed", (bytes, _) -> Future.resolved(bytes.toString()), _ -> {});
}

@:build(hxn.me.Assets.build())
class Files {
	@:asset("text.txt") public static var Text:AssetRef<String>;
	@:asset("level.json") public static var Level:AssetRef<Named>;
	@:asset("box.txt") @:assetType(Files.Types.box) public static var Boxed:AssetRef<Box>;
	@:asset("pair.txt") @:assetType(Files.Types.pair) public static var Pair:AssetRef<String>;
	@:asset("closed.txt") @:assetType(Files.Types.closed) public static var Closed:AssetRef<String>;
	@:asset("built.json") public static var Built:Named;
}
';

	// Returns the source of a system that prints `label` and what the files of `Files` hold ten times a second.
	static function show(label:String):String
		return 'import hxn.me.Asset;
import hxn.me.Assets;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

class Show {
	static var text:Asset<String>;
	static var level:Asset<Files.Named>;
	static var box:Files.Box;
	static var pair:Asset<String>;
	static var closed:Asset<String>;
	static var printed = 0;

	@:system(Start)
	static function start(assets:ResMut<Assets>) {
		var store:Assets = assets;
		store.load(Files.Text).then(a -> text = a);
		store.load(Files.Level).then(a -> level = a);
		store.load(Files.Boxed).then(a -> box = a.value);
		store.load(Files.Pair).then(a -> pair = a);
		store.load(Files.Closed).then(a -> closed = a);
	}

	@:system(Update)
	static function tick(time:Res<Time>) {
		if (time.frame % 6 != 0 || text == null || level == null || box == null || pair == null || closed == null)
			return;
		printed++;
		Sys.println("$label " + [
			text.value, Std.string(text.revision), level.value.name, box.text, pair.value, closed.value, Files.Built.name, Std.string(printed)
		].join(" "));
	}
}
';

	// Returns whether the app printed `text` at any time.
	static function printed(text:String):Bool {
		lock.acquire();
		var found = Lambda.exists(lines, line -> line.indexOf(text) >= 0);
		lock.release();
		return found;
	}

	static function count(line:String):Int
		return Std.parseInt(line.split(" ").pop());

	// Writes the whole file in one step, so that the command never compiles a part of it.
	static function write(name:String, text:String) {
		// What the app prints from here on counts for the next `until`.
		lock.acquire();
		seen = lines.length;
		lock.release();
		var path = Path.join([app, name]);
		File.saveContent(path + ".new", text);
		FileSystem.rename(path + ".new", path);
	}

	// Returns the first line after the last file change that contains `text`, or null after
	// `LIMIT` seconds. The next call starts at the line after it.
	static function until(text:String):Null<String> {
		var end = Sys.time() + LIMIT;
		while (Sys.time() < end) {
			lock.acquire();
			while (seen < lines.length) {
				var line = lines[seen++];
				if (line.indexOf(text) >= 0) {
					lock.release();
					return line;
				}
			}
			lock.release();
			Sys.sleep(0.05);
		}
		return null;
	}

	// Returns whether the app stops printing `text`, within 20 lines of the probe.
	static function stops(text:String):Bool {
		for (_ in 0...20)
			if (until("probe ") == null)
				return false;
		var from = seen;
		for (_ in 0...10)
			if (until("probe ") == null)
				return false;
		lock.acquire();
		var printed = [for (i in from...seen) if (lines[i].indexOf(text) >= 0) i];
		lock.release();
		return printed.length == 0;
	}

	static function read(input:haxe.io.Input) {
		try
			while (true) {
				var line = StringTools.rtrim(input.readLine());
				lock.acquire();
				lines.push(line);
				lock.release();
			}
		catch (_:haxe.io.Eof) {}
	}

	// Ends the check at the first failure. The app then ends too, as it does after a pass.
	static function expect(name:String, ok:Bool) {
		Sys.println('$name: ${ok ? "yes" : "no"}');
		if (ok)
			return;
		write("stop", "");
		lock.acquire();
		Sys.stderr().writeString(lines.join("\n") + "\n");
		lock.release();
		Sys.sleep(3);
		command.kill();
		Sys.exit(1);
	}

	static function remove(path:String) {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				remove(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}

	#end

	// Returns the directory of this check, fixed at compile time.
	static macro function here():haxe.macro.Expr
		return macro $v{sys.FileSystem.absolutePath(".")};
}
