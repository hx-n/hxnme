package hxn.me.render2d;

/**
	`Slice` maps the pixels of a nine-slice to its image, for shaders that
	`@:import` it.
**/
class Slice implements hxn.gpu.Shader {
	static var SRC = {
		/**
			Returns the image coordinate, from 0 to 1, of the point `p` of a box
			`size` large, both in pixels from its top left corner. `borders`
			holds the left, top, right and bottom borders in pixels, and
			`fractions` holds the same borders as fractions of the image. Each
			axis maps in three pieces: the borders keep their size, and the
			middle stretches. Borders wider than the box shrink to fit it.
		**/
		function sliceUv(p:Vec2, size:Vec2, borders:Vec4, fractions:Vec4):Vec2 {
			var eps = vec2(0.0001, 0.0001);
			var fit = min(vec2(1., 1.), size / max(borders.xy + borders.zw, eps));
			var near = borders.xy * fit;
			var far = borders.zw * fit;
			var middle = max(size - near - far, vec2(0., 0.));
			var stretch = vec2(1., 1.) - fractions.xy - fractions.zw;
			return min(p, near) / max(near, eps) * fractions.xy
				+ clamp(p - near, vec2(0., 0.), middle) / max(middle, eps) * stretch
				+ clamp(p - near - middle, vec2(0., 0.), far) / max(far, eps) * fractions.zw;
		}
	};
}
