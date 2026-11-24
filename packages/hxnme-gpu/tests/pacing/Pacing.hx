import hxn.me.Display;
import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;
import hxn.me.gpu.Gpu;

/**
	`Pacing` presents frames with vsync and records how long each frame
	takes, after the first frames settle. The mean frame time must be within
	a tenth of the display's refresh period, and fewer than one frame in twenty
	can take more than one and a half periods. If the host also waits on its own
	timer, it misses refreshes, and its frames take two periods.
**/
class Pacing {
	static inline final SETTLE = 30;
	static inline final FRAMES = 180;
	static final times:Array<Float> = [];

	@:system(Update)
	static function record(gpu:Res<Gpu>, time:Res<Time>, display:Res<Display>, lifecycle:ResMut<Lifecycle>) {
		if (gpu.failure != null) {
			Sys.println('no GPU: ${gpu.failure}');
			Sys.exit(1);
		}
		if (gpu.presented < SETTLE)
			return;
		times.push(time.delta);
		if (times.length < FRAMES)
			return;
		var period = 1 / display.refresh;
		var mean = 0.0;
		var long = 0;
		for (t in times) {
			mean += t / times.length;
			if (t > period * 1.5)
				long++;
		}
		var steady = Math.abs(mean - period) < period * 0.1;
		var few = long < FRAMES * 0.05;
		Sys.println('vsync: ${display.vsync}');
		Sys.println('mean frame time within a tenth of the refresh period: $steady');
		Sys.println('fewer than one frame in twenty longer than one and a half periods: $few');
		if (!steady || !few) {
			Sys.println('the mean frame time is ${Math.round(mean * 100000) / 100} ms for a refresh of ${display.refresh} Hz, with $long long frames');
			Sys.exit(1);
		}
		(lifecycle : Lifecycle).quit();
	}
}
