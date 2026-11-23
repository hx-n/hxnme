package hxn.me;

/**
	Paces the frames of the app. The host waits for each frame, reads the
	platform's events, sets `Lifecycle` and `Display`, and calls
	`loop.frame`. Plugins provide it with `@:provides(hxn.me.Host)` on the
	plugin class, which has the method `run`, with or without
	`implements hxn.me.Host`. If no plugin provides it, the app runs on
	`HeadlessHost`.
**/
@:service
interface Host {
	/**
		Runs the frames of `loop` until `loop.frame` returns false. On the web,
		it can return before then and run the frames from browser callbacks.
	**/
	function run(loop:AppLoop):Void;
}
