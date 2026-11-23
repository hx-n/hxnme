package hxn.me.gpu;

/**
	`Projection` sets how a camera maps what it sees onto its view. The world
	has y up, as in physics, and a camera looks along its -z.
**/
enum Projection {
	/**
		Things farther away look smaller. `fovY` is the vertical field of view
		in radians, and the camera sees from `near` to `far` in front of it.
	**/
	Perspective(fovY:Float, near:Float, far:Float);

	/**
		Things keep their size at any distance. The view is `height` world
		units high, or one unit for each logical pixel when `height` is 0, and
		its width follows the view's aspect ratio. The camera sees from `near`
		to `far` in front of it.
	**/
	Orthographic(height:Float, near:Float, far:Float);

	/**
		The view shows logical pixels, with the origin at its top-left corner
		and y down, for UI, HUDs and pixel-exact 2D. The camera's `x` and `y`
		move the view, and its rotation has no effect.
	**/
	Screen;
}
