package hxn.me;

/**
	The clock of the app, a kernel resource. The loop advances it once a
	frame, before `Fixed`. `app.step` in `hxnme.toml` sets the number of
	fixed steps in a second. The default is 60.
**/
class Time {
	/** The longest frame the clock counts, in seconds. Longer frames count as this long. **/
	public static inline final MAX_DELTA = 0.25;

	/** The seconds of the last frame, at most `MAX_DELTA`. **/
	public var delta(default, null) = 0.0;

	/** The seconds of all frames so far. **/
	public var elapsed(default, null) = 0.0;

	/** The number of frames that ran `Update`, including this one. **/
	public var frame(default, null) = 0;

	/** The seconds of one fixed step. **/
	public final step:Float = 1 / Project.number("app.step", 60);

	/** The fixed steps that this frame ran. **/
	public var steps(default, null) = 0;

	/** The seconds of all fixed steps so far. **/
	public var fixedElapsed(default, null) = 0.0;

	/**
		The part of a fixed step that the clock has counted and not run yet,
		from 0 to 1. Systems in `Render` use it to draw between two fixed steps.
	**/
	public var alpha(default, null) = 0.0;

	public function new() {}
}
