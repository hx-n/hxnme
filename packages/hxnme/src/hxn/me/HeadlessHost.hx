package hxn.me;

import haxe.Timer;

/**
	`HeadlessHost` runs the frames of an app that has no window. `app.rate` in
	`hxnme.toml` sets the number of frames in a second. The default is 60.
	Servers, tools and checks run on it. Under Emscripten, it returns to the
	browser between frames.
**/
class HeadlessHost implements Host {
	/** The number of frames in a second. **/
	public static final RATE:Float = Project.number("app.rate", 60);

	public function new() {}

	public function run(loop:AppLoop):Void {
		var period = 1 / RATE;
		var last = Timer.stamp();
		#if (cpp && emscripten)
		var next = last;
		function turn() {
			var now = Timer.stamp();
			if (now >= next) {
				if (!loop.frame(now - last))
					return;
				last = now;
				next += period;
				if (next < now)
					next = now;
			}
			hxn.native.Emscripten.later(turn);
		}
		turn();
		#else
		var next = last;
		while (true) {
			var now = Timer.stamp();
			if (!loop.frame(now - last))
				break;
			last = now;
			next += period;
			var wait = next - Timer.stamp();
			if (wait > 0)
				Sys.sleep(wait);
			else
				next = Timer.stamp();
		}
		#end
	}
}
