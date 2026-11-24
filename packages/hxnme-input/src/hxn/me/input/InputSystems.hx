package hxn.me.input;

import hxn.me.Events;
import hxn.me.ResMut;
import hxn.me.Res;
import hxn.window.Event;
import hxn.window.Gamepad;
import hxn.window.KeyEvent;
import hxn.window.MouseElementState;
import hxn.window.PhysicalKey;

class InputSystems {
	// `publish` sets the signals from these resources, in one batch.
	static var devices:Null<Devices>;
	static var pointer:Null<Pointer>;
	static final publishAll:() -> Void = publish;

	@:system(Begin, after = hxn.me.window.WindowPlugin, description = "Reads window and gamepad events into the devices, the pointer and each action set")
	static function read(events:Res<Events<Event>>, devices:ResMut<Devices>, pointer:ResMut<Pointer>) {
		pointer.begin();
		devices.begin();
		for (event in events)
			switch event {
				case KeyboardInput(_, Input(Code(code), logical, _, _, state, _, supplement), _):
					devices.setKey(code, state == Pressed, character(switch supplement {
						case Supplement(plain, _): plain;
						case Unavailable: logical;
					}));
				case ModifiersChanged(State(shift, control, alt, superKey, _, _, _, _, _, _, _, _)):
					devices.setModifiers((shift ? 1 : 0) | (control ? 2 : 0) | (alt ? 4 : 0) | (superKey ? 8 : 0));
				case MouseInput(state, button, _):
					var index = Devices.mouseIndex(button);
					devices.setMouse(index, state == Pressed);
					if (index == 0)
						pointer.press(state == Pressed);
				case CursorMoved(x, y, _):
					pointer.move(x, y);
				case Touch(_, phase, x, y, _, id):
					pointer.touched(phase, x, y, id);
				case Focused(false):
					// winit sends synthetic releases on Windows, Linux and the web,
					// and none on macOS, so the plugin releases every key and button
					// here on every platform.
					devices.releaseAll();
					pointer.press(false);
				case _:
			}
		readGamepads(devices);
		for (state in InputState.all)
			state.update(devices);
		if (InputState.watched > 0) {
			InputSystems.devices = devices;
			InputSystems.pointer = pointer;
			hxn.Reactive.batch(publishAll);
		}
	}

	// Sets every signal that code asked for, so that effects rerun once.
	static function publish():Void {
		devices.publish();
		pointer.publish();
		for (state in InputState.all)
			state.publish();
	}

	// `pad` is the first connected gamepad. Its state comes from `snapshot`,
	// and its connections come from `drain`, which reads events without
	// making objects.
	static var pad:Null<Gamepad>;
	static var padId = -1;
	static final records = haxe.io.Bytes.alloc(32 * 32);

	// Returns the character of a key, or 0 for a key that does not type one
	// character. It lowercases A to Z.
	static function character(key:hxn.window.Key):Int {
		return switch key {
			case Character(text) if (text.length == 1):
				var c = text.charCodeAt(0);
				c >= "A".code && c <= "Z".code ? c + 32 : c;
			case _: 0;
		}
	}

	static function readGamepads(devices:Devices) {
		if (!Gamepad.available())
			return;
		while (true) {
			var count = Gamepad.drain(records);
			for (i in 0...count) {
				var kind = records.getInt32(i * 32);
				var id = records.getInt32(i * 32 + 4);
				if (kind == CONNECTED && pad == null) {
					pad = Gamepad.fromId(id);
					padId = id;
				} else if (kind == BUTTON && id == padId) {
					devices.padEdge(records.getInt32(i * 32 + 8), records.getInt32(i * 32 + 12) != 0);
				} else if (kind == DISCONNECTED && id == padId) {
					pad.close();
					pad = null;
					padId = -1;
				}
			}
			if (count < 32)
				break;
		}
		if (pad == null && Gamepad.count() > 0) {
			pad = Gamepad.at(0);
			padId = pad.deviceId();
		}
		devices.connect(pad != null, pad == null ? Generic : GamepadFamily.ofVendor(pad.vendorId()));
		if (pad != null && pad.snapshot(devices.pad))
			devices.snapshotted();
	}

	// These constants are the kinds of `Gamepad.drain` records, in the order
	// of `GamepadEvent`.
	static inline final CONNECTED = 1;
	static inline final DISCONNECTED = 2;
	static inline final BUTTON = 3;
}
