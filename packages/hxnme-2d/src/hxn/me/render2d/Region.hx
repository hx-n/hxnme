package hxn.me.render2d;

/**
	`Region` holds the corner and size of a named rectangle of an `Atlas`
	texture, and its optional nine-slice borders. `Draw.region`,
	`Draw.regionSlice` and `Sprites.addRegion` draw it.
**/
class Region {
	public final name:String;

	/** `texture` holds the atlas texture that the region is part of. **/
	public final texture:Texture;

	/** `x`, `y`, `width` and `height` give the region's corner and size in texture pixels, from the top left. **/
	public var x(default, null):Int;

	public var y(default, null):Int;
	public var width(default, null):Int;
	public var height(default, null):Int;

	/**
		`left`, `top`, `right` and `bottom` give the nine-slice borders in
		texture pixels. They are 0 for a region that is not a nine-slice.
	**/
	public var left(default, null):Int;

	public var top(default, null):Int;
	public var right(default, null):Int;
	public var bottom(default, null):Int;

	/**
		`pivotX` and `pivotY` give the point of the region that `Draw.region`,
		`Draw.shadowOf` and `Sprites.addRegion` place at their `x`, `y`, and
		that `angle` turns about. They are fractions of the region's width and
		height, from its top left in the image. The default is the center, 0.5
		and 0.5.
	**/
	public var pivotX(default, null):Float;

	public var pivotY(default, null):Float;

	/** `u0`, `v0`, `u1` and `v1` give the region's texture coordinates, from 0 to 1, with `v0` at its top. **/
	public var u0(default, null):Float;

	public var v0(default, null):Float;
	public var u1(default, null):Float;
	public var v1(default, null):Float;

	public function new(name:String, texture:Texture, x:Int, y:Int, width:Int, height:Int, left = 0, top = 0, right = 0, bottom = 0, pivotX = 0.5,
			pivotY = 0.5) {
		this.pivotX = pivotX;
		this.pivotY = pivotY;
		this.name = name;
		this.texture = texture;
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
		this.left = left;
		this.top = top;
		this.right = right;
		this.bottom = bottom;
		u0 = x / texture.width;
		v0 = y / texture.height;
		u1 = (x + width) / texture.width;
		v1 = (y + height) / texture.height;
	}

	// Counts the calls of `adopt`, so that `Sprites` knows when to write its regions again.
	@:allow(hxn.me.render2d) static var changes(default, null) = 0;

	// Gives this region the rectangle, the borders and the pivot of `by`, a region of the same texture.
	@:allow(hxn.me.render2d) function adopt(by:Region):Void {
		x = by.x;
		y = by.y;
		width = by.width;
		height = by.height;
		left = by.left;
		top = by.top;
		right = by.right;
		bottom = by.bottom;
		pivotX = by.pivotX;
		pivotY = by.pivotY;
		u0 = by.u0;
		v0 = by.v0;
		u1 = by.u1;
		v1 = by.v1;
		changes++;
	}
}
