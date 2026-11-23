import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	Compiles action sets that are wrong, and makes sure that each compile
	fails with the error that describes the problem. Run it in `tests` with
	`haxe action-errors.hxml`. It needs hxn and hxn-window in haxelib.
**/
class ActionErrors {
	static final out = "bin/action-errors";

	static function main() {
		expect("a key does not exist", "@:actions enum abstract Action(Int) {\n\t@:keys(Spacebar) var Jump;\n}",
			"`Spacebar` is not a key of hxn.window.KeyCode");
		expect("a mouse button does not exist", "@:actions enum abstract Action(Int) {\n\t@:mouse(Wheel) var Fire;\n}",
			"`Wheel` is not a mouse button: use Left, Right, Middle, Back, Forward");
		expect("a key axis has one key", "@:actions enum abstract Action(Int) {\n\t@:keyAxis(KeyA) var MoveX;\n}",
			"@:keyAxis takes two keys: the key for -1, then the key for 1");
		expect("a shortcut has one key", "@:actions enum abstract Action(Int) {\n\t@:shortcut(KeyS) var Save;\n}",
			"@:shortcut takes two or more keys, held together, such as @:shortcut(Control, KeyS)");
		expect("a shortcut key does not exist", "@:actions enum abstract Action(Int) {\n\t@:shortcut(Control, Spacebar) var Save;\n}",
			"`Spacebar` is not a key of hxn.window.KeyCode, or Control, Shift, Alt or Super");
		expect("the set has no @:actions", "enum abstract Action(Int) {\n\t@:keys(Space) var Jump;\n}",
			"`Action` is not an action set: mark an enum abstract over Int with @:actions");
		expect("the actions have a gap", "@:actions enum abstract Action(Int) {\n\tvar Jump = 0;\n\tvar Fire = 2;\n}",
			"Action.Fire is 2: an action set numbers its actions from 0 without gaps");
		Sys.println("Action error checks passed");
	}

	// Writes `actions` and a program that creates its input, compiles it for
	// HashLink without output, and makes sure that the compile fails with `error`.
	static function expect(what:String, actions:String, error:String) {
		var dir = Path.join([out, StringTools.replace(what, " ", "-")]);
		FileSystem.createDirectory(dir);
		File.saveContent(Path.join([dir, "Action.hx"]), actions + "\n");
		File.saveContent(Path.join([dir, "Main.hx"]),
			"class Main {\n\tstatic function main() {\n\t\tvar input = (hxn.me.input.Input.create() : hxn.me.input.Input<Action>);\n\t}\n}\n");
		var args = [
			"-cp", classPath("hxn-window"), "-cp", classPath("hxn"), "-cp", "../../hxnme/src", "-cp", "../src", "-cp", dir, "-main", "Main", "--no-output",
			"-hl", Path.join([dir, "main.hl"])
		];
		var process = new Process("haxe", args);
		var printed = process.stderr.readAll().toString() + process.stdout.readAll().toString();
		var code = process.exitCode();
		process.close();
		if (code == 0 || printed.indexOf(error) < 0) {
			Sys.println('FAILED: $what: expected the compile to fail with "$error", and it printed:\n$printed');
			Sys.exit(1);
		}
		Sys.println('$what: $error');
	}

	// The class path of the haxelib `name`. The check compiles without output,
	// so it needs the classes only, and not the haxelib's macros.
	static function classPath(name:String):String {
		var process = new Process("haxelib", ["libpath", name]);
		var root = StringTools.trim(process.stdout.readAll().toString());
		process.close();
		var info:Dynamic = haxe.Json.parse(File.getContent(Path.join([root, "haxelib.json"])));
		if (info.classPath != null)
			return Path.join([root, info.classPath]);
		// hxn libraries keep their classes in `binding`, which `hxn.Bind.lib` adds.
		return FileSystem.exists(Path.join([root, "binding"])) ? Path.join([root, "binding"]) : root;
	}
}
