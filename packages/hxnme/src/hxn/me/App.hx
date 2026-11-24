package hxn.me;

import haxe.macro.Expr;

/**
	`App` starts an hxnme app. It generates the schedule of the app at
	compile time, and runs its frames on the host.
**/
class App {
	/** Checks the plugin classes of the app. The generated `Plugins.start` calls it. **/
	@:noCompletion public static macro function checkPlugins():Expr
		return hxn.me.macro.Registry.contracts();

	/**
		Starts the plugins, generates the schedule of the app at compile time,
		and runs it on the host until a system calls `Lifecycle.quit` or the
		platform closes the app:

		```haxe
		static function main()
			hxn.me.App.run(Movement, Scoring);
		```

		The host is the plugin that provides `hxn.me.Host`, such as the window
		plugin, or `HeadlessHost` if no plugin provides it. The schedule
		contains the systems of the classes given here and the systems of the
		plugins. Each app calls `run` or `schedule` one time only.

		Make `run` the last statement of `main`. Under Emscripten, a host can
		return from `run` before the frames run, and then run them from
		browser callbacks. Code after `run` then runs before the frames.
	**/
	public static macro function run(classes:Array<Expr>):Expr
		return hxn.me.macro.Scheduler.run(classes);

	/**
		Generates the schedule of the app at compile time, and returns a new
		`hxn.me.Schedule`. The schedule contains the systems of the classes
		given here and the systems of the plugins:

		```haxe
		var schedule = hxn.me.App.schedule(Movement, Scoring);
		```

		Systems are static functions with `@:system`. The schedule has one
		method for each phase. That method calls each system of the phase
		once, in the order that hxnme resolved at compile time. Use it to run
		the phases from a loop of your own. Each app calls `run` or `schedule`
		one time only.
	**/
	public static macro function schedule(classes:Array<Expr>):Expr
		return hxn.me.macro.Scheduler.schedule(classes);
}
