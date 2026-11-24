package hxn.me.render2d;

import hxn.text.AtlasKind;

/**
	`Draw` is the resource for drawing that the app repeats every frame,
	such as shapes and debug lines. Systems call its methods in each frame,
	and the renderer draws what they added in that frame, in the order they
	added it, through each camera that shows its layer. Positions are in the
	world's XY plane, and `x`, `y` is the corner of a shape with the smaller
	coordinates: the bottom-left corner in a world with y up, and the top-left
	corner through a screen camera. Colors are 0xRRGGBB with a separate
	`alpha` from 0 to 1.

	Shapes have edges from signed distance functions, so they stay smooth at
	any size, zoom and angle. Each change of texture between sprites and text
	starts a new batch, and shapes never start one.
**/
class Draw {
	@:allow(hxn.me.render2d) final instances = new Instances();
	@:allow(hxn.me.render2d) final runs:Array<Run> = [];

	/** The layer bits of what is added next. Cameras show the layers in their `layers`. **/
	public var layer = 1;

	/** The plane that what is added next lies on, or null for the world's XY plane. **/
	public var plane:Null<Plane>;

	public function new() {}

	/**
		Adds a rectangle. `radius` rounds its corners. With `border` above 0,
		the rectangle has a border of that width in `borderColor`.
	**/
	public function rect(x:Float, y:Float, width:Float, height:Float, color = 0xFFFFFF, alpha = 1.0, radius = 0.0, border = 0.0, borderColor = 0x000000,
			borderAlpha = 1.0):Void {
		var i = shape(2, x, y, width, height, color, alpha, border, borderColor, borderAlpha);
		instances.set(Instances.RADIUS, i, radius, radius, radius, radius);
	}

	/** Adds a circle around `x`, `y`. With `border` above 0, it has a border of that width in `borderColor`. **/
	public function circle(x:Float, y:Float, radius:Float, color = 0xFFFFFF, alpha = 1.0, border = 0.0, borderColor = 0x000000, borderAlpha = 1.0):Void
		shape(3, x - radius, y - radius, radius * 2, radius * 2, color, alpha, border, borderColor, borderAlpha);

	/** Adds an ellipse that fills the rectangle at `x`, `y`. **/
	public function ellipse(x:Float, y:Float, width:Float, height:Float, color = 0xFFFFFF, alpha = 1.0):Void
		shape(3, x, y, width, height, color, alpha, 0, 0, 1);

	/**
		Adds a line from `x0`, `y0` to `x1`, `y1` with round ends. It is `width`
		wide at its start and `endWidth` wide at its end, by default `width`.
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
		Adds a stroke through the points of `points`, given as x, y pairs, as
		lines with round ends. `widths` gives the width at each point, such as
		from a pen's pressure; without it, the stroke is `width` wide.
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
		Adds `texture` as a nine-slice over the rectangle at `x`, `y`: the
		corners keep their size, the edges stretch along their length, and the
		center stretches both ways. `left`, `top`, `right` and `bottom` are the
		widths of the borders in texture pixels, drawn `scale` logical pixels
		for each texture pixel. When the rectangle is smaller than its borders,
		the borders shrink to fit. The top border reads at the top through a
		camera with y up and through a screen camera. `angle` turns the
		rectangle in radians about its center.
	**/
	public function nineSlice(texture:Texture, x:Float, y:Float, width:Float, height:Float, left:Float, top:Float, right:Float, bottom:Float,
			color = 0xFFFFFF, alpha = 1.0, angle = 0.0, scale = 1.0):Void {
		var l = left * scale, r = right * scale, t = top * scale, b = bottom * scale;
		var fitX = l + r > width ? width / (l + r) : 1.0;
		var fitY = t + b > height ? height / (t + b) : 1.0;
		l *= fitX;
		r *= fitX;
		t *= fitY;
		b *= fitY;
		var xs = [x, x + l, x + width - r, x + width];
		// Rows run from the top of the box, as for text, and the shader mirrors them for a view with y up.
		var ys = [y, y + t, y + height - b, y + height];
		var us = [0, left / texture.width, 1 - right / texture.width, 1];
		var vs = [0, top / texture.height, 1 - bottom / texture.height, 1];
		var c = Math.cos(angle), s = Math.sin(angle);
		for (row in 0...3)
			for (col in 0...3) {
				var pw = xs[col + 1] - xs[col], ph = ys[row + 1] - ys[row];
				if (pw <= 0 || ph <= 0)
					continue;
				var i = instances.add();
				instances.set(Instances.RECT, i, xs[col], ys[row], pw, ph);
				instances.set(Instances.UV, i, us[col], vs[row], us[col + 1], vs[row + 1]);
				tint(Instances.COLOR, i, color, alpha);
				instances.set(Instances.XFORM, i, c, s, (x + width / 2 - xs[col]) / pw, (y + height / 2 - ys[row]) / ph);
				instances.set(Instances.SHAPE, i, 0, 0, y, height);
				textured(texture, i);
			}
	}

	/**
		Adds `text` with its box's corner with the smaller coordinates at `x`,
		`y`, in `color` and `alpha`. `angle` turns it in radians about the
		box's center. The text reads upright through a camera with y up and
		through a screen camera. Color glyphs, such as emoji, keep their own
		colors and take only `alpha`.
	**/
	public function text(text:Text, x:Float, y:Float, color = 0xFFFFFF, alpha = 1.0, angle = 0.0):Void {
		var laid = text.layout();
		var w = laid.width, h = laid.height;
		var c = Math.cos(angle), s = Math.sin(angle);
		for (g in laid.glyphs) {
			var atlas = text.atlas(g.kind);
			if (atlas == null || g.width <= 0 || g.height <= 0)
				continue;
			var i = instances.add();
			// Glyph rects are laid out from the top of the box. The shader mirrors
			// them within the box, given in `shape.zw`, for a view with y up.
			var gx = x + g.x, gy = y + g.y;
			instances.set(Instances.RECT, i, gx, gy, g.width, g.height);
			instances.set(Instances.UV, i, g.atlasX / atlas.width, g.atlasY / atlas.height, (g.atlasX + g.atlasWidth) / atlas.width,
				(g.atlasY + g.atlasHeight) / atlas.height);
			if (g.kind == Coverage)
				tint(Instances.COLOR, i, color, alpha);
			else
				instances.set(Instances.COLOR, i, 1, 1, 1, alpha);
			// Every glyph turns about the box's center, so the text turns as one piece.
			instances.set(Instances.XFORM, i, c, s, (x + w / 2 - gx) / g.width, (y + h / 2 - gy) / g.height);
			instances.set(Instances.SHAPE, i, g.kind == Coverage ? 1 : 0, 0, y, h);
			textured(atlas, i);
		}
	}

	// Adds instance `i`, drawn with `texture`, to the last run, or starts a run when the texture, layer or plane differs.
	function textured(texture:Texture, i:Int):Void {
		var last = runs.length > 0 ? runs[runs.length - 1] : null;
		if (last == null || last.layer != layer || last.plane != plane || (last.texture != null && last.texture != texture))
			runs.push({texture: texture, layer: layer, plane: plane, start: i, count: 1});
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
		if (last == null || last.layer != layer || last.plane != plane)
			runs.push({texture: null, layer: layer, plane: plane, start: i, count: 1});
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
	var start:Int;
	var count:Int;
}
