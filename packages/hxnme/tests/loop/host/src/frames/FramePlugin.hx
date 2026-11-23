package frames;

import hxn.me.AppLoop;

/**
	This host runs three frames of a thirtieth of a second, and suspends the
	app for the third, as a platform does. Then it runs frames of a sixtieth
	of a second, each a few percent long or short, as vsync timing is. Its
	metadata declares it, without `implements`.
**/
@:plugin("check-host", description = "Runs frames of exactly one thirtieth of a second")
@:provides(hxn.me.Host)
class FramePlugin {
	public function new() {}

	public function start():Void {}

	public function run(loop:AppLoop):Void {
		loop.display.set(640, 480, 2);
		var seconds = [1 / 30, 1 / 30, 1 / 30, 0.97 / 60, 1.03 / 60, 0.96 / 60, 1.04 / 60];
		var frame = 0;
		while (frame < seconds.length) {
			loop.lifecycle.set(frame == 2, true, true);
			frame++;
			if (!loop.frame(seconds[frame - 1]))
				break;
		}
		Sys.println('host: the loop stopped after $frame frames');
	}
}
