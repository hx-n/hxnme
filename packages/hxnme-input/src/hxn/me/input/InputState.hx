package hxn.me.input;

/**
	`InputState` holds the state of one set of actions, behind `Input<A>`.
	Each binding is an integer: its kind times 65536, plus the code of the
	key, the button or the axis. For a shortcut, the code is its index in
	`shortcuts`, where each shortcut is a list of parts: physical keys,
	modifiers of the window's modifier state, and characters that held keys
	type. The shortcut is down while every part is. The input plugin updates
	every state in `Begin`.
**/
class InputState {
	public static inline final KEY = 1;
	public static inline final MOUSE = 2;
	public static inline final BUTTON = 3;
	public static inline final AXIS = 4;
	public static inline final KEY_NEGATIVE = 5;
	public static inline final KEY_POSITIVE = 6;
	public static inline final SHORTCUT = 7;

	// `CONFIRM` and `CANCEL` are the button codes of `@:buttons(Confirm)` and
	// `@:buttons(Cancel)`. Each stands for a different button on each gamepad
	// family.
	public static inline final CONFIRM = 100;
	public static inline final CANCEL = 101;

	// `all` lists each state of the app, so that the input plugin can update them.
	@:allow(hxn.me.input)
	static final all:Array<InputState> = [];

	// `watched` counts the signals that code asked for. While it is 0, no
	// signal work runs. It lives here, and not in InputSystems, because
	// `Input.create` loads this class in the macro context, which cannot load
	// hxn-window's natives.
	@:allow(hxn.me.input)
	static var watched = 0;

	// `never` is the equality test of a signal that carries a changing object.
	// It always returns false, so each `set` reaches the readers.
	@:allow(hxn.me.input)
	static function never<T>(a:T, b:T):Bool
		return false;

	final bindings:Array<Array<Int>>;
	final shortcuts:Array<Array<Int>>;
	final values:Array<Float>;
	final down:Array<Bool>;
	final before:Array<Bool>;
	final pressedNow:Array<Bool>;
	var family:GamepadFamily = Generic;
	final releasedNow:Array<Bool>;
	var signals:Null<Array<Null<hxn.Signal<Bool>>>>;

	public function new(bindings:Array<Array<Int>>, shortcuts:Array<Array<Int>>) {
		this.bindings = bindings;
		this.shortcuts = shortcuts;
		values = [for (_ in bindings) 0.0];
		down = [for (_ in bindings) false];
		before = [for (_ in bindings) false];
		pressedNow = [for (_ in bindings) false];
		releasedNow = [for (_ in bindings) false];
		all.push(this);
	}

	public inline function isPressed(action:Int):Bool
		return pressedNow[action];

	public inline function isHeld(action:Int):Bool
		return down[action];

	public inline function isReleased(action:Int):Bool
		return releasedNow[action];

	public inline function valueOf(action:Int):Float
		return values[action];

	public function signalOf(action:Int):hxn.Signal<Bool> {
		if (signals == null)
			signals = [for (_ in bindings) null];
		var signal = signals[action];
		if (signal == null) {
			signal = signals[action] = new hxn.Signal(down[action]);
			InputState.watched++;
		}
		return signal;
	}

	// Sets each signal that code asked for to whether its action is down.
	@:allow(hxn.me.input)
	function publish():Void {
		if (signals == null)
			return;
		for (action in 0...signals.length) {
			var signal = signals[action];
			if (signal != null)
				signal.set(down[action]);
		}
	}

	// Returns the positional button that `code` stands for on a gamepad of
	// `family`.
	static inline function button(code:Int, family:GamepadFamily):Int {
		return switch code {
			case CONFIRM: Gamepads.confirm(family);
			case CANCEL: Gamepads.cancel(family);
			case _: code;
		}
	}

	/**
		Returns the label of the first gamepad button bound to `action`, on the
		connected pad's family, or an empty string for an action that has no
		gamepad button. Prompts use it, such as "Press A to jump".
	**/
	public function labelOf(action:Int):String {
		for (binding in bindings[action])
			if (binding >> 16 == BUTTON)
				return Gamepads.label(family, button(binding & 0xFFFF, family));
		return "";
	}

	// Returns true while every part of the shortcut is down.
	static function held(parts:Array<Int>, devices:Devices):Bool {
		for (part in parts) {
			var value = part & 0xFFFF;
			var down = switch part >> 16 {
				case 0: devices.key(value);
				case 1: @:privateAccess devices.modifiers & value == value;
				case _: @:privateAccess devices.typing(value);
			}
			if (!down)
				return false;
		}
		return true;
	}

	// Computes each action from the devices. Keys bound as an axis add up, so
	// both keys down give 0. Then the contribution with the largest size wins.
	@:allow(hxn.me.input)
	function update(devices:Devices):Void {
		family = devices.gamepadFamily;
		for (action in 0...bindings.length) {
			var keyAxis = 0.0;
			var best = 0.0;
			// Keys and buttons that went down and up within the frame are not
			// down at its end, so their events count as well.
			var pressEvent = false;
			var releaseEvent = false;
			for (binding in bindings[action]) {
				var code = binding & 0xFFFF;
				switch binding >> 16 {
					case KEY:
						pressEvent = pressEvent || devices.keyPressed(code);
						releaseEvent = releaseEvent || devices.keyReleased(code);
					case MOUSE:
						pressEvent = pressEvent || @:privateAccess devices.pressedButtons[code];
						releaseEvent = releaseEvent || @:privateAccess devices.releasedButtons[code];
					case BUTTON:
						code = button(code, devices.gamepadFamily);
						pressEvent = pressEvent || devices.gamepadPressed(code);
						releaseEvent = releaseEvent || devices.gamepadReleased(code);
					case _:
				}
				var value = switch binding >> 16 {
					case KEY: devices.key(code) ? 1.0 : 0.0;
					case MOUSE: @:privateAccess devices.buttons[code] ? 1.0 : 0.0;
					case BUTTON: devices.gamepadButton(code);
					case AXIS: devices.gamepadAxis(code);
					case KEY_NEGATIVE:
						if (devices.key(code))
							keyAxis -= 1;
						0.0;
					case KEY_POSITIVE:
						if (devices.key(code))
							keyAxis += 1;
						0.0;
					case SHORTCUT: held(shortcuts[code], devices) ? 1.0 : 0.0;
					case _: 0.0;
				}
				if (Math.abs(value) > Math.abs(best))
					best = value;
			}
			if (Math.abs(keyAxis) > Math.abs(best))
				best = keyAxis;
			before[action] = down[action];
			values[action] = best;
			down[action] = Math.abs(best) >= 0.5;
			pressedNow[action] = (down[action] && !before[action]) || pressEvent;
			releasedNow[action] = (!down[action] && before[action]) || releaseEvent;
		}
	}
}
