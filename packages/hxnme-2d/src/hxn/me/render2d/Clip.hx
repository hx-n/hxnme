package hxn.me.render2d;

/**
	`Clip` limits what shows to a rectangle with shaped corners, in the
	coordinates of the plane that the content lies on. Set `draw.clip` or
	`sprites.clip` to a clip, and only the parts of the content added next
	that are inside it show. The GPU tests each pixel against the clip, so a
	clip adds no data to the instances. Changes to a clip's fields apply from
	the next frame.
**/
class Clip {
	/** The x coordinate of the clip's corner with the smaller coordinates. **/
	public var x:Float;

	/** The y coordinate of the clip's corner with the smaller coordinates. **/
	public var y:Float;

	public var width:Float;
	public var height:Float;

	/** The radius of the clip's corners. **/
	public var radius:Float;

	/** The shape of the clip's corners. **/
	public var corner:CornerShape;

	public function new(x:Float, y:Float, width:Float, height:Float, radius = 0.0, corner:CornerShape = Round) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
		this.radius = radius;
		this.corner = corner;
	}
}
