import steps.Clock;
import hxn.me.Res;
import hxn.me.ResMut;

/**
	The systems are declared out of order. The constraints put `move` after
	the systems of the clock plugin and before `report`. They put `clear`
	before `draw`.
**/
class Movement {
	@:system(Render)
	static function draw(world:Res<World>) {
		Sys.println('Movement.draw: x = ${world.x}');
	}

	@:system(Update, after = move)
	static function report(world:Res<World>) {
		Sys.println('Movement.report: x = ${world.x}');
	}

	@:system(Update, after = steps.ClockSystems, description = "Moves the point ten units for each fixed step")
	public static function move(clock:Res<Clock>, world:ResMut<World>) {
		world.x = clock.ticks * 10;
		Sys.println("Movement.move");
	}

	@:system(Render, before = [Movement.draw])
	static function clear() {
		Sys.println("Movement.clear");
	}
}
