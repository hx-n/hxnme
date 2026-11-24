package hxn.me.render2d;

import hxn.text.AtlasKind;
import hxn.text.Font;
import hxn.text.PreparedText;
import hxn.text.TextOptions;

/**
	`Text` is a string laid out in one font, for `Draw.text`. `Typesetter.text`
	makes it. The first time that it is drawn or measured, it lays itself out.
	After `set` changes the string, or after the scale or the atlases of the
	typesetter change, it lays itself out again. The app can therefore keep one
	`Text` for a label and change it in each frame.
**/
class Text {
	/** The string. Set it with `set`. **/
	public var value(default, null):String;

	final typesetter:Typesetter;
	final font:Font;
	final options:TextOptions;
	var prepared:Null<PreparedText>;
	var scale = 0.0;

	@:allow(hxn.me.render2d) function new(typesetter:Typesetter, font:Font, value:String, options:TextOptions) {
		this.typesetter = typesetter;
		this.font = font;
		this.value = value;
		this.options = options;
	}

	/** Changes the string. The text lays itself out again when it is next drawn or measured. **/
	public function set(value:String):Void {
		if (value != this.value) {
			this.value = value;
			prepared = null;
		}
	}

	/** The width of the laid-out text, in logical pixels. **/
	public var width(get, never):Float;

	function get_width():Float
		return layout().width;

	/** The height of the laid-out text, in logical pixels. **/
	public var height(get, never):Float;

	function get_height():Float
		return layout().height;

	/** Returns the text laid out for the typesetter's current scale and atlases. **/
	@:allow(hxn.me.render2d) function layout():PreparedText {
		if (prepared == null || scale != typesetter.scale || prepared.generation != typesetter.generation()) {
			scale = typesetter.scale;
			prepared = typesetter.prepare(font, value, options);
		}
		return prepared;
	}

	@:allow(hxn.me.render2d) inline function atlas(kind:AtlasKind):Null<Texture>
		return typesetter.atlas(kind);

	/**
		Adds an instance to `instances` for each glyph, with the corner of the
		text's box that has the smaller coordinates at `x`, `y`, and calls
		`added` with each atlas texture and instance. If `only` is not
		null, it adds only the glyphs of that atlas.
	**/
	@:allow(hxn.me.render2d) function write(instances:Instances, x:Float, y:Float, color:Int, alpha:Float, angle:Float, only:Null<AtlasKind>,
			added:(Texture, Int) -> Void):Void {
		var laid = layout();
		var w = laid.width, h = laid.height;
		var c = Math.cos(angle), s = Math.sin(angle);
		var r = ((color >> 16) & 0xFF) / 255, g = ((color >> 8) & 0xFF) / 255, b = (color & 0xFF) / 255;
		for (glyph in laid.glyphs) {
			if (only != null && glyph.kind != only)
				continue;
			var atlas = atlas(glyph.kind);
			if (atlas == null || glyph.width <= 0 || glyph.height <= 0)
				continue;
			var i = instances.add();
			// Glyph rects are laid out from the top of the box. The shader mirrors
			// them within the box, given in `shape.zw`, for a view with y up.
			var gx = x + glyph.x, gy = y + glyph.y;
			instances.set(Instances.RECT, i, gx, gy, glyph.width, glyph.height);
			instances.set(Instances.UV, i, glyph.atlasX / atlas.width, glyph.atlasY / atlas.height, (glyph.atlasX + glyph.atlasWidth) / atlas.width,
				(glyph.atlasY + glyph.atlasHeight) / atlas.height);
			if (glyph.kind == Coverage)
				instances.set(Instances.COLOR, i, r, g, b, alpha);
			else
				instances.set(Instances.COLOR, i, 1, 1, 1, alpha);
			// Every glyph turns about the box's center, so the text turns as one piece.
			instances.set(Instances.XFORM, i, c, s, (x + w / 2 - gx) / glyph.width, (y + h / 2 - gy) / glyph.height);
			instances.set(Instances.SHAPE, i, glyph.kind == Coverage ? 1 : 0, 0, y, h);
			added(atlas, i);
		}
	}
}
