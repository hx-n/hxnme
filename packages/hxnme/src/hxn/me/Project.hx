package hxn.me;

import haxe.macro.Expr;

/**
	Values from the app's `hxnme.toml`, read at compile time. Each call
	becomes a constant. Each key is a dotted path, such as `"window.title"`. If
	the file or the key does not exist, the call becomes `fallback`. Values of another type are compile errors. The kernel and each plugin read their
	own tables this way.

	The hxnme hook of the hxn command gives the compiler the path of the
	file. If the compile does not run the hook, the compiler uses
	`hxnme.toml` in the working directory, if that file exists.
**/
class Project {
	/** The number at `key`, or `fallback`. **/
	public static macro function number(key:String, fallback:Float):ExprOf<Float>
		return hxn.me.macro.ProjectFile.value(key, fallback, "a number");

	/** The integer at `key`, or `fallback`. **/
	public static macro function integer(key:String, fallback:Int):ExprOf<Int>
		return hxn.me.macro.ProjectFile.value(key, fallback, "an integer");

	/** The string at `key`, or `fallback`. **/
	public static macro function text(key:String, fallback:String):ExprOf<String>
		return hxn.me.macro.ProjectFile.value(key, fallback, "a string");

	/** The boolean at `key`, or `fallback`. **/
	public static macro function flag(key:String, fallback:Bool):ExprOf<Bool>
		return hxn.me.macro.ProjectFile.value(key, fallback, "a boolean");
}
