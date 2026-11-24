package steps;

import hxn.me.Res;
import hxn.me.ResMut;

@:plugin("check-clock", description = "Counts fixed steps")
@:systems(ClockSystems, ClockNotes)
class ClockPlugin implements hxn.me.Plugin {
	public function new() {}

	public function start():Void {}

	@:system(Start)
	static function begin(clock:ResMut<Clock>) {
		clock.ticks = 0;
		Sys.println("steps.ClockPlugin.begin");
	}
}

/** Holds a system in the plugin's module, which the schedule calls by its module path. **/
class ClockNotes {
	@:system(Start, after = ClockPlugin.begin)
	static function note(clock:Res<Clock>) {
		Sys.println('steps.ClockNotes.note: ${clock.ticks} ticks');
	}
}
