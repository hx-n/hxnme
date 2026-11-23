import hxn.me.Display;
import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

/** Prints the size of the window in logical pixels, and stops the app after three frames. **/
class Frames {
	@:system(Start)
	static function begin(display:Res<Display>) {
		Sys.println('window: ${Math.round(display.width / display.scale)} x ${Math.round(display.height / display.scale)}');
	}

	@:system(Update)
	static function count(time:Res<Time>, lifecycle:ResMut<Lifecycle>) {
		Sys.println('frame ${time.frame}');
		if (time.frame == 3)
			lifecycle.quit();
	}
}
