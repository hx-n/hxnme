package hxn.me.input;

/**
	`GamepadFamily` groups gamepads by the USB vendor id that hxn-window
	reports. The family decides the labels that the gamepad's buttons carry,
	and which button confirms and which cancels. Bindings stay positional, so
	`South` is the bottom face button on every family.
**/
enum abstract GamepadFamily(Int) {
	/** Pads of other vendors, and pads whose vendor the platform does not report. **/
	var Generic;

	/** Microsoft Xbox controllers. **/
	var Xbox;

	/** Sony DualShock and DualSense controllers. **/
	var PlayStation;

	/** Nintendo Switch Pro controllers and Joy-Cons. **/
	var Nintendo;

	/** Valve Steam controllers and the Steam Deck. **/
	var Steam;

	/** Returns the family of the vendor id `vendor`, as hxn-window's `Gamepad.vendorId` reports it. **/
	public static function ofVendor(vendor:Int):GamepadFamily {
		return switch vendor {
			case 0x045E: Xbox;
			case 0x054C: PlayStation;
			case 0x057E: Nintendo;
			case 0x28DE: Steam;
			case _: Generic;
		}
	}
}
