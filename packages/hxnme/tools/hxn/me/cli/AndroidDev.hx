package hxn.me.cli;

import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Path;
import hxn.cli.Failure;
import hxn.me.dev.Update;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import sys.net.Host;
import sys.thread.Deque;
import sys.thread.Thread;

/**
	`AndroidDev` runs an app on the connected Android device or emulator, and gives it
	each change. A warm Haxe compile, as `Dev` makes, checks each change first. When only
	assets changed, the running app gets them through `hxn.me.dev.Session`, whose socket
	reaches this command through `adb reverse`. Other changes build the app with
	`hxn build`, install it again and restart it, because the app is native code that
	Ash built ahead of time.
**/
class AndroidDev {
	// The number of looks at the files between two checks that the app still runs.
	static inline final ALIVE = 5;

	final watch:Dev;
	final adb:String;
	var triple = "";
	var activity = "";
	// The bytecode of the warm compile that the installed app was built from.
	var installed:Null<Bytes>;
	// The assets that changed after the install, which the installed APK has from before.
	final since:Array<String> = [];
	var running = false;
	var log:Null<Process>;

	static function main() {
		var args = Sys.args();
		var dev = new AndroidDev(args[0], args[1]);
		try
			dev.run()
		catch (failure:haxe.Exception) {
			dev.stop();
			Sys.stderr().writeString(failure.message + "\n");
			Sys.exit(1);
		}
	}

	/** Runs the Android development command on Ash, as the desktop development command does. **/
	public static function launch(file:String, ash:String, cwd:String, root:String):Int {
		var full = Path.normalize(Path.isAbsolute(file) ? file : Path.join([cwd, file]));
		if (!FileSystem.exists(full))
			throw new Failure('$full does not exist');
		var out = Path.join([Path.directory(full), "bin", Path.withoutExtension(Path.withoutDirectory(full)), "dev-android"]);
		FileSystem.createDirectory(out);
		var tool = Path.join([out, "dev.hl"]);
		var compile = Sys.command("haxe", [
			"-lib", "hxn", "-cp", Path.join([root, "tools"]), "-cp", Path.join([root, "src"]), "-main", "hxn.me.cli.AndroidDev", "-hl", tool
		]);
		var command = [for (word in ~/\s+/g.split(ash)) if (word != "") word];
		if (command.length == 0)
			throw new Failure("The Ash command is empty.");
		return compile != 0 ? compile : Sys.command(command[0], command.slice(1).concat([tool, full, ash]));
	}

	function new(file:String, ash:String) {
		watch = new Dev(file, ash, "dev-android");
		var home = Sys.getEnv("ANDROID_HOME");
		var sdk = home == null ? null : Path.join([home, "platform-tools", Sys.systemName() == "Windows" ? "adb.exe" : "adb"]);
		adb = sdk != null && FileSystem.exists(sdk) ? sdk : "adb";
	}

	function run():Void {
		Sys.setCwd(watch.directory);
		var state = call(["get-state"]);
		if (state.status != 0 || StringTools.trim(state.output) != "device")
			throw new Failure("No Android device or emulator is connected. Start an emulator, or connect a device with USB debugging on.");
		var abi = StringTools.trim(call(["shell", "getprop", "ro.product.cpu.abi"]).output);
		triple = switch abi {
			case "arm64-v8a": "aarch64-linux-android";
			case "x86_64": "x86_64-linux-android";
			case _: throw new Failure('hxn me dev android does not build for the device ABI $abi.');
		}
		watch.listener.bind(new Host("127.0.0.1"), 0);
		watch.listener.listen(1);
		var port = watch.listener.host().port;
		// The hook compiles this address into the app. On the device, adb reverse
		// forwards it to this command.
		Sys.putEnv("HXNME_DEV", '127.0.0.1:$port');
		if (call(["reverse", 'tcp:$port', 'tcp:$port']).status != 0)
			throw new Failure('adb cannot forward port $port from the device.');
		arguments();
		var before = watch.snapshot();
		if (watch.compile())
			deploy(null);
		var looks = 0;
		while (true) {
			Sys.sleep(Dev.INTERVAL);
			watch.exchange();
			if (watch.asked != null)
				deploy(watch.asked);
			if (running && ++looks % ALIVE == 0 && !alive()) {
				running = false;
				Dev.say("the app ended. It starts again after the next change.");
			}
			var now = watch.snapshot();
			if (Dev.difference(before, now).length == 0)
				continue;
			while (true) {
				Sys.sleep(Dev.SETTLE);
				var later = watch.snapshot();
				if (Dev.difference(now, later).length == 0)
					break;
				now = later;
			}
			var changed = Dev.difference(before, now);
			before = now;
			apply(changed);
		}
	}

	function apply(changed:Array<String>) {
		for (path in changed)
			if (!watch.uncompiled.contains(path))
				watch.uncompiled.push(path);
		var assets = watch.assets() + "/";
		var changedAssets = [
			for (path in changed)
				if (StringTools.startsWith(path, assets)) path.substr(assets.length)
		];
		var changedFiles = [
			for (path in changed)
				if (Path.extension(path) != "hx" && !StringTools.startsWith(path, assets)) path
		];
		if (changedFiles.length > 0)
			try
				arguments()
			catch (failure:Failure) {
				Dev.say(failure.message);
				return;
			}
		if (!watch.compile())
			return;
		var code = File.getBytes(Path.join([watch.built, "main.hl"]));
		if (changedFiles.length > 0)
			deploy('${watch.relative(changedFiles)} changed');
		else if (installed == null || code.compare(installed) != 0)
			deploy("the code changed");
		else if (watch.embedded(changedAssets).length > 0)
			deploy('${watch.embedded(changedAssets).join(", ")} changed');
		else {
			for (path in changedAssets)
				if (!since.contains(path))
					since.push(path);
			if (running)
				send(changedAssets);
			else {
				// The installed app has the code, so it starts again and gets every asset that changed after the install.
				Dev.say("the app starts again with the changed assets.");
				if (start())
					send(since);
			}
		}
	}

	function arguments() {
		watch.arguments = Tool.arguments(watch.directory, watch.hxml, watch.built, false, triple);
		// `hxn.Bind.lib` selects each library's native file for the triple, as in `hxn build`.
		watch.arguments.haxe.push(["-D", 'hxn_triple=$triple']);
	}

	// Gives the app the files of `assets` that the warm compile wrote. The app gets them when it is connected.
	function send(assets:Array<String>) {
		var files = new Map<String, Bytes>();
		for (path in assets) {
			var file = Path.join([watch.built, "assets", path]);
			if (FileSystem.exists(file))
				files.set(path, File.getBytes(file));
		}
		if (!files.keys().hasNext())
			return;
		watch.updates.push(new Update(false, files));
		watch.exchange();
	}

	// Builds the app with `hxn build`, installs it, and starts it again.
	function deploy(why:Null<String>) {
		Dev.say(why == null ? 'building the app for $triple' : '$why, so the app builds, installs and starts again.');
		var code = File.getBytes(Path.join([watch.built, "main.hl"]));
		var from = Sys.time();
		var built = build();
		if (built == null) {
			Dev.say("the build failed, and the app stays as it is.");
			return;
		}
		Dev.say('built the app in ${Math.round((Sys.time() - from) * 10) / 10} s');
		var install = call(["install", "-r", built.apk]);
		if (install.status != 0) {
			Sys.print(install.output);
			Dev.say("the app does not install.");
			return;
		}
		activity = built.activity;
		installed = code;
		since.resize(0);
		start();
	}

	// Stops the app if it runs, and starts the installed app. Returns whether it started.
	function start():Bool {
		call(["shell", "am", "force-stop", activity.split("/")[0]]);
		if (watch.channel != null)
			watch.channel.close();
		watch.channel = null;
		watch.updates.resize(0);
		watch.asked = null;
		call(["logcat", "-c"]);
		if (log == null)
			follow();
		var start = call(["shell", "am", "start", "-n", activity]);
		running = start.status == 0;
		if (!running) {
			Sys.print(start.output);
			Dev.say("the app does not start.");
		}
		return running;
	}

	// Runs `hxn build` for the device, and returns the APK and the activity that it printed.
	function build():Null<{apk:String, activity:String}> {
		var process = new Process("hxn", [
			"build", "hl", Path.withoutDirectory(watch.hxml), "--target", triple, "--ash", watch.ash.join(" ")
		]);
		var errors = new Deque<String>();
		Thread.create(() -> errors.add(process.stderr.readAll().toString()));
		var output = process.stdout.readAll().toString();
		var status = process.exitCode();
		var error = errors.pop(true);
		process.close();
		var install = ~/adb install -r (\S+\.apk)/;
		var start = ~/adb shell am start(?: -W)? -n (\S+)/;
		if (status != 0 || !install.match(output) || !start.match(output)) {
			Sys.print(output + error);
			return null;
		}
		return {apk: install.matched(1), activity: start.matched(1)};
	}

	// Prints the app's output from the device log, where android-activity writes it.
	function follow() {
		var process = new Process(adb, ["logcat", "-v", "raw", "-s", "RustStdoutStderr:V"]);
		log = process;
		Thread.create(() -> {
			try
				while (true) {
					var line = process.stdout.readLine();
					if (StringTools.startsWith(line, "--------- beginning of"))
						continue;
					Sys.stdout().writeString(line + "\n");
					Sys.stdout().flush();
				}
			catch (_:Eof) {}
		});
	}

	function alive():Bool
		return StringTools.trim(call(["shell", "pidof", activity.split("/")[0]]).output) != "";

	// Runs adb with `args`, and returns its status and its output.
	function call(args:Array<String>):{status:Int, output:String} {
		var process = new Process(adb, args);
		var errors = new Deque<String>();
		Thread.create(() -> errors.add(process.stderr.readAll().toString()));
		var output = process.stdout.readAll().toString();
		var status = process.exitCode();
		output += errors.pop(true);
		process.close();
		return {status: status, output: output};
	}

	function stop() {
		if (log != null) {
			log.kill();
			log.close();
			log = null;
		}
		watch.compiler.close();
	}
}
