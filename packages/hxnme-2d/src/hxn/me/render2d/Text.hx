package hxn.me.render2d;

import hxn.text.Font;
import hxn.text.PreparedText;
import hxn.text.TextOptions;

/**
	`Text` is a string laid out in one font for `Draw.text`. `Typesetter.text`
	makes it. It lays itself out when it is first drawn, and again after `set`
	changes its string or the typesetter's scale or atlases change, so the
	app can keep one `Text` for a label and change it each frame.
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

	@:allow(hxn.me.render2d) inline function atlas(kind:hxn.text.AtlasKind):Null<Texture>
		return typesetter.atlas(kind);
}
