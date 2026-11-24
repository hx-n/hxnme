import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	Compiles atlas declarations that are wrong, and makes sure that each
	compile fails with the error that describes the problem. Run it in
	`tests` with `haxe asset-errors.hxml`. It needs hxnme, its window
	and GPU plugins, and their libraries in haxelib.
**/
class AssetErrors {
	static final out = "bin/asset-errors";

	static function main() {
		expect("a region name is misspelled", '{"image": "sheet.png", "regions": {"hero": {"x": 0, "y": 0, "width": 8, "height": 8}}}',
			"function show(a:hxn.me.Asset<ArtSheetAtlas>) return a.value.heor;", "ArtSheetAtlas has no field heor");
		expect("two region names become one property",
			'{"image": "sheet.png", "regions": {"a-b": {"x": 0, "y": 0, "width": 8, "height": 8}, "a_b": {"x": 9, "y": 0, "width": 8, "height": 8}}}',
			"function show(a:hxn.me.Asset<ArtSheetAtlas>) return a.value;", "the regions a-b and a_b of");
		Sys.println("Asset error checks passed");
	}

	// Writes an atlas file, a class that declares it and a program with `use`, compiles them for
	// HashLink without output, and makes sure that the compile fails with `error`.
	static function expect(what:String, atlas:String, use:String, error:String) {
		var dir = FileSystem.absolutePath(Path.join([out, StringTools.replace(what, " ", "-")]));
		FileSystem.createDirectory(Path.join([dir, "assets"]));
		File.saveContent(Path.join([dir, "assets", "sheet.json"]), atlas);
		File.saveContent(Path.join([dir, "Art.hx"]),
			"@:build(hxn.me.Assets.build())\nclass Art {\n\t@:asset(\"sheet.json\") public static var Sheet:hxn.me.AssetRef<hxn.me.render2d.Atlas>;\n}\n");
		File.saveContent(Path.join([dir, "Main.hx"]), 'class Main {\n\tstatic function main() {\n\t\tshow(null);\n\t\tArt.Sheet;\n\t}\n\n\tstatic $use\n}\n');
		var args = [];
		for (name in ["hxn", "hxn-assets", "hxn-file", "format", "hxn-text", "hxn-gpu", "hxnsl", "hxnme", "hxnme-window", "hxnme-gpu"])
			for (path in classPaths(name)) {
				args.push("-cp");
				args.push(path);
			}
		args.push("-cp");
		args.push("../src");
		args = args.concat([
			"--macro", "hxn.me.macro.AssetFields.install()", "--macro", "hxn.me.render2d.macro.AtlasNames.register()", "-cp", dir, "-D", 'hxn_assets_dir=${Path.join([dir, "assets"])}', "-main", "Main",
			"--no-output", "-hl", Path.join([dir, "main.hl"])
		]);
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

	// The class paths of the haxelib `name`. The check compiles without output,
	// so it needs the classes only, and not the haxelib's macros.
	static function classPaths(name:String):Array<String> {
		var process = new Process("haxelib", ["libpath", name]);
		var root = StringTools.trim(process.stdout.readAll().toString());
		process.close();
		var info:Dynamic = haxe.Json.parse(File.getContent(Path.join([root, "haxelib.json"])));
		if (info.classPath != null)
			return [Path.join([root, info.classPath])];
		// hxn libraries keep their bindings in `binding`, which `hxn.Bind.lib` adds, and their own classes in `sources`.
		var paths = [for (dir in ["binding", "sources"]) if (FileSystem.exists(Path.join([root, dir]))) Path.join([root, dir])];
		return paths.length > 0 ? paths : [root];
	}
}
