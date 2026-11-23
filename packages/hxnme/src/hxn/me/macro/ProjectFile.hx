package hxn.me.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import hxn.me.project.Toml;
import sys.FileSystem;
import sys.io.File;

/**
	Reads the app's `hxnme.toml` once for each compile, for `hxn.me.Project`.
	`-D hxnme_project` gives its path. The file is a dependency of the module
	that reads it, so the compilation server compiles that module again when
	the file changes.
**/
class ProjectFile {
	static var parsed:Null<Dynamic>;
	static var path:Null<String>;

	/** The constant at `key`, or `fallback`. `kind` describes the expected type in the error. **/
	public static function value(key:String, fallback:Dynamic, kind:String):Expr {
		var table = load();
		var found:Dynamic = table;
		for (part in key.split(".")) {
			if (found == null || !Reflect.isObject(found) || Std.isOfType(found, String) || Std.isOfType(found, Array)) {
				found = null;
				break;
			}
			found = Reflect.field(found, part);
		}
		if (found == null)
			return macro $v{fallback};
		var matches = switch kind {
			case "a number": Std.isOfType(found, Float);
			case "an integer": Std.isOfType(found, Int);
			case "a string": Std.isOfType(found, String);
			case _: Std.isOfType(found, Bool);
		}
		if (!matches)
			Context.error('$path: `$key` must be $kind', Context.currentPos());
		return macro $v{found};
	}

	static function load():Dynamic {
		if (path == null) {
			path = Context.definedValue("hxnme_project");
			if (path == null || path == "")
				path = "hxnme.toml";
			parsed = FileSystem.exists(path) ? try Toml.parse(File.getContent(path), path) catch (error:String) Context.error(error, Context.currentPos()) : {};
		}
		if (FileSystem.exists(path))
			Context.registerModuleDependency(Context.getLocalModule(), path);
		return parsed;
	}
}
#end
