package hxn.me.physics.core;

/**
 * Runs physics at a fixed rate under frames of any length. Each frame,
 * `advance` takes the frame's duration and says how many steps to run; the
 * time left over carries to the next frame.
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
 * sampling animation at the step's own time; `alpha` places the frame between
 * the last two steps, for drawing.
 */
class FixedStep {
	/** Seconds per physics step. */
	public var step(default, null):Float;

	/** Most steps one frame may run; time beyond them is dropped so a slow frame cannot snowball. */
	public var maxSteps:Int;

	/** Time carried over, in [0, step). */
	public var remainder(default, null):Float = 0.0;

	/** Steps `advance` asked for this frame. */
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

	/** Where the end of this frame's step `i` lies between the previous frame (0) and this one (1). */
	public function stepFraction(i:Int):Float {
		if (frameTime <= 0.0)
			return 1.0;
		var f = ((i + 1) * step - startRemainder) / frameTime;
		return f < 0.0 ? 0.0 : f > 1.0 ? 1.0 : f;
	}

	/** How far this frame is between the last two steps, for drawing physics: leftover time over the step. */
	public var alpha(get, never):Float;

	inline function get_alpha():Float {
		return remainder / step;
	}
}
