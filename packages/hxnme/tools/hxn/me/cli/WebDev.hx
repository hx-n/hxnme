package hxn.me.cli;

import haxe.Json;
import haxe.io.Path;
import hxn.cli.Failure;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Deque;
import sys.thread.Thread;

/** Builds a web app with Ash, serves it locally, and reloads the page after a successful build. **/
class WebDev {
	final watch:Dev;
	final built:String;
	final served:String;
	final port:Int;
	var server:Null<Process>;
	var revision = 0;

	static function main() {
		var args = Sys.args();
		var dev = new WebDev(args[0], args[1], Std.parseInt(args[2]));
		try
			dev.run()
		catch (failure:haxe.Exception) {
			dev.stop();
			Sys.stderr().writeString(failure.message + "\n");
			Sys.exit(1);
		}
	}

	/** Runs the web development command on Ash, as the desktop development command does. **/
	public static function launch(file:String, ash:String, port:Int, cwd:String, root:String):Int {
		if (port < 1 || port > 65535)
			throw new Failure("The web server port must be between 1 and 65535.");
		var full = Path.normalize(Path.isAbsolute(file) ? file : Path.join([cwd, file]));
		if (!FileSystem.exists(full))
			throw new Failure('$full does not exist');
		var out = Path.join([Path.directory(full), "bin", Path.withoutExtension(Path.withoutDirectory(full)), "dev-web"]);
		FileSystem.createDirectory(out);
		var tool = Path.join([out, "dev.hl"]);
		var compile = Sys.command("haxe", [
			"-lib", "hxn", "-cp", Path.join([root, "tools"]), "-cp", Path.join([root, "src"]), "-main", "hxn.me.cli.WebDev", "-hl", tool
		]);
		var command = [for (word in ~/\s+/g.split(ash)) if (word != "") word];
		if (command.length == 0)
			throw new Failure("The Ash command is empty.");
		return compile != 0 ? compile : Sys.command(command[0], command.slice(1).concat([tool, full, ash, Std.string(port)]));
	}

	function new(file:String, ash:String, port:Int) {
		watch = new Dev(file, ash);
		this.port = port;
		var out = Path.join([watch.directory, "bin", Path.withoutExtension(Path.withoutDirectory(file))]);
		built = Path.join([out, "hl-wasm-threads"]);
		served = Path.join([out, "dev-web", "page"]);
	}

	function run():Void {
		Sys.setCwd(watch.directory);
		var probe = new Socket();
		try
			probe.bind(new Host("127.0.0.1"), port)
		catch (failure:haxe.Exception) {
			probe.close();
			throw new Failure('Cannot listen on 127.0.0.1:$port: ${failure.message}');
		}
		probe.close();
		watch.arguments = Tool.arguments(watch.directory, watch.hxml, built, true);
		var before = watch.snapshot();
		if (!compile()) {
			Dev.remove(served);
			FileSystem.createDirectory(served);
			File.saveContent(Path.join([served, "index.html"]), '<!doctype html><title>hxnme dev</title><p>Waiting for a successful build.</p>' + reload());
			File.saveContent(Path.join([served, "hxnme-dev.json"]), Json.stringify({revision: revision}));
		}
		server = new Process(watch.ash[0], ["serve", served, "--port", Std.string(port)]);
		var started = server;
		Thread.create(() -> {
			try Sys.stdout().writeString(started.stdout.readAll().toString()) catch (_:haxe.Exception) {}
		});
		Thread.create(() -> {
			try Sys.stderr().writeString(started.stderr.readAll().toString()) catch (_:haxe.Exception) {}
		});
		Dev.say('open http://127.0.0.1:$port/');
		while (true) {
			Sys.sleep(Dev.INTERVAL);
			var status = server.exitCode(false);
			if (status != null)
				throw new Failure('The web server exited with status $status.');
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
			before = now;
			try {
				watch.arguments = Tool.arguments(watch.directory, watch.hxml, built, true);
				compile();
			} catch (failure:haxe.Exception)
				Dev.say(failure.message);
		}
	}

	// hxn owns the wasm build, its target libraries and the page files of their hooks.
	function compile():Bool {
		var from = Sys.time();
		var process = new Process("hxn", ["build", "hl", Path.withoutDirectory(watch.hxml), "--wasm", "--threads", "--ash", watch.ash.join(" ")]);
		var errors = new Deque<String>();
		Thread.create(() -> errors.add(process.stderr.readAll().toString()));
		var output = process.stdout.readAll().toString();
		var status = process.exitCode();
		var error = errors.pop(true);
		process.close();
		if (status != 0) {
			Sys.print(output + error);
			Dev.say("the app does not compile, and the running page stays as it is.");
			return false;
		}
		var next = served + ".next";
		var previous = served + ".previous";
		Dev.remove(next);
		FileSystem.createDirectory(next);
		for (entry in FileSystem.readDirectory(built)) {
			var source = Path.join([built, entry]);
			if (FileSystem.isDirectory(source))
				Dev.copy(source, Path.join([next, entry]));
			else if (!["a", "hl", "o"].contains(Path.extension(entry)) && !StringTools.endsWith(entry, ".link.xml"))
				File.copy(source, Path.join([next, entry]));
		}
		revision++;
		var index = Path.join([next, "index.html"]);
		File.saveContent(index, File.getContent(index) + reload());
		File.saveContent(Path.join([next, "hxnme-dev.json"]), Json.stringify({revision: revision}));
		Dev.remove(previous);
		if (FileSystem.exists(served))
			FileSystem.rename(served, previous);
		FileSystem.rename(next, served);
		Dev.remove(previous);
		Dev.say('built the web app in ${Math.round((Sys.time() - from) * 10) / 10} s; the page reloads.');
		return true;
	}

	// Each page keeps its build's revision, so a new page never reloads itself in a loop.
	function reload():String
		return '<script type="module">\n'
			+ 'const revision = $revision;\n'
			+ 'async function poll() {\n'
			+ '  try {\n'
			+ '    const response = await fetch("hxnme-dev.json", {cache: "no-store"});\n'
			+ '    if (response.ok && (await response.json()).revision !== revision) { location.reload(); return; }\n'
			+ '  } catch {}\n'
			+ '  setTimeout(poll, 300);\n'
			+ '}\n'
			+ 'setTimeout(poll, 300);\n'
			+ '</script>\n';

	function stop():Void {
		if (server != null) {
			if (server.exitCode(false) == null)
				server.kill();
			server.exitCode();
			server.close();
			server = null;
		}
	}
}
