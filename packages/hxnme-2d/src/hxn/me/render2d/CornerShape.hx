package hxn.me.render2d;

/**
	`CornerShape` sets the shape of a rectangle's corners, as in CSS
	`corner-shape: superellipse(n)`. The corner follows `|x|^k + |y|^k = 1`
	with `k = 2^|n|`, scaled by the corner's radius. Values between the
	named ones give the shapes between them.
**/
enum abstract CornerShape(Float) from Float to Float {
	/** `Round` gives circular corners. **/
	var Round = 1;

	/** `Squircle` gives corners that blend smoothly into the straight sides. **/
	var Squircle = 2;

	/** `Bevel` cuts straight across the corners. **/
	var Bevel = 0;

	/** `Scoop` curves the corners inward. **/
	var Scoop = -1;

	/** `Square` gives square corners. Every value of 100 or more is square. **/
	var Square = 100;

	/** `Notch` cuts square steps into the corners. Every value of -100 or less is a notch. **/
	var Notch = -100;
}
