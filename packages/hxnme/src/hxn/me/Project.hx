package hxn.me;

import haxe.macro.Expr;

/**
	`Project` reads values from the app's `hxnme.toml` at compile time. Each
	call becomes a constant. Each key is a dotted path, such as
	`"window.title"`. If the file or the key does not exist, the call becomes
	`fallback`. Values of another type are compile errors. The kernel and
	each plugin read their own tables this way.

	The hxnme hook of the hxn command gives the compiler the path of the
	file. If the compiler runs without the hook, it uses `hxnme.toml` in the
	working directory, if that file exists.
**/
class Project {
	/** Returns the number at `key`, or `fallback`. **/
	public static macro function number(key:String, fallback:Float):ExprOf<Float>
		return hxn.me.macro.ProjectFile.value(key, fallback, "a number");

	/** Returns the integer at `key`, or `fallback`. **/
	public static macro function integer(key:String, fallback:Int):ExprOf<Int>
		return hxn.me.macro.ProjectFile.value(key, fallback, "an integer");

	/** Returns the string at `key`, or `fallback`. **/
	public static macro function text(key:String, fallback:String):ExprOf<String>
		return hxn.me.macro.ProjectFile.value(key, fallback, "a string");

	/** Returns the boolean at `key`, or `fallback`. **/
	public static macro function flag(key:String, fallback:Bool):ExprOf<Bool>
		return hxn.me.macro.ProjectFile.value(key, fallback, "a boolean");
}
