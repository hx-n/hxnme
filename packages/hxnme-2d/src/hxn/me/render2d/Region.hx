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
	public final x:Int;

	public final y:Int;
	public final width:Int;
	public final height:Int;

	/**
		`left`, `top`, `right` and `bottom` give the nine-slice borders in
		texture pixels. They are 0 for a region that is not a nine-slice.
	**/
	public final left:Int;

	public final top:Int;
	public final right:Int;
	public final bottom:Int;

	/**
		`pivotX` and `pivotY` give the point of the region that `Draw.region`,
		`Draw.shadowOf` and `Sprites.addRegion` place at their `x`, `y`, and
		that `angle` turns about. They are fractions of the region's width and
		height, from its top left in the image. The default is the center, 0.5
		and 0.5.
	**/
	public final pivotX:Float;

	public final pivotY:Float;

	/** `u0`, `v0`, `u1` and `v1` give the region's texture coordinates, from 0 to 1, with `v0` at its top. **/
	public final u0:Float;

	public final v0:Float;
	public final u1:Float;
	public final v1:Float;

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
}
