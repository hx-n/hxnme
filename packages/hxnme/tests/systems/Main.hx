/** Runs two frames of the schedule, each with two fixed steps. */
class Main {
	static function main() {
		hxn.me.Plugins.start();
		var schedule = hxn.me.App.schedule(Movement);
		schedule.start();
		for (frame in 0...2) {
			schedule.fixed();
			schedule.fixed();
			schedule.update();
			schedule.render();
		}
		Sys.println("System checks passed");
	}
}
