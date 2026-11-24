package hxn.me.input;

import hxn.window.GamepadAxis;
import hxn.window.GamepadButton;
import hxn.window.KeyCode;
import hxn.window.MouseButton;

/**
	`Devices` holds the state of the keyboard, the mouse buttons and the
	first connected gamepad, as a resource. The input plugin updates it in
	`Begin`. Systems read it to query a key or a button directly, without an
	action.

	The window reports keys and mouse buttons only as events, so the plugin
	keeps their state here. The gamepad state is the snapshot that
	`hxn.window.Gamepad.snapshot` copies each frame: 17 button values, 4 axes,
	a mask and a change sequence.
**/
class Devices {
	final keys:Array<Bool> = [for (_ in 0...256) false];
	// `characters` holds the character that each held key typed when it went
	// down, or 0.
	final characters:Array<Int> = [for (_ in 0...256) 0];
	final buttons:Array<Bool> = [for (_ in 0...8) false];
	// These arrays mark the keys and buttons that went down or came up in
	// this frame.
	final pressedKeys:Array<Bool> = [for (_ in 0...256) false];
	final releasedKeys:Array<Bool> = [for (_ in 0...256) false];
	final pressedButtons:Array<Bool> = [for (_ in 0...8) false];
	final releasedButtons:Array<Bool> = [for (_ in 0...8) false];
	// `modifiers` holds the modifiers that the window reports, as bits: 1 is
	// Shift, 2 Control, 4 Alt and 8 Super.
	var modifiers = 0;
	@:allow(hxn.me.input)
	final pad = haxe.io.Bytes.alloc(176);
	var connected = false;
	var sequence = -1;
	// These arrays mark the gamepad buttons that went down or came up in this
	// frame, from the events that `drain` reads.
	final padPressed:Array<Bool> = [for (_ in 0...17) false];
	final padReleased:Array<Bool> = [for (_ in 0...17) false];

	/** The family of the connected gamepad, or `Generic` while none is connected. **/
	public var gamepadFamily(default, null):GamepadFamily = Generic;
	var changed = false;
	var stream:Null<hxn.Signal<Devices>>;

	public function new() {}

	/**
		Returns a signal that carries these devices, for code that reacts to
		changes, such as a UI. The plugin sets it in `Begin` of each frame in
		which a key, a mouse button or a gamepad value changed, or a gamepad
		connected or disconnected. The value is always this object, so setting
		it allocates nothing, and effects read it, for example
		`devices.key(ControlLeft) && devices.key(KeyS)`. This method creates
		the signal on its first call.
	**/
	public function signal():hxn.Signal<Devices> {
		if (stream == null) {
			stream = new hxn.Signal(this, InputState.never);
			InputState.watched++;
		}
		return stream;
	}

	@:allow(hxn.me.input)
	function begin():Void {
		changed = false;
		for (i in 0...pressedKeys.length) {
			pressedKeys[i] = false;
			releasedKeys[i] = false;
		}
		for (i in 0...pressedButtons.length) {
			pressedButtons[i] = false;
			releasedButtons[i] = false;
		}
		for (i in 0...padPressed.length) {
			padPressed[i] = false;
			padReleased[i] = false;
		}
	}

	@:allow(hxn.me.input)
	function publish():Void
		if (stream != null && changed)
			stream.set(this);

	/** Returns true while `code` is down. **/
	public inline function key(code:KeyCode):Bool
		return keys[(code : Int)];

	/** True while either Shift key is down, as the window reports it. **/
	public var shift(get, never):Bool;

	/** True while either Control key is down, as the window reports it. **/
	public var control(get, never):Bool;

	/** True while either Alt or Option key is down, as the window reports it. **/
	public var alt(get, never):Bool;

	/** True while either Super, Command or Windows key is down, as the window reports it. **/
	public var superKey(get, never):Bool;

	inline function get_shift():Bool
		return modifiers & 1 != 0;

	inline function get_control():Bool
		return modifiers & 2 != 0;

	inline function get_alt():Bool
		return modifiers & 4 != 0;

	inline function get_superKey():Bool
		return modifiers & 8 != 0;

	// Returns true while a held key is down that typed `character` when it
	// went down.
	function typing(character:Int):Bool {
		for (typed in characters)
			if (typed == character)
				return true;
		return false;
	}

	/** Returns true while the mouse button `button` is down. **/
	public function mouse(button:MouseButton):Bool
		return buttons[mouseIndex(button)];

	/** Returns true if `code` went down in this frame, even if it came up again. **/
	public inline function keyPressed(code:KeyCode):Bool
		return pressedKeys[(code : Int)];

	/** Returns true if `code` came up in this frame. **/
	public inline function keyReleased(code:KeyCode):Bool
		return releasedKeys[(code : Int)];

	/** Returns true if `button` went down in this frame, even if it came up again. **/
	public function mousePressed(button:MouseButton):Bool
		return pressedButtons[mouseIndex(button)];

	/** Returns true if `button` came up in this frame. **/
	public function mouseReleased(button:MouseButton):Bool
		return releasedButtons[mouseIndex(button)];

	/** Returns the value of `button` on the first gamepad, from 0 to 1. **/
	public inline function gamepadButton(button:GamepadButton):Float
		return pad.getDouble((button : Int) * 8);

	/** Returns the value of `axis` on the first gamepad, from -1 to 1. **/
	public inline function gamepadAxis(axis:GamepadAxis):Float
		return pad.getDouble(136 + (axis : Int) * 8);

	/** True while a gamepad is connected. **/
	public var gamepad(get, never):Bool;

	inline function get_gamepad():Bool
		return connected;

	@:allow(hxn.me.input)
	static function mouseIndex(button:MouseButton):Int {
		return switch button {
			case Left: 0;
			case Right: 1;
			case Middle: 2;
			case Back: 3;
			case Forward: 4;
			case Other(_): 5;
		}
	}

	@:allow(hxn.me.input)
	function setKey(code:Int, down:Bool, character:Int = 0):Void
		if (code >= 0 && code < keys.length && keys[code] != down) {
			keys[code] = down;
			characters[code] = down ? character : 0;
			(down ? pressedKeys : releasedKeys)[code] = true;
			changed = true;
		}

	@:allow(hxn.me.input)
	function setModifiers(mask:Int):Void
		if (mask != modifiers) {
			modifiers = mask;
			changed = true;
		}

	@:allow(hxn.me.input)
	function setMouse(index:Int, down:Bool):Void
		if (buttons[index] != down) {
			buttons[index] = down;
			(down ? pressedButtons : releasedButtons)[index] = true;
			changed = true;
		}

	// Releases every key and button, for a window that loses the focus.
	@:allow(hxn.me.input)
	function releaseAll():Void {
		for (i in 0...keys.length)
			setKey(i, false);
		for (i in 0...buttons.length)
			setMouse(i, false);
		setModifiers(0);
	}

	// Records that the first gamepad connected or disconnected. After a
	// disconnect, the pad state reads as zero.
	@:allow(hxn.me.input)
	function connect(on:Bool, family:GamepadFamily):Void {
		if (on == connected)
			return;
		connected = on;
		gamepadFamily = on ? family : Generic;
		changed = true;
		if (!on) {
			pad.fill(0, pad.length, 0);
			sequence = -1;
		}
	}

	@:allow(hxn.me.input)
	function padEdge(button:Int, pressed:Bool):Void
		if (button >= 0 && button < padPressed.length)
			(pressed ? padPressed : padReleased)[button] = true;

	/** Returns true if the gamepad's `button` went down in this frame, even if it came up again. **/
	public inline function gamepadPressed(button:GamepadButton):Bool
		return padPressed[(button : Int)];

	/** Returns true if the gamepad's `button` came up in this frame. **/
	public inline function gamepadReleased(button:GamepadButton):Bool
		return padReleased[(button : Int)];

	// Records the change sequence of the snapshot that `pad` now holds.
	@:allow(hxn.me.input)
	function snapshotted():Void {
		var next = pad.getInt32(172);
		if (next != sequence) {
			sequence = next;
			changed = true;
		}
	}
}
