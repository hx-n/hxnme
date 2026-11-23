import hxn.me.Display;
import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

/**
	Counts three frames of the headless host, then stops the app. The last
	line prints from the system, because under Emscripten `App.run` returns
	before the frames run.
**/
class Count {
	@:system(Start)
	static function begin(display:Res<Display>) {
		Sys.println('start: ${display.width} x ${display.height}');
	}

	@:system(Update)
	static function count(time:Res<Time>, lifecycle:ResMut<Lifecycle>) {
		Sys.println('frame ${time.frame}');
		if (time.frame == 3) {
			lifecycle.quit();
			Sys.println("Headless checks passed");
		}
	}
}
