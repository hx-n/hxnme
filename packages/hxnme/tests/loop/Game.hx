import hxn.me.Display;
import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

/** Prints the clock in milliseconds, and stops the app after six frames. **/
class Game {
	@:system(Start)
	static function begin(display:Res<Display>) {
		Sys.println('start: ${display.width} x ${display.height} at scale ${display.scale}');
	}

	@:system(Fixed)
	static function step(time:Res<Time>) {
		Sys.println('  fixed step ${time.steps}: ${ms(time.fixedElapsed)} ms');
	}

	@:system(Update)
	static function update(time:Res<Time>, lifecycle:ResMut<Lifecycle>) {
		Sys.println('frame ${time.frame}: ${time.steps} fixed steps, ${ms(time.elapsed)} ms');
		if (time.frame == 6)
			lifecycle.quit();
	}

	static function ms(seconds:Float):Int
		return Math.round(seconds * 1000);
}
