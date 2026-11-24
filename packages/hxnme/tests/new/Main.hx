import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Creates a game from hxnme's template with the tool's `new` command, into
	`bin/new`, and checks the files it wrote and the name it filled in.
**/
class Main {
	static var failed = 0;

	static function main() {
		var out = Path.join([here(), "bin", "new"]);
		remove(out);
		FileSystem.createDirectory(out);
		@:privateAccess hxn.me.cli.Tool.create("my-game", out, Path.join([here(), "..", ".."]));
		var game = Path.join([out, "my-game"]);
		for (file in [".gitignore", "hxnme.toml", "app.hxml", "Main.hx", "Game.hx", "GameAssets.hx", "Action.hx", "assets/sheet.png", "assets/sheet.json",
			"assets/font.ttf", "licenses/NotoSans-OFL.txt"])
			expect('$file is there', FileSystem.exists(Path.join([game, file])));
		var toml = File.getContent(Path.join([game, "hxnme.toml"]));
		expect("the app id is the name", toml.indexOf('id = "my-game"') >= 0);
		expect("the window title is the name in words", toml.indexOf('title = "My Game"') >= 0);
		expect("no placeholder is left", toml.indexOf("{{") < 0);
		if (failed > 0) {
			Sys.println('$failed checks failed');
			Sys.exit(1);
		}
		Sys.println("New project checks passed");
	}

	static function expect(name:String, ok:Bool) {
		if (!ok)
			failed++;
		Sys.println('$name: ${ok ? "yes" : "no"}');
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

	// The directory of this check, fixed at compile time so that every runtime writes to the same place.
	static macro function here():haxe.macro.Expr
		return macro $v{sys.FileSystem.absolutePath(".")};
}
