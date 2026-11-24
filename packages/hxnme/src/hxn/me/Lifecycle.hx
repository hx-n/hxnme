package hxn.me;

/**
	`Lifecycle` holds the state of the app. It is a kernel resource. The host
	sets `suspended`, `visible` and `focused` from the platform. While the
	app is suspended, the loop runs no phase. Systems call `quit` to stop the
	app after the current frame.
**/
class Lifecycle {
	/** False after a system calls `quit`, or after the platform closes the app. **/
	public var running(default, null) = true;

	/** True while the platform keeps the app in the background, as on Android and iOS. **/
	public var suspended(default, null) = false;

	/** False while no part of the app can be seen, such as a hidden web page or a minimized window. **/
	public var visible(default, null) = true;

	/** True while the app has the keyboard focus. **/
	public var focused(default, null) = true;

	public function new() {}

	/** Stops the app after the current frame. **/
	public function quit():Void
		running = false;

	/** Sets the platform state. Only a host calls it. **/
	public function set(suspended:Bool, visible:Bool, focused:Bool):Void {
		this.suspended = suspended;
		this.visible = visible;
		this.focused = focused;
	}
}
