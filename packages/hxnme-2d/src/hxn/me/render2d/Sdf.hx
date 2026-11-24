package hxn.me.render2d;

/**
	`Sdf` holds the signed distance functions of the 2D shapes, for shaders
	that `@:import` it. Each function returns the distance from `p` to the
	shape's edge: negative inside, positive outside. The functions come from
	Ashui's `Sdf.hx`, which ports them from Blinc.
**/
class Sdf implements hxn.gpu.Shader {
	static var SRC = {
		/**
			Returns the distance to a rectangle centered on the origin, with half
			size `half`. Each corner has its radius in `radii` and its shape in
			`shapes`, both top left, top right, bottom right and bottom left,
			with y up. A shape is the `n` of `CornerShape`: 1 round, 2 squircle,
			0 bevel, -1 scoop, 100 or more square, -100 or less notch. The
			distance changes by one pixel for each pixel, so borders have the
			same width at every shape.
		**/
		function shapedBox(p:Vec2, half:Vec2, radii:Vec4, shapes:Vec4):Float {
			var q = abs(p) - half;
			var r = radii.w;
			var n = shapes.w;
			if (p.y > 0.) {
				r = radii.x;
				n = shapes.x;
				if (p.x > 0.) {
					r = radii.y;
					n = shapes.y;
				}
			} else if (p.x > 0.) {
				r = radii.z;
				n = shapes.z;
			}
			r = min(r, min(half.x, half.y));
			var qa = q + vec2(r, r);
			// The rectangle with square corners.
			var box = length(max(q, vec2(0., 0.))) + min(max(q.x, q.y), 0.);
			var d = box;
			if (r <= 0. || n >= 100.) {
				d = box;
			} else if (n <= -100.) {
				// The rectangle less the square beyond the corner's step.
				var cut = length(max(-qa, vec2(0., 0.))) + min(max(-qa.x, -qa.y), 0.);
				d = max(box, -cut);
			} else if (abs(n - 1.) < 0.01) {
				d = length(max(qa, vec2(0., 0.))) + min(max(qa.x, qa.y), 0.) - r;
			} else if (n < 0.) {
				// The rectangle less a superellipse centered on the corner's tip.
				d = max(box, -superellipse(-q, r, n));
			} else if (abs(n) < 0.01) {
				// The rectangle cut by the line across the corner.
				d = max(box, (qa.x + qa.y - r) * 0.70710678);
			} else {
				d = max(box, superellipse(qa, r, n));
			}
			return d;
		}

		/**
			Returns the signed distance from `v`, at least 0 on both axes, to a
			quarter superellipse of radius `r` and exponent `2^|n|` about the
			origin. The norm is divided by the length of its gradient, so the
			distance changes by one pixel for each pixel.
		**/
		function superellipse(v:Vec2, r:Float, n:Float):Float {
			var e = pow(2., min(abs(n), 5.));
			// WGSL leaves pow(0, 0) undefined, so t stays above 0.
			var t = max(v / max(r, 0.001), vec2(0.000001, 0.000001));
			// Dividing by the larger component keeps t^e from underflowing at large e.
			var m = max(t.x, t.y);
			var u = t / m;
			var norm = m * pow(pow(u.x, e) + pow(u.y, e), 1. / e);
			var grad = vec2(pow(min(t.x / norm, 1.), e - 1.), pow(min(t.y / norm, 1.), e - 1.));
			return (norm - 1.) * r / max(length(grad), 0.0001);
		}

		/** Returns the error function of `x`, to Abramowitz and Stegun 7.1.26. **/
		function erf(x:Float):Float {
			var a = abs(x);
			var t = 1. / (1. + 0.3275911 * a);
			var y = 1. - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-a * a);
			return sign(x) * y;
		}

		/** Returns the distance to an ellipse centered on the origin, with half size `half`. **/
		function ellipse(p:Vec2, half:Vec2):Float {
			return (length(p / half) - 1.) * min(half.x, half.y);
		}

		/** Returns the distance to a line from `a` to `b` with round ends. Its radius is `ra` at `a` and `rb` at `b`. **/
		function taperedLine(p:Vec2, a:Vec2, b:Vec2, ra:Float, rb:Float):Float {
			var ab = b - a;
			var t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0., 1.);
			return length(p - (a + ab * t)) - mix(ra, rb, t);
		}
	};
}
