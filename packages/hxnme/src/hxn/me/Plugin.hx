package hxn.me;

/**
	`Plugin` declares the methods of an hxnme plugin class. The class has
	`@:plugin("<haxelib name>")`, and the `hxnme` section of the haxelib's
	`haxelib.json` specifies it:

	```json
	"hxnme": {"plugin": "my.pkg.MyPlugin", "requires": ["hxnme-physics"]}
	```

	The haxelib's `extraParams.hxml` registers it with
	`--macro hxn.me.macro.Registry.add("<haxelib name>")`. The kernel
	generates `hxn.me.Plugins` at compile time. It creates each plugin of the
	app and starts it, after the plugins it requires.

	The class does not have to implement this interface. The kernel checks
	that it has these methods with these types, and calls the class directly.
	Classes that implement the interface get the same checks.
**/
@:autoBuild(hxn.me.macro.Registry.check())
interface Plugin {
	/** `Plugins.start` calls it once when the app starts. **/
	function start():Void;
}
