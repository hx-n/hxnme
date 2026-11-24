package hxn.me.render2d;

/**
	`Draw` holds what the app draws again in every frame, for example shapes and
	debug lines. Systems call its methods in each frame. The renderer draws what
	they added in that frame, in the order that they added it, through each
	camera that shows its layer.

	Positions are in the XY plane of the world. Each shape's `x`, `y` is its
	corner with the smaller coordinates. With y up, that is the bottom-left
	corner. Through a screen camera, it is the top-left corner. Colors are
	0xRRGGBB, with a separate `alpha` from 0 to 1.

	Shapes get their edges from signed distance functions, so they stay smooth
	at any size, zoom and angle. Each change of texture between sprites and text
	starts a new batch. Shapes never start a batch.
**/
class Draw {
	@:allow(hxn.me.render2d) final instances = new Instances();
	@:allow(hxn.me.render2d) final runs:Array<Run> = [];

	/** The layer bits of the content added next. Cameras show the layers in their `layers`. **/
	public var layer = 1;

	/** The plane of the content added next, or null for the XY plane of the world. **/
	public var plane:Null<Plane>;

	/** The clip of the content added next, or null for none. **/
	public var clip:Null<Clip>;

	public function new() {}

	/**
		Adds a rectangle. `radius` is the radius of its corners, and `corner`
		is their shape, such as `Squircle`. If `border` is above 0, the
		rectangle has a border of that width in `borderColor`.
	**/
	public function rect(x:Float, y:Float, width:Float, height:Float, color = 0xFFFFFF, alpha = 1.0, radius = 0.0, border = 0.0, borderColor = 0x000000,
			borderAlpha = 1.0, corner:CornerShape = Round):Void {
		var i = shape(2, x, y, width, height, color, alpha, border, borderColor, borderAlpha);
		instances.set(Instances.SHAPE, i, 2, border, corner, 0);
		instances.set(Instances.RADIUS, i, radius, radius, radius, radius);
	}

	/**
		Adds a shadow of the rectangle at `x`, `y`, blurred by `blur` as with
		CSS `box-shadow`, in `color` and `alpha`. `radius` and `corner` give
		the rectangle's corners. Add the shadow before the shape that casts it,
		and move it by the shadow's offset. The shadow is one instance, a quad
		larger than the rectangle by the reach of the blur. The shader computes
		the blur for each pixel from its distance to the rectangle.
	**/
	public function shadow(x:Float, y:Float, width:Float, height:Float, blur:Float, color = 0x000000, alpha = 0.5, radius = 0.0,
			corner:CornerShape = Round):Void {
		// The blur reaches one and a half times `blur` past the rectangle, and one more pixel covers the edge.
		var grow = blur * 1.5 + 1;
		var i = shape(6, x - grow, y - grow, width + grow * 2, height + grow * 2, color, alpha, 0, 0, 1);
		instances.set(Instances.SHAPE, i, 6, blur, corner, grow);
		instances.set(Instances.RADIUS, i, radius, radius, radius, radius);
	}

	/** Adds a circle around `x`, `y`. With `border` above 0, it has a border of that width in `borderColor`. **/
	public function circle(x:Float, y:Float, radius:Float, color = 0xFFFFFF, alpha = 1.0, border = 0.0, borderColor = 0x000000, borderAlpha = 1.0):Void
		shape(3, x - radius, y - radius, radius * 2, radius * 2, color, alpha, border, borderColor, borderAlpha);

	/** Adds an ellipse that fills the rectangle at `x`, `y`. **/
	public function ellipse(x:Float, y:Float, width:Float, height:Float, color = 0xFFFFFF, alpha = 1.0):Void
		shape(3, x, y, width, height, color, alpha, 0, 0, 1);

	/**
		Adds a line with round ends from `x0`, `y0` to `x1`, `y1`. It is
		`width` wide at its start and `endWidth` wide at its end. `endWidth`
		defaults to `width`.
	**/
	public function line(x0:Float, y0:Float, x1:Float, y1:Float, width:Float, color = 0xFFFFFF, alpha = 1.0, ?endWidth:Float):Void {
		var ra = width / 2;
		var rb = (endWidth != null ? endWidth : width) / 2;
		var left = Math.min(x0 - ra, x1 - rb), bottom = Math.min(y0 - ra, y1 - rb);
		var right = Math.max(x0 + ra, x1 + rb), top = Math.max(y0 + ra, y1 + rb);
		var i = shape(4, left, bottom, right - left, top - bottom, color, alpha, 0, 0, 1);
		instances.set(Instances.SHAPE, i, 4, 0, ra, rb);
		instances.set(Instances.RADIUS, i, x0 - left, y0 - bottom, x1 - left, y1 - bottom);
	}

	/**
		Adds a stroke through `points`, which holds x, y pairs. The stroke
		is made of lines with round ends. `widths` gives the width at each
		point, for example from the pressure of a pen. Without `widths`, the
		stroke is `width` wide.
	**/
	public function stroke(points:Array<Float>, width:Float, color = 0xFFFFFF, alpha = 1.0, ?widths:Array<Float>):Void {
		var n = points.length >> 1;
		for (k in 0...n - 1) {
			var a = widths != null ? widths[k] : width;
			var b = widths != null ? widths[k + 1] : width;
			line(points[k * 2], points[k * 2 + 1], points[k * 2 + 2], points[k * 2 + 3], a, color, alpha, b);
		}
	}

	/**
		Adds `texture` stretched over the rectangle at `x`, `y`, multiplied by
		`color` and `alpha`. `angle` turns it in radians about its center.
		`u0`, `v0`, `u1`, `v1` select part of the texture, from 0 to 1.
	**/
	public function sprite(texture:Texture, x:Float, y:Float, width:Float, height:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0, u0 = 0.0, v0 = 0.0,
			u1 = 1.0, v1 = 1.0):Void {
		var i = instances.add();
		instances.set(Instances.RECT, i, x, y, width, height);
		instances.set(Instances.UV, i, u0, v0, u1, v1);
		tint(Instances.COLOR, i, color, alpha);
		instances.set(Instances.XFORM, i, Math.cos(angle), Math.sin(angle), 0.5, 0.5);
		textured(texture, i);
	}

	/**
		Adds `texture` as a nine-slice over the rectangle at `x`, `y`. The
		corners keep their size, the edges stretch along their length, and
		the center stretches in both directions. `left`, `top`, `right` and
		`bottom` are the widths of the borders in texture pixels. Each
		texture pixel covers `scale` logical pixels. If the rectangle is
		smaller than its borders, the borders shrink to fit. The top border
		stays at the top through a camera with y up and through a screen
		camera. `angle` turns the rectangle in radians about its center.
	**/
	public function nineSlice(texture:Texture, x:Float, y:Float, width:Float, height:Float, left:Float, top:Float, right:Float, bottom:Float,
			color = 0xFFFFFF, alpha = 1.0, angle = 0.0, scale = 1.0):Void
		slice(texture, 0, 0, 1, 1, texture.width, texture.height, x, y, width, height, left, top, right, bottom, color, alpha, angle, scale);

	/**
		Adds `region` of an atlas stretched over the rectangle at `x`, `y`,
		multiplied by `color` and `alpha`. The rectangle is the region's size
		in texture pixels unless `width` and `height` are given. `angle` turns
		it in radians about its center.
	**/
	public function region(region:Region, x:Float, y:Float, ?width:Float, ?height:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0):Void
		sprite(region.texture, x, y, width != null ? width : region.width, height != null ? height : region.height, color, alpha, angle, region.u0,
			region.v0, region.u1, region.v1);

	/**
		Adds `region` of an atlas as a nine-slice over the rectangle at `x`,
		`y`, with the region's borders, as `nineSlice` does with a whole
		texture.
	**/
	public function regionSlice(region:Region, x:Float, y:Float, width:Float, height:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0,
			scale = 1.0):Void
		slice(region.texture, region.u0, region.v0, region.u1, region.v1, region.width, region.height, x, y, width, height, region.left, region.top,
			region.right, region.bottom, color, alpha, angle, scale);

	// Adds a nine-slice of the part of `texture` from `u0`, `v0` to `u1`, `v1`, which is `texelsX` by `texelsY` texels.
	function slice(texture:Texture, u0:Float, v0:Float, u1:Float, v1:Float, texelsX:Float, texelsY:Float, x:Float, y:Float, width:Float, height:Float,
			left:Float, top:Float, right:Float, bottom:Float, color:Int, alpha:Float, angle:Float, scale:Float):Void {
		var i = instances.add();
		instances.set(Instances.RECT, i, x, y, width, height);
		instances.set(Instances.UV, i, u0, v0, u1, v1);
		tint(Instances.COLOR, i, color, alpha);
		instances.set(Instances.XFORM, i, Math.cos(angle), Math.sin(angle), 0.5, 0.5);
		// The shader fits the borders to the rectangle and maps each pixel to its piece of the texture.
		instances.set(Instances.SHAPE, i, 5, scale, texelsX, texelsY);
		instances.set(Instances.RADIUS, i, left * scale, top * scale, right * scale, bottom * scale);
		textured(texture, i);
	}

	/**
		Adds `text` in `color` and `alpha`, with the corner of its box that
		has the smaller coordinates at `x`, `y`. `angle` turns it in radians
		about the center of the box. The text reads upright through a camera
		with y up and through a screen camera. Color glyphs, such as emoji,
		keep their own colors and use only `alpha`.
	**/
	public function text(text:Text, x:Float, y:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0):Void
		text.write(instances, x, y, color, alpha, angle, null, textured);

	// Adds instance `i`, which draws with `texture`, to the last run. If the texture, layer or plane differs, it starts a new run.
	function textured(texture:Texture, i:Int):Void {
		var last = runs.length > 0 ? runs[runs.length - 1] : null;
		if (last == null || last.layer != layer || last.plane != plane || last.clip != clip || (last.texture != null && last.texture != texture))
			runs.push({texture: texture, layer: layer, plane: plane, clip: clip, start: i, count: 1});
		else {
			last.texture = texture;
			last.count++;
		}
	}

	@:allow(hxn.me.render2d) function clear():Void {
		instances.clear();
		runs.resize(0);
	}

	function shape(kind:Int, x:Float, y:Float, width:Float, height:Float, color:Int, alpha:Float, border:Float, borderColor:Int, borderAlpha:Float):Int {
		var i = instances.add();
		instances.set(Instances.RECT, i, x, y, width, height);
		tint(Instances.COLOR, i, color, alpha);
		instances.set(Instances.XFORM, i, 1, 0, 0.5, 0.5);
		instances.set(Instances.SHAPE, i, kind, border, 0, 0);
		tint(Instances.BORDER, i, borderColor, borderAlpha);
		// Shapes sample no texture, so each shape joins the run before it.
		var last = runs.length > 0 ? runs[runs.length - 1] : null;
		if (last == null || last.layer != layer || last.plane != plane || last.clip != clip)
			runs.push({texture: null, layer: layer, plane: plane, clip: clip, start: i, count: 1});
		else
			last.count++;
		return i;
	}

	inline function tint(field:Int, i:Int, color:Int, alpha:Float):Void
		instances.set(field, i, ((color >> 16) & 0xFF) / 255, ((color >> 8) & 0xFF) / 255, (color & 0xFF) / 255, alpha);
}

/** Each run is a range of instances that draw with one texture, or with none. **/
typedef Run = {
	var texture:Null<Texture>;
	var layer:Int;
	var plane:Null<Plane>;
	var clip:Null<Clip>;
	var start:Int;
	var count:Int;
}
