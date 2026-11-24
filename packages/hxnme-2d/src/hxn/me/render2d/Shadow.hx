package hxn.me.render2d;

/**
	`Shadow` is how a region casts its shadow, for `Draw.region` and
	`Sprites.addRegion`: the region's silhouette, moved by `offsetX`,
	`offsetY`, blurred by `blur`, in `color` and `alpha`, with its height
	scaled about the pivot by `squash`, such as 0.4 for a shadow on the
	ground. Make one for each style and keep it, so no frame allocates one.
**/
class Shadow {
	public var offsetX:Float;
	public var offsetY:Float;
	public var blur:Float;
	public var color:Int;
	public var alpha:Float;
	public var squash:Float;

	public function new(offsetX = 0.0, offsetY = 0.0, blur = 4.0, color = 0x000000, alpha = 0.5, squash = 1.0) {
		this.offsetX = offsetX;
		this.offsetY = offsetY;
		this.blur = blur;
		this.color = color;
		this.alpha = alpha;
		this.squash = squash;
	}
}
