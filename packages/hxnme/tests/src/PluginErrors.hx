import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

private typedef Fixture = {
	var name:String;
	var manifest:String;
	var source:String;
}

/**
	Compiles apps whose plugins are wrong, and checks that each compile fails
	with the error that names the problem. Run it in `tests` with
	`haxe plugin-errors.hxml`.
**/
class PluginErrors {
	static final out = "bin/plugin-errors";

	static function main() {
		expect("a required plugin is missing", [plugin("needs", '"requires": ["check-absent"]')],
			"`check-needs` requires the plugin `check-absent`");
		expect("plugins require each other", [
			plugin("first", '"requires": ["check-second"]'),
			plugin("second", '"requires": ["check-first"]')
		], "the plugins require each other in a cycle: check-first -> check-second -> check-first");
		expect("the target is not supported", [plugin("native", '"platforms": ["cpp"]')], "`check-native` supports cpp, and this build is hl for desktop");
		expect("the class has no @:plugin", [
			{
				name: "bare",
				manifest: '"plugin": "bare.BarePlugin"',
				source: "package bare;\nclass BarePlugin implements hxn.me.Plugin {\n\tpublic function new() {}\n\tpublic function start() {}\n}\n"
			}
		], 'bare.BarePlugin implements hxn.me.Plugin: mark it with @:plugin("<haxelib name>")');
		expect("@:plugin names another haxelib", [
			{
				name: "renamed",
				manifest: '"plugin": "renamed.RenamedPlugin"',
				source: '@:plugin("check-other") class RenamedPlugin implements hxn.me.Plugin {\n\tpublic function new() {}\n\tpublic function start() {}\n}\n'
			}
		], "the app does not list the plugin `check-other`");
		expect("the manifest names a class that is not a plugin", [
			{
				name: "moved",
				manifest: '"plugin": "moved.Elsewhere"',
				source: "class Elsewhere {\n\tpublic function new() {}\n}\n"
			}
		], "moved.Elsewhere should be hxn.me.Plugin");
		expect("the haxelib has no hxnme section", [{name: "plain", manifest: null, source: "package plain;\nclass Plain {}\n"}],
			"has no `hxnme.plugin` naming the plugin class of `check-plain`");
		Sys.println("Plugin error checks passed");
	}

	static function plugin(name:String, extra:String):Fixture {
		var type = name.charAt(0).toUpperCase() + name.substr(1) + "Plugin";
		return {
			name: name,
			manifest: '"plugin": "$name.$type", $extra',
			source: '@:plugin("check-$name") class $type implements hxn.me.Plugin {\n\tpublic function new() {}\n\tpublic function start() {}\n}\n'
		};
	}

	// Writes the app and its plugins, compiles it for HashLink, and checks the
	// compile fails with `error` in its output.
	static function expect(what:String, fixtures:Array<Fixture>, error:String) {
		var dir = Path.join([out, StringTools.replace(what, " ", "-")]);
		var args = ["-cp", "../src", "--macro", "hxn.me.macro.Registry.install()"];
		for (fixture in fixtures) {
			var root = Path.join([dir, fixture.name]);
			var file = fixture.source.split("class ")[1].split(" ")[0];
			FileSystem.createDirectory(Path.join([root, "src", fixture.name]));
			var source = fixture.source.indexOf("package ") == 0 ? fixture.source : 'package ${fixture.name};\n\n' + fixture.source;
			File.saveContent(Path.join([root, "src", fixture.name, '$file.hx']), source);
			var section = fixture.manifest == null ? "" : ', "hxnme": {${fixture.manifest}}';
			File.saveContent(Path.join([root, "haxelib.json"]), '{"name": "check-${fixture.name}", "version": "0.0.1", "classPath": "src"$section}\n');
			args = args.concat(["-cp", Path.join([root, "src"]), "--macro", 'hxn.me.macro.Registry.add("check-${fixture.name}")']);
		}
		File.saveContent(Path.join([dir, "Main.hx"]), "class Main {\n\tstatic function main() hxn.me.Plugins.start();\n}\n");
		args = args.concat(["-cp", dir, "-main", "Main", "-hl", Path.join([dir, "main.hl"])]);
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
