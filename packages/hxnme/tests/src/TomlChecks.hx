import hxn.me.project.Toml;

/** Checks the TOML reader against the project file's syntax and its errors. */
class TomlChecks {
	static function main() {
		var t:Dynamic = Toml.parse('# app\nplugins = [\n  "hxnme-physics", # physics\n  \'other\',\n]\nsize = 1_024\nscale = 1.5e2\non = true\n\n[app]\npreset = "game" # kind\nname = "Tab\\there"\n[window.main]\nsize = { w = 800, h = 600 }\n"quoted key".x = -3\n');
		check(t.plugins.length == 2 && t.plugins[0] == "hxnme-physics" && t.plugins[1] == "other", "arrays over lines, with comments and a trailing comma");
		check(t.size == 1024 && t.scale == 150 && t.on == true, "integers, floats and booleans");
		check(t.app.preset == "game" && t.app.name == "Tab\there", "tables and string escapes");
		check(t.window.main.size.w == 800 && t.window.main.size.h == 600, "dotted table headers and inline tables");
		check(Reflect.field(t.window.main, "quoted key").x == -3, "quoted and dotted keys");
		for (bad in [
			["a = 1\na = 2", "t.toml:2: `a` is set twice"],
			["[[x]]", "t.toml:1: arrays of tables are not supported"],
			["d = 2026-11-22", "t.toml:1: dates are not supported"],
			['a = "open', "t.toml:1: unterminated string"],
			["[t]\n[t.u]\nv = 1\n[t]\nw = 2", "t.toml:4: the table `t` is defined twice"],
			["a = 1 b", "t.toml:1: expected the end of the line"],
			["preset = game", "t.toml:1: `game` is not a value"],
		]) {
			var error = try {
				Toml.parse(bad[0], "t.toml");
				null;
			} catch (e:String) e;
			check(error == bad[1], 'refuses ${bad[0].split("\n").join("\\n")}: $error');
		}
		Sys.println("TOML checks passed");
	}

	static function check(ok:Bool, what:String) {
		if (!ok) {
			Sys.println('FAILED: $what');
			Sys.exit(1);
		}
		Sys.println(what);
	}
}
