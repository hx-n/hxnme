package hxn.me.input;

import hxn.window.GamepadButton;

/**
	`Gamepads` returns the labels of gamepad buttons for each family, and the
	buttons that confirm and cancel. Use the labels in prompts, such as
	"Press A to jump", and bind actions to positions, such as
	`@:buttons(South)`.
**/
class Gamepads {
	// Each array lists one family's labels for the buttons, in the order of
	// `hxn.window.GamepadButton`.
	static final XBOX = ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "View", "Menu", "LS", "RS", "Up", "Down", "Left", "Right", "Xbox"];
	static final PLAYSTATION = [
		"Cross", "Circle", "Square", "Triangle", "L1", "R1", "L2", "R2", "Create", "Options", "L3", "R3", "Up", "Down", "Left", "Right", "PS"
	];
	static final NINTENDO = ["B", "A", "Y", "X", "L", "R", "ZL", "ZR", "-", "+", "LS", "RS", "Up", "Down", "Left", "Right", "Home"];
	static final STEAM = ["A", "B", "X", "Y", "L1", "R1", "L2", "R2", "View", "Menu", "L3", "R3", "Up", "Down", "Left", "Right", "Steam"];
	static final GENERIC = [
		"South", "East", "West", "North", "Left Shoulder", "Right Shoulder", "Left Trigger", "Right Trigger", "Select", "Start", "Left Stick",
		"Right Stick", "Up", "Down", "Left", "Right", "Guide"
	];

	/** Returns the label that `button` carries on a gamepad of `family`. **/
	public static function label(family:GamepadFamily, button:GamepadButton):String {
		var labels = switch family {
			case Xbox: XBOX;
			case PlayStation: PLAYSTATION;
			case Nintendo: NINTENDO;
			case Steam: STEAM;
			case Generic: GENERIC;
		}
		var index:Int = button;
		return index >= 0 && index < labels.length ? labels[index] : "";
	}

	/**
		Returns the button that confirms on a gamepad of `family`. That is
		`East` on Nintendo pads, where A sits, and `South` on the others.
	**/
	public static function confirm(family:GamepadFamily):GamepadButton
		return family == Nintendo ? East : South;

	/** Returns the button that cancels on a gamepad of `family`, which is the other one of `confirm`. **/
	public static function cancel(family:GamepadFamily):GamepadButton
		return family == Nintendo ? South : East;
}
