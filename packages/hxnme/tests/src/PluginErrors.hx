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
	with the error that describes the problem. Run it in `tests` with
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
		], 'specifies bare.BarePlugin as the plugin class of `check-bare`: mark the class with @:plugin("check-bare")');
		expect("@:plugin refers to another haxelib", [
			{
				name: "renamed",
				manifest: '"plugin": "renamed.RenamedPlugin"',
				source: '@:plugin("check-other") class RenamedPlugin implements hxn.me.Plugin {\n\tpublic function new() {}\n\tpublic function start() {}\n}\n'
			}
		], "the app does not list the plugin `check-other`");
		expect("a class implements Plugin without @:plugin", [
			{
				name: "stray",
				manifest: '"plugin": "stray.StrayPlugin"',
				source: '@:plugin("check-stray") class StrayPlugin {\n\tpublic function new() {}\n\tpublic function start() {}\n}\n\nclass Extra implements hxn.me.Plugin {\n\tpublic function new() {}\n\tpublic function start() {}\n}\n'
			}
		], 'stray.Extra implements hxn.me.Plugin: mark it with @:plugin("<haxelib name>")');
		expect("the haxelib has no hxnme section", [{name: "plain", manifest: null, source: "package plain;\nclass Plain {}\n"}],
			"has no `hxnme.plugin` that specifies the plugin class of `check-plain`");
		expect("two plugins provide the host", [host("one", "run(loop:hxn.me.AppLoop)"), host("two", "run(loop:hxn.me.AppLoop)")],
			"both provide `hxn.me.Host`: an app has one provider for each service");
		expect("the plugin provides an interface that is not a service", [
			{
				name: "plain",
				manifest: '"plugin": "plain.PlainPlugin"',
				source: '@:plugin("check-plain") @:provides(hxn.me.Plugin) class PlainPlugin implements hxn.me.Plugin {\n\tpublic function new() {}\n\tpublic function start() {}\n}\n'
			}
		], "`hxn.me.Plugin` is not a service: mark the interface with @:service");
		expect("the plugin class lacks a method of the service", [host("partial", null)],
			"partial.PartialPlugin is the plugin class of `check-partial`, and hxn.me.Host needs the public method `run`, of type (loop : hxn.me.AppLoop) -> Void");
		expect("a method of the plugin class has the wrong type", [host("wrong", "run(steps:Int)")],
			"wrong.WrongPlugin.run has the type (steps : Int) -> Void, and hxn.me.Host needs (loop : hxn.me.AppLoop) -> Void");
		expect("the plugin class lacks start", [
			{
				name: "idle",
				manifest: '"plugin": "idle.IdlePlugin"',
				source: '@:plugin("check-idle") class IdlePlugin {\n\tpublic function new() {}\n}\n'
			}
		], "idle.IdlePlugin is the plugin class of `check-idle`, and hxn.me.Plugin needs the public method `start`, of type () -> Void");
		Sys.println("Plugin error checks passed");
	}

	// Returns a plugin that provides `hxn.me.Host` without `implements`. `run` is the
	// signature of its run method, or null for none.
	static function host(name:String, run:Null<String>):Fixture {
		var type = name.charAt(0).toUpperCase() + name.substr(1) + "Plugin";
		var method = run == null ? "" : '\tpublic function $run {}\n';
		return {
			name: name,
			manifest: '"plugin": "$name.$type"',
			source: '@:plugin("check-$name") @:provides(hxn.me.Host) class $type {\n\tpublic function new() {}\n\tpublic function start() {}\n$method}\n'
		};
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
		var dir = Path.join([out, directoryName(what)]);
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

	// Keeps letters and digits, so that the name is a valid directory on every system.
	static function directoryName(what:String):String
		return ~/[^A-Za-z0-9]+/g.replace(what, "-");
}
