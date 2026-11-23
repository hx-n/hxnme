package hxn.me.render2d;

/**
	`Shader` draws every instance of the 2D renderer. Each instance is a quad
	in the world's XY plane, with its corner at `rect.xy` and its size in
	`rect.zw`, turned by the angle in `xform` around a point of the quad. The
	camera's matrix maps it to the view. `shape.x` sets what the quad shows: 0 samples `image` at the quad's
	`uv` and multiplies it by `color`, 1 uses the red channel of `image` as the
	coverage of a glyph in `color`, 2 is a rectangle with the corner radii in
	`radius`, 3 is an ellipse, and 4 is a line with round ends from `radius.xy`
	to `radius.zw`, in pixels from the quad's corner, with the radius
	`shape.z` at its start and `shape.w` at its end. When `shape.y` is above
	0, the shape has a border of that width in the color in `border`. Signed distance functions give
	the shapes their edges, so they are smooth at any size and angle. The
	functions come from Ashui's `Sdf.hx`.
**/
class Shader implements hxn.gpu.Shader {
	static var SRC = {
		@input var input : { rect : Vec4, uv : Vec4, color : Vec4, xform : Vec4, shape : Vec4, radius : Vec4, border : Vec4 };
		var output : { position : Vec4, color : Vec4 };
		/**
			The columns of the matrix that maps the plane's points to clip space:
			the camera's matrix times the plane's. The third column is left out,
			because 2D content lies at z = 0 in its plane, so it adds nothing.
		**/
		@param var matrix0 : Vec4;
		@param var matrix1 : Vec4;
		@param var matrix3 : Vec4;
		/** `x` is 1 when the camera's view has y down, as with a screen camera, and 0 when it has y up. **/
		@param var flags : Vec4;
		@param var image : Sampler2D;
		/** The fragment's position in the quad, in pixels from its top-left corner. **/
		var local : Vec2;
		var size : Vec2;
		var texel : Vec2;
		var tint : Vec4;
		var kind : Vec4;
		var radii : Vec4;
		var edge : Vec4;

		function vertex() {
			var corner = vec2(float(vertexID % 2), float(vertexID / 2));
			var r = input.rect;
			size = r.zw;
			local = corner * r.zw;
			// The top row of an image is v = 0, and the top of the quad is its larger y in a
			// view with y up, and its smaller y in a view with y down.
			texel = mix(input.uv.xy, input.uv.zw, vec2(corner.x, flags.x > 0.5 ? corner.y : 1. - corner.y));
			tint = input.color;
			kind = input.shape;
			radii = input.radius;
			edge = input.border;
			var origin = input.xform.zw * r.zw;
			var d = local - origin;
			var c = input.xform.x;
			var s = input.xform.y;
			var world = r.xy + origin + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
			output.position = matrix0 * world.x + matrix1 * world.y + matrix3;
		}

		function fragment() {
			// WGSL takes derivatives and samples textures only outside branches.
			var sampled = image.get(texel);
			var pixel = max(length(fwidth(local)) * 0.7071, 0.0001);
			var halfSize = size * 0.5;
			var rel = local - halfSize;
			// The radii are top left, top right, bottom right and bottom left, as the view shows them.
			var up = flags.x > 0.5 ? -rel.y : rel.y;
			var rr = radii.w;
			if (up > 0.) {
				rr = radii.x;
				if (rel.x > 0.)
					rr = radii.y;
			} else if (rel.x > 0.) {
				rr = radii.z;
			}
			rr = min(rr, min(halfSize.x, halfSize.y));
			var qa = abs(rel) - halfSize + vec2(rr, rr);
			var box = length(max(qa, vec2(0., 0.))) + min(max(qa.x, qa.y), 0.) - rr;
			var oval = (length(rel / halfSize) - 1.) * min(halfSize.x, halfSize.y);
			// The distance to a line whose radius changes from its start to its end.
			var ab = radii.zw - radii.xy;
			var t = clamp(dot(local - radii.xy, ab) / max(dot(ab, ab), 0.0001), 0., 1.);
			var segment = length(local - (radii.xy + ab * t)) - mix(kind.z, kind.w, t);
			var d = kind.x < 2.5 ? box : (kind.x < 3.5 ? oval : segment);
			var fill = clamp(0.5 - d / pixel, 0., 1.);
			var inner = clamp(0.5 - (d + kind.y) / pixel, 0., 1.);
			var shaped = kind.y > 0. ? mix(edge, tint, inner) : tint;
			var result = vec4(shaped.rgb, shaped.a * fill);
			if (kind.x < 0.5)
				result = sampled * tint;
			else if (kind.x < 1.5)
				result = vec4(tint.rgb, tint.a * sampled.r);
			// Fully transparent fragments write no depth, so the empty corners of a quad hide nothing.
			if (result.a < 0.004)
				discard;
			output.color = result;
		}
	};
}
