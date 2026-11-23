import hxn.me.Lifecycle;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;
import hxn.me.input.Devices;
import hxn.me.input.Input;
import hxn.me.input.Pointer;
import hxn.me.window.WindowPlugin;
import hxn.window.Event;
import hxn.window.KeyCode;
import hxn.window.MouseElementState;

/**
	Posts window events before the window plugin publishes them, and prints
	the actions and the pointer in each frame. Control comes from the
	window's modifier state. In frame 4, the key in the place of W types "Z"
	with Shift held, and "z" without it, as on an AZERTY keyboard, and the left button goes down and up within the
	frame. In frame 5, two touches begin and the second moves: the pointer
	follows the first. The effects that `watch` makes print each change of the signal of
	`Jump`, and each frame in which the pointer or the devices changed.
**/
class Script {
	static var frame = 0;

	@:system(Start, description = "Prints the changes that the signals carry")
	static function watch(input:Res<Input<Action>>, pointer:Res<Pointer>, devices:Res<Devices>) {
		var jump = input.signal(Jump);
		hxn.Reactive.effect(() -> Sys.println('signal: jump ${jump.value ? "down" : "up"}'));
		var cursor = pointer.signal();
		hxn.Reactive.effect(() -> {
			var p = cursor.value;
			Sys.println('signal: pointer ${p.x} ${p.y} ${p.down ? "down" : "up"}');
		});
		var keys = devices.signal();
		hxn.Reactive.effect(() -> {
			var d = keys.value;
			Sys.println('signal: control and S ${d.control && d.key(KeyS) ? "down" : "up"}');
		});
	}

	@:system(Begin, before = hxn.me.window.WindowPlugin, description = "Posts the events of the next frame")
	static function post() {
		frame++;
		switch frame {
			case 1:
				WindowPlugin.post(key(Space, Pressed));
				WindowPlugin.post(key(KeyD, Pressed, "d"));
				WindowPlugin.post(CursorMoved(40, 30, 0));
				WindowPlugin.post(MouseInput(Pressed, Left, 0));
			case 2:
				WindowPlugin.post(ModifiersChanged(State(false, true, false, false, Unknown, Unknown, Pressed, Unknown, Unknown, Unknown, Unknown, Unknown)));
				WindowPlugin.post(key(KeyS, Pressed, "s"));
			case 3:
				WindowPlugin.post(key(KeyS, Released, "s"));
				WindowPlugin.post(key(Space, Released));
				WindowPlugin.post(key(KeyD, Released, "d"));
				WindowPlugin.post(key(KeyA, Pressed, "a"));
				WindowPlugin.post(MouseInput(Released, Left, 0));
			case 4:
				WindowPlugin.post(key(KeyD, Pressed, "d"));
				WindowPlugin.post(key(KeyW, Pressed, "Z", "z"));
				WindowPlugin.post(MouseInput(Pressed, Left, 0));
				WindowPlugin.post(MouseInput(Released, Left, 0));
			case 5:
				WindowPlugin.post(Touch(0, Started, 100, 80, None, 1));
				WindowPlugin.post(Touch(0, Started, 200, 90, Normalized(0.5), 2));
				WindowPlugin.post(Touch(0, Moved, 210, 95, Normalized(0.6), 2));
			case _:
		}
	}

	@:system(Update, description = "Prints the actions and the pointer")
	static function report(input:Res<Input<Action>>, pointer:Res<Pointer>, time:Res<Time>, lifecycle:ResMut<Lifecycle>) {
		Sys.println('frame ${time.frame}: jump ${state(input.pressed(Jump), input.held(Jump), input.released(Jump))}, '
			+ 'move ${input.value(MoveX)}, fire ${state(input.pressed(Fire), input.held(Fire), input.released(Fire))}, '
			+ 'pointer ${pointer.x} ${pointer.y} ${pointer.down ? "down" : "up"}${pointer.pressed ? " pressed" : ""}${pointer.released ? " released" : ""} touches ${pointer.touches}, '
			+ 'save ${state(input.pressed(Save), input.held(Save), input.released(Save))}, '
			+ 'undo ${state(input.pressed(Undo), input.held(Undo), input.released(Undo))}');
		if (time.frame == 5)
			lifecycle.quit();
	}

	// A key event. `plain` is the key without modifiers, which some
	// platforms report, as winit's `key_without_modifiers`.
	static function key(code:KeyCode, state:MouseElementState, text = "", plain = ""):Event {
		var supplement:hxn.window.KeySupplement = plain == "" ? Unavailable : Supplement(Character(plain), Some(text));
		return KeyboardInput(0, Input(Code(code), Character(text), text == "" ? None : Some(text), Standard, state, false, supplement), false);
	}

	static function state(pressed:Bool, held:Bool, released:Bool):String
		return pressed && released ? "tapped" : pressed ? "pressed" : released ? "released" : held ? "held" : "up";
}
