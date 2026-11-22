package hxn.me;

import haxe.macro.Expr;

/** The entry point of an hxnme app. **/
class App {
	/**
		Generates the schedule of the app at compile time, and returns a new
		`hxn.me.Schedule`. The schedule contains the systems of the classes
		given here and the systems of the plugins:

		```haxe
		var schedule = hxn.me.App.schedule(Movement, Scoring);
		```

		A system is a static function with `@:system`. The schedule has one
		method for each phase. That method calls each system of the phase
		once, in the order that hxnme resolved at compile time. An app calls
		`schedule` one time only.
	**/
	public static macro function schedule(classes:Array<Expr>):Expr
		return hxn.me.macro.Scheduler.schedule(classes);
}
