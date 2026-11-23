package hxn.me;

/**
	The surface that the app draws to, a kernel resource. The host sets it
	before `Start`, and again when the size or the scale changes. If the app
	has no window, the values come from `display.width`, `display.height`
	and `display.scale` in `hxnme.toml`.
**/
class Display {
	/** The width in physical pixels. **/
	public var width(default, null):Int = Project.integer("display.width", 1280);

	/** The height in physical pixels. **/
	public var height(default, null):Int = Project.integer("display.height", 720);

	/** The physical pixels for each logical pixel. **/
	public var scale(default, null):Float = Project.number("display.scale", 1);

	public function new() {}

	/** Sets the size and the scale. Only a host calls it. **/
	public function set(width:Int, height:Int, scale:Float):Void {
		this.width = width;
		this.height = height;
		this.scale = scale;
	}
}
