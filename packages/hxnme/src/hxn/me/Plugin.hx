package hxn.me;

/**
	An hxnme plugin. The class carries `@:plugin("<haxelib name>")`, and the
	`hxnme` section of the haxelib's `haxelib.json` names it:

	```json
	"hxnme": {"plugin": "my.pkg.MyPlugin", "requires": ["hxnme-physics"]}
	```

	The haxelib's `extraParams.hxml` registers it with
	`--macro hxn.me.macro.Registry.add("<haxelib name>")`. `hxn.me.Plugins`,
	generated at compile time, creates each plugin of the app and starts it,
	after the plugins it requires.
**/
@:autoBuild(hxn.me.macro.Registry.check())
interface Plugin {
	/** Called once when the app starts. **/
	function start():Void;
}
