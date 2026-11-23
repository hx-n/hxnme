package hxn.me.input;

/**
	The input plugin. Its systems read the events of the window and the
	gamepads in `Begin`, after the window plugin publishes them, and update
	`Devices`, `Pointer` and each `Input<A>` of the app.
**/
@:plugin("hxnme-input", description = "Maps keys, mouse buttons, touches and gamepads to typed actions")
@:systems(InputSystems)
class InputPlugin {
	public function new() {}

	public function start():Void {}
}
