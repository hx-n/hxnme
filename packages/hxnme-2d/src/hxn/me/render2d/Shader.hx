package hxn.me.render2d;

/**
	`Shader` draws every instance of the 2D renderer. Each instance is a quad in
	the XY plane of the world, with its corner at `rect.xy` and its size in
	`rect.zw`. It turns by the angle in `xform` about a point of the quad, and
	the camera's matrix maps it to the view. `shape.x` selects what the quad
	shows:

	- 0 samples `image` at the quad's `uv` and multiplies it by `color`.
	- 1 is a glyph, with its coverage in the red channel of `image`, in `color`.
	- 2 is a rectangle, with the corner radii in `radius` and the
	  `CornerShape` of its corners in `shape.z`.
	- 3 is an ellipse.
	- 4 is a line with round ends, from `radius.xy` to `radius.zw` in pixels
	  from the quad's corner. Its radius is `shape.z` at its start and `shape.w`
	  at its end.
	- 5 is a nine-slice of the part of `image` in `uv`. `radius` holds its left,
	  top, right and bottom borders in pixels, `shape.y` the pixels for each
	  texel, and `shape.zw` the size of the part in texels.
	- 6 is a shadow: a rectangle with the corner radii in `radius` and the
	  `CornerShape` in `shape.z`, blurred by `shape.y` as with CSS
	  `box-shadow`. The quad is larger than the rectangle by `shape.w` on each
	  side, to hold the blur.
	- 7 is the silhouette of the part of `image` in `uv`: its alpha, blurred by
	  `shape.y`, in `color`. The quad is larger than the silhouette, which is
	  `radius.xy` large, by `shape.z` on each side.

	For kinds 0 and 7, when `radius.w` is 1, `rect.xy` is the position of the
	pivot, and `xform.zw` the pivot as a fraction of the quad, measured from
	the image's top left. The shader places the quad's corner from it, for the
	view's orientation. Otherwise `rect.xy` is the corner with the smaller
	coordinates, and `xform.zw` only the point that `angle` turns about.

	For kinds 2 to 4, when `shape.y` is above 0, the shape has a border of that
	width in the color in `border`. For kinds 0 and 1, when `shape.w` is above
	0, the quad is a glyph of a text whose box starts at y = `shape.z` and is
	`shape.w` high.

	When the run has a clip, the fragment shows only where it is inside the
	shaped rectangle in `clipRect` and `clipShape`, in the plane's coordinates.

	The distance functions in `Sdf` give the shapes their edges, so they are
	smooth at any size and angle. `Slice` maps the pixels of a nine-slice to its
	image.
**/
class Shader implements hxn.gpu.Shader {
	static var SRC = {
		@:import hxn.me.render2d.Sdf;
		@:import hxn.me.render2d.Slice;
		@input var input : { rect : Vec4, uv : Vec4, color : Vec4, xform : Vec4, shape : Vec4, radius : Vec4, border : Vec4 };
		var output : { position : Vec4, color : Vec4 };
		/**
			The columns of the matrix that maps the plane's points to clip space,
			which is the camera's matrix times the plane's matrix. The third
			column is left out, because 2D content lies at z = 0 in its plane.
		**/
		@param var matrix0 : Vec4;
		@param var matrix1 : Vec4;
		@param var matrix3 : Vec4;
		/** `x` is 1 when the camera's view has y down, as with a screen camera, and 0 when it has y up. **/
		@param var flags : Vec4;
		/** The clip's corner with the smaller coordinates and its size, in the plane's coordinates. **/
		@param var clipRect : Vec4;
		/** The clip's corner radius in `x` and its `CornerShape` in `y`. `z` is 1 when the run has a clip. **/
		@param var clipShape : Vec4;
		@param var image : Sampler2D;
		/** The fragment's position in the quad, in pixels from its corner at `rect.xy`. **/
		var local : Vec2;
		var size : Vec2;
		var texel : Vec2;
		var tint : Vec4;
		var kind : Vec4;
		var radii : Vec4;
		var edge : Vec4;
		/** The fragment's position in the plane's coordinates. **/
		var at : Vec2;
		/** The part of `image` that a nine-slice shows. **/
		var region : Vec4;

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
			region = input.uv;
			// Glyphs are laid out from the top of their box,
			// which starts at y = shape.z and is shape.w high. In a view with y up,
			// the shader mirrors them within the box, so they read upright.
			var mirror = 0.;
			if (input.shape.x < 1.5 && input.shape.w > 0. && flags.x < 0.5)
				mirror = 1.;
			var cornerY = mix(r.y, 2. * input.shape.z + input.shape.w - r.y - r.w, mirror);
			var pivot = vec2(input.xform.z, mix(input.xform.w, 1. - input.xform.w, mirror));
			// A sprite or silhouette with `radius.w` set is placed by its pivot: `rect.xy` is
			// the pivot's position, and `xform.zw` the pivot as a fraction of the quad, top
			// first in the image. The image's top is the quad's larger y in a view with y up.
			if ((input.shape.x < 0.5 || input.shape.x > 6.5) && input.radius.w > 0.5) {
				pivot = vec2(input.xform.z, flags.x > 0.5 ? input.xform.w : 1. - input.xform.w);
				cornerY = r.y - pivot.y * r.w;
			}
			var cornerX = (input.shape.x < 0.5 || input.shape.x > 6.5) && input.radius.w > 0.5 ? r.x - pivot.x * r.z : r.x;
			var origin = pivot * r.zw;
			var d = local - origin;
			var c = input.xform.x;
			var s = input.xform.y;
			var world = vec2(cornerX, cornerY) + origin + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
			at = world;
			output.position = matrix0 * world.x + matrix1 * world.y + matrix3;
		}

		function fragment() {
			// Nine-slices count their pixels from the top left, as the view shows it.
			var fromTop = vec2(local.x, flags.x > 0.5 ? local.y : size.y - local.y);
			var nine = kind.x > 4.5 ? 1. : 0.;
			// WGSL takes derivatives and samples textures only outside branches.
			// The borders as fractions of the part of the image, from the borders in texels.
			var texels = max(vec4(kind.y * kind.z, kind.y * kind.w, kind.y * kind.z, kind.y * kind.w), vec4(0.0001, 0.0001, 0.0001, 0.0001));
			var sliced = mix(region.xy, region.zw, sliceUv(fromTop, size, radii, radii / texels));
			var sampled = image.get(mix(texel, sliced, vec2(nine, nine)));
			var pixel = max(length(fwidth(local)) * 0.7071, 0.0001);
			var planePixel = max(length(fwidth(at)) * 0.7071, 0.0001);
			var halfSize = size * 0.5;
			var rel = local - halfSize;
			// The radii are top left, top right, bottom right and bottom left, as the view shows them.
			var up = vec2(rel.x, flags.x > 0.5 ? -rel.y : rel.y);
			// A shadow's box is its quad less the margin for the blur, in `shape.w`.
			var boxHalf = kind.x > 5.5 ? max(halfSize - vec2(kind.w, kind.w), vec2(0., 0.)) : halfSize;
			var box = shapedBox(up, boxHalf, radii, vec4(kind.z, kind.z, kind.z, kind.z));
			var d = kind.x < 2.5 ? box : (kind.x < 3.5 ? ellipse(rel, halfSize) : taperedLine(local, radii.xy, radii.zw, kind.z, kind.w));
			var fill = clamp(0.5 - d / pixel, 0., 1.);
			var inner = clamp(0.5 - (d + kind.y) / pixel, 0., 1.);
			var shaped = kind.y > 0. ? mix(edge, tint, inner) : tint;
			var result = vec4(shaped.rgb, shaped.a * fill);
			if (kind.x < 0.5)
				result = sampled * tint;
			else if (kind.x < 1.5)
				result = vec4(tint.rgb, tint.a * sampled.r);
			else if (kind.x > 6.5) {
				// The sprite's silhouette, its alpha blurred over a 5 by 5 grid of samples.
				// Samples outside the sprite's part of the image count as transparent.
				var spriteSize = max(radii.xy, vec2(0.0001, 0.0001));
				var base = (fromTop - vec2(kind.z, kind.z)) / spriteSize;
				var spread = vec2(kind.y, kind.y) * 0.5 / spriteSize;
				var sum = 0.;
				var weights = 0.;
				for (i in 0...5)
					for (j in 0...5) {
						var o = vec2(float(i) - 2., float(j) - 2.);
						var w = exp(-dot(o, o) * 0.25);
						var f = base + o * spread;
						var inside = step(0., f.x) * step(f.x, 1.) * step(0., f.y) * step(f.y, 1.);
						sum += image.getLod(mix(region.xy, region.zw, clamp(f, vec2(0., 0.), vec2(1., 1.))), 0.).a * inside * w;
						weights += w;
					}
				result = vec4(tint.rgb, tint.a * sum / weights);
			} else if (kind.x > 5.5)
				result = vec4(tint.rgb, tint.a * (kind.y > 0.001 ? 0.5 * (1. - erf(box / (0.7071 * kind.y))) : fill));
			else if (kind.x > 4.5)
				result = sampled * tint;
			if (clipShape.z > 0.5) {
				var clipHalf = clipRect.zw * 0.5;
				var clipped = shapedBox(at - clipRect.xy - clipHalf, clipHalf, vec4(clipShape.x, clipShape.x, clipShape.x, clipShape.x),
					vec4(clipShape.y, clipShape.y, clipShape.y, clipShape.y));
				result.a *= clamp(0.5 - clipped / planePixel, 0., 1.);
			}
			// Fully transparent fragments write no depth, so the empty corners of a quad hide nothing.
			if (result.a < 0.004)
				discard;
			output.color = result;
		}
	};
}
