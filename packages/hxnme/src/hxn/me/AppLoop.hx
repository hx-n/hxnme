package hxn.me;

/**
	`AppLoop` runs the phases of a schedule, one frame at a time. The host
	calls `frame` once for each frame. The first frame runs `Start`. Each
	frame then runs `Begin`, advances `Time`, runs `Fixed` once for each fixed
	step that the frame completes, and runs `Update` and `Render`. Then it
	clears the event queues. If the number of steps is close to a whole
	number, `SNAP` rounds it to that number. While the app is suspended, a
	frame runs no phase and does not advance `Time`. At the start of each
	frame, `hxn.Loop.sync` delivers the results of native libraries.
**/
class AppLoop {
	/** The largest number of fixed steps that one frame runs. Slower frames drop the steps after these. **/
	public static inline final MAX_STEPS = 8;

	/**
		The tolerance for whole steps, as a part of a fixed step, from
		`app.step_snap` in `hxnme.toml`. The default is 0.1, and 0 turns the
		correction off. If the steps that a frame owes are this close to a
		whole number, the frame runs that whole number of steps. So frames that
		vsync paces near the step rate run the same number of steps each,
		instead of zero in one frame and two in the next.
	**/
	public static final SNAP:Float = Project.number("app.step_snap", 0.1);

	/** The number of frames after which the app stops, from `app.frames` in `hxnme.toml`, or 0 to run until it quits. Checks use it. **/
	public static final FRAMES:Int = Project.integer("app.frames", 0);

	/** The clock that the loop advances. **/
	public final time:Time;

	/** The state of the app, which the host sets. **/
	public final lifecycle:Lifecycle;

	/** The surface of the app, which the host sets. **/
	public final display:Display;

	final phases:Phases;
	var started = false;
	var pending = 0.0;

	public function new(phases:Phases, time:Time, lifecycle:Lifecycle, display:Display) {
		this.phases = phases;
		this.time = time;
		this.lifecycle = lifecycle;
		this.display = display;
		hxn.Loop.manual = true;
	}

	/**
		Runs one frame that started `seconds` after the previous one. Returns
		false after the app stops.
	**/
	public function frame(seconds:Float):Bool {
		hxn.Loop.sync();
		#if hxnme_dev
		hxn.me.dev.Session.frame();
		#elseif (hl && hxnme_reload)
		hl.Api.checkReload();
		#end
		if (!started) {
			started = true;
			phases.start();
		}
		if (!lifecycle.running || lifecycle.suspended)
			return lifecycle.running;
		phases.begin();
		@:privateAccess {
			var delta = seconds < 0 ? 0 : seconds > Time.MAX_DELTA ? Time.MAX_DELTA : seconds;
			time.delta = delta;
			time.elapsed += delta;
			time.frame++;
			pending += delta;
			// `owed` is the number of steps that this frame owes. If it is within
			// SNAP of a whole number, the frame runs that number of steps, and the
			// difference stays in `pending`.
			var owed = pending / time.step;
			var whole = Math.round(owed);
			var steps = Math.abs(owed - whole) <= SNAP ? whole : Math.floor(owed);
			if (steps > MAX_STEPS) {
				steps = MAX_STEPS;
				pending = 0;
			} else {
				pending -= steps * time.step;
			}
			for (i in 0...steps) {
				time.steps = i + 1;
				time.fixedElapsed += time.step;
				phases.fixed();
			}
			time.steps = steps;
			time.alpha = pending <= 0 ? 0 : pending / time.step;
		}
		phases.update();
		phases.render();
		phases.end();
		if (FRAMES > 0 && time.frame >= FRAMES)
			lifecycle.quit();
		return lifecycle.running;
	}
}
