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
		remove(app);
		FileSystem.createDirectory(app);
		write("app.hxml", "-lib hxnme\n-main App\n");
		write("hxnme.toml", "[app]\nrate = 60\n");
		write("App.hx", "class App {\n\tstatic function main()\n\t\thxn.me.App.run(Probe);\n}\n");
		write("Probe.hx", probe('"one"'));
		var ash = Sys.getEnv("ASH");
		command = new Process("haxe", [
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

		write("hxnme.toml", "[app]\nrate = 61\n");
		expect("the app restarts after hxnme.toml changes", until("[dev] hxnme.toml changed") != null && until("probe four ") != null);

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
			Sys.println("probe " + label() + " " + printed);
		}
		if (sys.FileSystem.exists("crash"))
			throw "crashed";
		if (sys.FileSystem.exists("stop"))
			lifecycle.quit();
	}
}
';

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
