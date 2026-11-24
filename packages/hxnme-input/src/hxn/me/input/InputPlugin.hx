package hxn.me.input;

/**
	`InputPlugin` updates `Devices`, `Pointer` and each `Input<A>` of the app
	from the events of the window and the gamepads. Its systems read the
	events in `Begin`, after the window plugin publishes them.
**/
@:plugin("hxnme-input", description = "Maps keys, mouse buttons, touches and gamepads to typed actions")
@:systems(InputSystems)
class InputPlugin {
	public function new() {}

	public function start():Void {}
}
