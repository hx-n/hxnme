package hxn.me.cli;

import haxe.Json;
import sys.io.File;

/**
	The hxn CLI hook of hxnme. Before a build, it reads the app's metadata from
	the defines of its program file and returns the Ash options they select:
	`-D hxnme_preset=game` gives Ash `--preset game`.
**/
class Tool {
	static function main() {
		var request:Dynamic = Json.parse(Sys.stdin().readAll().toString());
		if (request.kind != "hook") {
			Sys.stderr().writeString("hxn me has no commands. hxnme reads its app metadata from the program file's defines, such as -D hxnme_preset=game.\n");
			Sys.exit(2);
		}
		var reply:Dynamic = {version: 1};
		var context:Dynamic = request.context;
		var hxml:Null<String> = context.project.hxml;
		var target:Dynamic = context.target;
		if (request.phase == "before-build" && hxml != null && target != null && target.runtime == "hl") {
			var preset = define(File.getContent(hxml), "hxnme_preset");
			if (preset != null)
				reply.ash_args = [["--preset", preset]];
		}
		Sys.println(Json.stringify(reply));
	}

	// The value of `-D name=value` or `--define name=value` in the text of an
	// .hxml file, or null when the file does not define `name` with a value.
	static function define(text:String, name:String):Null<String> {
		var found = null;
		for (line in text.split("\n")) {
			var words = [for (word in ~/\s+/g.split(StringTools.trim(line))) if (word != "") word];
			if (words.length == 0 || StringTools.startsWith(words[0], "#"))
				continue;
			var i = 0;
			while (i < words.length - 1) {
				if ((words[i] == "-D" || words[i] == "--define") && StringTools.startsWith(words[i + 1], '$name='))
					found = words[i + 1].substr(name.length + 1);
				i++;
			}
		}
		return found;
	}
}
