import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	Compiles apps whose systems are wrong, and makes sure that each compile
	fails with the error that names the problem. Run it in `tests` with
	`haxe system-errors.hxml`.
**/
class SystemErrors {
	static final out = "bin/system-errors";
	static final once = "hxn.me.App.schedule(Systems);";

	static function main() {
		expect("systems are ordered in a cycle", systems("
			@:system(Update, after = b) static function a() {}
			@:system(Update, after = a) static function b() {}
		"), once, "the Update systems are ordered in a cycle, each running before the next: Systems.a -> Systems.b -> Systems.a");
		expect("a parameter is not a resource", systems("
			@:system(Update) static function a(count:Int) {}
		"), once, "Systems.a takes `count:Int`: a system takes Res<T> or ResMut<T>");
		expect("a constraint names nothing", systems("
			@:system(Update, after = missing) static function a() {}
		"), once, "Systems.a names `missing`, which is no system of the app and no class of its systems");
		expect("a constraint names another phase", systems("
			@:system(Update, after = b) static function a() {}
			@:system(Render) static function b() {}
		"), once, "Systems.a runs in Update, and `b` names Systems.b, which runs in Render");
		expect("the phase does not exist", systems("
			@:system(Draw) static function a() {}
		"), once, "`Draw` is not a phase: use Start, Fixed, Update or Render");
		expect("the system is not static", systems("
			@:system(Update) function a() {}
		"), once, "Systems.a is not static: a system is a static function");
		expect("the system returns a value", systems("
			@:system(Update) static function a():Int return 1;
		"), once, "Systems.a returns a value: a system returns Void");
		expect("a resource is taken twice", systems("
			@:system(Update) static function a(x:hxn.me.Res<Counter>, y:hxn.me.ResMut<Counter>) {}
		", ["Counter" => "class Counter {\n\tpublic function new() {}\n}\n"]), once, "Systems.a takes Counter twice");
		expect("a resource has no constructor", systems("
			@:system(Update) static function a(shape:hxn.me.Res<Shape>) {}
		", ["Shape" => "interface Shape {}\n"]), once,
			"`Shape` cannot be a resource: a resource is a class whose constructor takes no arguments");
		expect("a constraint names two classes", systems("
			@:system(Update, after = Moves) static function a() {}
		", [
			"one/Moves" => "package one;\n\nclass Moves {\n\t@:system(Update) static function step() {}\n}\n",
			"two/Moves" => "package two;\n\nclass Moves {\n\t@:system(Update) static function step() {}\n}\n"
		]), "hxn.me.App.schedule(Systems, one.Moves, two.Moves);",
			"Systems.a names `Moves`, which could be one.Moves or two.Moves: write the full path");
		expect("a description is not a string", systems("
			@:system(Update, description = 42) static function a() {}
		"), once, "`description` takes a string");
		expect("the app names a value", systems(""), "hxn.me.App.schedule(42);", "hxn.me.App.schedule takes the classes that hold the app's systems");
		expect("the app makes two schedules", systems(""), once + " " + once, "the app calls hxn.me.App.schedule once");
		Sys.println("System error checks passed");
	}

	// The source files of an app: `Systems` with the fields `body`, and `extra`.
	static function systems(body:String, ?extra:Map<String, String>):Map<String, String> {
		var files = ["Systems" => 'class Systems {\n$body\n}\n'];
		if (extra != null)
			for (name => source in extra)
				files.set(name, source);
		return files;
	}

	// Writes the app, compiles it for HashLink, and makes sure that the compile
	// fails with `error` in its output. `run` is the body of `main`.
	static function expect(what:String, files:Map<String, String>, run:String, error:String) {
		var dir = Path.join([out, StringTools.replace(what, " ", "-")]);
		for (name => source in files) {
			var file = Path.join([dir, '$name.hx']);
			FileSystem.createDirectory(Path.directory(file));
			File.saveContent(file, source);
		}
		File.saveContent(Path.join([dir, "Main.hx"]), 'class Main {\n\tstatic function main() {\n\t\t$run\n\t}\n}\n');
		var args = [
			"-cp", "../src", "--macro", "hxn.me.macro.Registry.install()", "-cp", dir, "-main", "Main", "-hl", Path.join([dir, "main.hl"])
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
}
