package steps;

import hxn.me.Res;
import hxn.me.ResMut;

class ClockSystems {
	@:system(Fixed, description = "Counts one fixed step")
	static function tick(clock:ResMut<Clock>) {
		clock.ticks++;
	}

	@:system(Update)
	static function publish(clock:Res<Clock>) {
		Sys.println('steps.ClockSystems.publish: ${clock.ticks} ticks');
	}
}
