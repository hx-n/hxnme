package hxn.me.render2d;

/**
	`Shadow` sets how a region casts its shadow, for `Draw.region` and
	`Sprites.addRegion`. The shadow is the region's silhouette, moved by
	`offsetX`, `offsetY` and blurred by `blur`, in `color` and `alpha`.
	`squash` scales its height about the pivot, such as 0.4 for a shadow on
	the ground. Make one for each style and keep it, so no frame allocates
	one.
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
