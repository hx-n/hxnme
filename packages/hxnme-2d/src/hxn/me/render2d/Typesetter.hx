package hxn.me.render2d;

import hxn.text.AtlasKind;
import hxn.text.AtlasUpdate;
import hxn.text.Font;
import hxn.text.PreparedText;
import hxn.text.TextEngine;
import hxn.text.TextErrorCode;
import hxn.text.TextException;
import hxn.text.TextOptions;

/**
	`Typesetter` lays out text with hxn-text and keeps the glyph atlases. The
	coverage atlas holds one byte for each pixel of plain glyphs. The color
	atlas holds RGBA pixels for color glyphs, such as emoji. `text` returns a
	`Text` for `Draw.text`. Glyphs are rasterized at the display's scale, so
	they cover whole device pixels through a camera that shows one world unit
	for each logical pixel.
**/
class Typesetter {
	/** The number of device pixels for each logical pixel, at which glyphs are rasterized. The plugin sets it from `Display` in each frame. **/
	public var scale(default, null) = 1.0;

	var engine:Null<TextEngine>;
	final coverage = new Atlas(Coverage);
	final color = new Atlas(Color);

	// Atlas textures that a larger atlas replaced in this frame. Draws earlier in the frame still use them.
	final retired:Array<Texture> = [];

	public function new() {}

	/**
		Returns `value` laid out in `font` with `options`, for example `{size:
		24}`, for `Draw.text`. After `set` changes the string, or after the
		scale or the atlases change, the text lays itself out again.
	**/
	public function text(font:Font, value:String, ?options:TextOptions):Text
		return new Text(this, font, value, options != null ? options : {size: 16});

	/**
		Lays out `value` and brings the atlas textures up to date with the
		glyphs that it needs. If an atlas is full, the typesetter clears both
		atlases and lays the text out again.
	**/
	@:allow(hxn.me.render2d) function prepare(font:Font, value:String, options:TextOptions):PreparedText {
		var prepared = try layout(font, value, options) catch (e:TextException) {
			if (e.error.code != TextErrorCode.AtlasFull)
				throw e;
			engine.clear();
			// Draws earlier in this frame still read the old textures, so the cleared atlases start new ones.
			restart(coverage);
			restart(color);
			layout(font, value, options);
		}
		pull(coverage);
		pull(color);
		return prepared;
	}

	/** Returns the atlas texture for glyphs of `kind`. **/
	@:allow(hxn.me.render2d) inline function atlas(kind:AtlasKind):Null<Texture>
		return kind == Coverage ? coverage.texture : color.texture;

	/** Returns the generation of the engine's atlas coordinates. **/
	@:allow(hxn.me.render2d) function generation():UInt
		return engine == null ? 0 : engine.generation();

	/** Sets the scale for this frame, and releases the atlas textures that the last frame replaced. **/
	@:allow(hxn.me.render2d) function begin(scale:Float):Void {
		this.scale = scale;
		for (t in retired)
			t.close();
		retired.resize(0);
	}

	function layout(font:Font, value:String, options:TextOptions):PreparedText {
		if (engine == null)
			engine = new TextEngine();
		var scaled:TextOptions = {
			size: options.size,
			maxWidth: options.maxWidth,
			lineHeight: options.lineHeight,
			letterSpacing: options.letterSpacing,
			alignment: options.alignment,
			wrap: options.wrap,
			scale: options.scale != null ? options.scale : scale,
			subpixel: options.subpixel
		};
		return engine.prepare(font, value, scaled);
	}

	function restart(atlas:Atlas):Void {
		if (atlas.texture != null)
			retired.push(atlas.texture);
		atlas.texture = null;
		atlas.revision = 0;
	}

	// Copies the atlas's changes since the last pull into its texture, or makes a new texture if its size changed.
	function pull(atlas:Atlas):Void {
		var update:AtlasUpdate = engine.atlas(atlas.kind, atlas.revision);
		atlas.revision = update.revision;
		if (update.pixels == null || update.pixels.length == 0 || update.width == 0 || update.height == 0)
			return;
		var current = atlas.texture;
		var resized = current == null || current.width != update.width || current.height != update.height;
		if (resized && !(update.full && update.patchWidth == update.width && update.patchHeight == update.height)) {
			// Partial patches cannot fill a new texture, so ask for the whole atlas.
			update = engine.atlas(atlas.kind, 0);
			atlas.revision = update.revision;
		}
		if (resized) {
			if (current != null)
				retired.push(current);
			atlas.texture = atlas.kind == Coverage ? Texture.coverage(update.width, update.height,
				update.pixels) : new Texture(update.width, update.height, update.pixels);
		} else
			current.write(update.x, update.y, update.patchWidth, update.patchHeight, update.pixels, update.stride);
	}
}

/** Each atlas holds its texture and the last revision copied into it. **/
private class Atlas {
	public final kind:AtlasKind;
	public var revision:UInt = 0;
	public var texture:Null<Texture>;

	public function new(kind:AtlasKind)
		this.kind = kind;
}
