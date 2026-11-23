package hxn.me.input;

/**
	The pointer, as a resource: the mouse cursor, or the primary touch on a
	touch screen, which is the first finger down while no other is. The
	position is in physical pixels of the window. The input plugin updates
	it in `Begin`. winit 0.30, under hxn-window, reports the mouse and touches
	as separate events, so the pointer joins them. Each touch, with its phase,
	force and id as winit reports them, is in `Events<hxn.window.Event>`.
**/
class Pointer {
	/** The horizontal position. **/
	public var x(default, null) = 0.0;

	/** The vertical position, from the top. **/
	public var y(default, null) = 0.0;

	/** True while the left mouse button or a touch is down. **/
	public var down(default, null) = false;

	/** True if the pointer went down in this frame, even if it came up again. **/
	public var pressed(default, null) = false;

	/** True if the pointer came up in this frame. **/
	public var released(default, null) = false;

	/** The number of touches on the screen. **/
	public var touches(default, null) = 0;

	// The id of the primary touch, while `pressedByTouch` is true.
	var primary:haxe.Int64 = 0;
	var pressedByTouch = false;

	var changed = false;
	var stream:Null<hxn.Signal<Pointer>>;

	public function new() {}

	/**
		Returns a signal that carries this pointer, for code that reacts to
		changes, such as a UI. The plugin sets it in `Begin` of each frame in
		which the pointer moved, went down or up, or a touch began or ended.
		The value is always this object, so setting it allocates nothing, and
		effects read the fields of the value. The signal is created the first
		time it is asked for.
	**/
	public function signal():hxn.Signal<Pointer> {
		if (stream == null) {
			stream = new hxn.Signal(this, InputState.never);
			InputState.watched++;
		}
		return stream;
	}

	@:allow(hxn.me.input)
	function publish():Void
		if (stream != null && changed)
			stream.set(this);

	@:allow(hxn.me.input)
	function begin():Void {
		pressed = false;
		released = false;
		changed = false;
	}

	@:allow(hxn.me.input)
	function move(x:Float, y:Float):Void {
		if (x == this.x && y == this.y)
			return;
		this.x = x;
		this.y = y;
		changed = true;
	}

	@:allow(hxn.me.input)
	function press(down:Bool):Void {
		if (down == this.down)
			return;
		this.down = down;
		if (down)
			pressed = true;
		else
			released = true;
		changed = true;
	}

	// Applies one touch event: the primary touch moves and presses the
	// pointer, and every touch counts in `touches`.
	@:allow(hxn.me.input)
	function touched(phase:hxn.window.TouchPhase, x:Float, y:Float, id:haxe.Int64):Void {
		switch phase {
			case Started:
				touches++;
				changed = true;
				if (!pressedByTouch) {
					pressedByTouch = true;
					primary = id;
					move(x, y);
					press(true);
				}
			case Moved:
				if (pressedByTouch && primary == id)
					move(x, y);
			case Ended | Cancelled:
				touches = touches > 0 ? touches - 1 : 0;
				changed = true;
				if (pressedByTouch && primary == id) {
					pressedByTouch = false;
					move(x, y);
					press(false);
				}
		}
	}
}
