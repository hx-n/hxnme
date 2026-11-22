package steps;

import hxn.me.ResMut;

@:plugin("check-clock", description = "Counts fixed steps")
@:systems(ClockSystems)
class ClockPlugin implements hxn.me.Plugin {
	public function new() {}

	public function start():Void {}

	@:system(Start)
	static function begin(clock:ResMut<Clock>) {
		clock.ticks = 0;
		Sys.println("steps.ClockPlugin.begin");
	}
}
