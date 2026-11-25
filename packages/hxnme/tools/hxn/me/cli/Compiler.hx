package hxn.me.cli;

import haxe.Json;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;
import hxn.me.cli.Tool.Failure;
import sys.io.Process;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Thread;

/**
	`Compiler` compiles with one Haxe compiler that stays in memory. The first compile
	types every module. The next ones type only the modules that changed, and those that
	depend on them.

	The Haxe compiler connects to a socket of this process, and ends when that connection
	closes.
**/
class Compiler {
	// The number of seconds that the Haxe compiler has to connect.
	static inline final LIMIT = 30;

	var process:Null<Process>;
	var socket:Null<Socket>;

	public function new() {}

	/**
		Compiles with the arguments of `haxe`, in `directory`. `changed` lists the files that
		changed after the last compile. Returns whether it succeeded, and what the compiler
		printed.
	**/
	public function compile(directory:String, arguments:Array<String>, changed:Array<String>):{success:Bool, output:String} {
		var connected = socket != null;
		try {
			// The compiler compares file times in whole seconds, so it cannot see each change.
			if (connected)
				for (file in changed)
					answer(["--display", Json.stringify({jsonrpc: "2.0", id: 1, method: "server/invalidate", params: {file: file}})]);
			return answer(["--cwd", directory].concat(arguments));
		} catch (failure:haxe.Exception) {
			close();
			// The compiler can end between two compiles, and a new one then takes its place.
			return connected ? compile(directory, arguments, []) : {success: false, output: 'The Haxe compiler gave no answer: ${failure.message}\n'};
		}
	}

	/** Ends the Haxe compiler. **/
	public function close() {
		if (socket != null)
			socket.close();
		socket = null;
		if (process != null) {
			process.kill();
			process.exitCode();
			process.close();
		}
		process = null;
	}

	// Each message starts with its length. In an answer, the byte 1 starts a line that the
	// compiler printed to its standard output and stands for the line breaks in it, and the
	// byte 2 starts a line that marks an error.
	function answer(arguments:Array<String>):{success:Bool, output:String} {
		if (socket == null)
			connect();
		var request = Bytes.ofString(arguments.join("\n") + "\n");
		socket.output.writeInt32(request.length);
		socket.output.write(request);
		socket.output.flush();
		var text = socket.input.read(socket.input.readInt32()).toString();
		var success = true;
		var output = new StringBuf();
		for (line in text.split("\n"))
			switch StringTools.fastCodeAt(line, 0) {
				case 1:
					output.add(StringTools.replace(line.substr(1), "\x01", "\n"));
				case 2:
					success = false;
				case _ if (line != ""):
					output.add(line + "\n");
				case _:
			}
		return {success: success, output: output.toString()};
	}

	function connect() {
		var listener = new Socket();
		listener.bind(new Host("127.0.0.1"), 0);
		listener.listen(1);
		var started = new Process("haxe", ["--server-connect", "127.0.0.1:" + listener.host().port]);
		process = started;
		// Programs that macros run can print to the pipes, and stop when one is full.
		drain(started.stdout);
		drain(started.stderr);
		var end = Sys.time() + LIMIT;
		while (Socket.select([listener], [], [], 0.1).read.length == 0)
			if (started.exitCode(false) != null || Sys.time() > end) {
				listener.close();
				throw new Failure("the Haxe compiler did not start");
			}
		socket = listener.accept();
		listener.close();
	}

	static function drain(input:Input)
		Thread.create(() -> {
			var buffer = Bytes.alloc(4096);
			try
				while (true) {
					var read = input.readBytes(buffer, 0, buffer.length);
					Sys.stdout().writeBytes(buffer, 0, read);
					Sys.stdout().flush();
				}
			catch (_:Eof) {}
		});
}
