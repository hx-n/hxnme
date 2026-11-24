package hxn.me;

/**
	`Display` describes the surface that the app draws to. It is a kernel
	resource. The host sets it before `Start`, and again when the size or the
	scale changes. If the app has no window, the values come from
	`display.width`, `display.height` and `display.scale` in `hxnme.toml`.
**/
class Display {
	/** The width in physical pixels. **/
	public var width(default, null):Int = Project.integer("display.width", 1280);

	/** The height in physical pixels. **/
	public var height(default, null):Int = Project.integer("display.height", 720);

	/** The physical pixels for each logical pixel. **/
	public var scale(default, null):Float = Project.number("display.scale", 1);

	/** The frames that the display shows in a second. The host sets it from the monitor, or from `display.refresh` in `hxnme.toml`. **/
	public var refresh(default, null):Float = Project.number("display.refresh", 60);

	/**
		Whether presenting a frame waits for the display's refresh. The plugin
		that presents frames sets it. While it is true and the window is
		visible, the host runs each frame as soon as the last one is presented,
		so the present paces the frames.
	**/
	public var vsync(default, null) = false;

	public function new() {}

	/** Sets the frames that the display shows in a second. Only a host calls it. **/
	public function setRefresh(rate:Float):Void
		refresh = rate;

	/** Sets whether presenting a frame waits for the display's refresh. Only the plugin that presents frames calls it. **/
	public function setVsync(on:Bool):Void
		vsync = on;

	/** Sets the size and the scale. Only a host calls it. **/
	public function set(width:Int, height:Int, scale:Float):Void {
		this.width = width;
		this.height = height;
		this.scale = scale;
	}
}
