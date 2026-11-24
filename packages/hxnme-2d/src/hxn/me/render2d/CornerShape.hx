package hxn.me.render2d;

/**
	`CornerShape` is the shape of a rectangle's corners, as in CSS
	`corner-shape: superellipse(n)`. The corner follows `|x|^k + |y|^k = 1`
	with `k = 2^|n|`, scaled by the corner's radius. Values between the
	named ones give the shapes between them.
**/
enum abstract CornerShape(Float) from Float to Float {
	/** Circular corners. **/
	var Round = 1;

	/** Corners that blend smoothly into the straight sides. **/
	var Squircle = 2;

	/** Straight cuts across the corners. **/
	var Bevel = 0;

	/** Corners that curve inward. **/
	var Scoop = -1;

	/** Square corners. Every value of 100 or more is square. **/
	var Square = 100;

	/** Square steps cut into the corners. Every value of -100 or less is a notch. **/
	var Notch = -100;
}
