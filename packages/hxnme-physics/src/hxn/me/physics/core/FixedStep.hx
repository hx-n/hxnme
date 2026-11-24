package hxn.me.physics.core;

/**
 * `FixedStep` runs physics at a fixed rate under frames of any length. Each
 * frame, `advance` takes the frame's duration and returns how many steps to
 * run. The time left over carries to the next frame.
 *
 * ```haxe
 * var steps = clock.advance(frameTime);
 * for (i in 0...steps) {
 *     binding.pushStep(clock.stepFraction(i));
 *     world.step(clock.step);
 * }
 * binding.readback(clock.alpha);
 * ```
 *
 * Physics trails the frame by the leftover time. `stepFraction(i)` places the
 * end of step `i` between the previous frame (0) and this one (1), for
 * sampling animation at the step's own time. `alpha` places the frame between
 * the last two steps, for drawing.
 */
class FixedStep {
	/** Sets the seconds per physics step. */
	public var step(default, null):Float;

	/** Sets the most steps that one frame can run. Time beyond them is dropped, so a slow frame cannot snowball. */
	public var maxSteps:Int;

	/** Holds the time carried over, in [0, step). */
	public var remainder(default, null):Float = 0.0;

	/** Counts the steps that `advance` asked for this frame. */
	public var steps(default, null):Int = 0;

	var frameTime = 0.0;
	var startRemainder = 0.0;

	public function new(step:Float, maxSteps:Int = 8) {
		if (!(step > 0.0) || !Math.isFinite(step))
			throw 'step must be positive';
		if (maxSteps < 1)
			throw 'maxSteps must be at least 1';
		this.step = step;
		this.maxSteps = maxSteps;
	}

	/** Adds a frame of `seconds` and returns how many steps to run for it. */
	public function advance(seconds:Float):Int {
		if (!(seconds >= 0.0) || !Math.isFinite(seconds))
			seconds = 0.0;
		startRemainder = remainder;
		var total = remainder + seconds;
		var n = Math.floor(total / step);
		if (n > maxSteps) {
			n = maxSteps;
			total = n * step;
			seconds = total - startRemainder;
		}
		frameTime = seconds;
		remainder = total - n * step;
		if (remainder < 0.0)
			remainder = 0.0;
		steps = n;
		return n;
	}

	/** Returns where the end of this frame's step `i` lies between the previous frame (0) and this one (1). */
	public function stepFraction(i:Int):Float {
		if (frameTime <= 0.0)
			return 1.0;
		var f = ((i + 1) * step - startRemainder) / frameTime;
		return f < 0.0 ? 0.0 : f > 1.0 ? 1.0 : f;
	}

	/** Returns how far this frame is between the last two steps, for drawing physics. It is the leftover time over the step. */
	public var alpha(get, never):Float;

	inline function get_alpha():Float {
		return remainder / step;
	}
}
