# hxnme-input

Input for hxnme apps, in `hxn.me.input`. The plugin maps keys, mouse
buttons and gamepads to typed actions, and tracks the pointer of the mouse
or of a touch screen. It reads the events that the window plugin publishes,
so it requires [hxnme-window](../hxnme-window).

List both plugins in the app's `hxnme.toml`:

```toml
plugins = ["hxnme-window", "hxnme-input"]
```

## Actions

Each set of actions is an enum abstract over `Int`, with `@:actions`.
Metadata on each value binds it:

```haxe
@:actions
enum abstract Action(Int) {
	@:keys(Space) @:buttons(South)
	var Jump;

	@:keyAxis(KeyA, KeyD) @:axis(LeftX)
	var MoveX;

	@:mouse(Left)
	var Fire;

	@:shortcut(Control, KeyS) @:shortcut(Super, KeyS)
	var Save;
}
```

| Metadata | Binds the action to |
|---|---|
| `@:keys(...)` | Keys, by the names of `hxn.window.KeyCode`, such as `Space` and `KeyW`. |
| `@:mouse(...)` | Mouse buttons: `Left`, `Right`, `Middle`, `Back` or `Forward`. |
| `@:buttons(...)` | Buttons of the first gamepad, by position, with the names of `hxn.window.GamepadButton` such as `South`, or `Confirm` and `Cancel`. |
| `@:axis(...)` | Axes of the first gamepad, by the names of `hxn.window.GamepadAxis`, such as `LeftX`. |
| `@:keyAxis(negative, positive)` | Two keys that give -1 and 1. |
| `@:shortcut(...)` | Two or more keys held together. `Control`, `Shift`, `Alt` and `Super` are modifiers, which the window reports for either side. Each `@:shortcut` is one alternative. |

Systems take the actions as the resource `Input<Action>`:

```haxe
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.input.Input;

class Movement {
	@:system(Update)
	static function move(input:Res<Input<Action>>, player:ResMut<Player>) {
		if (input.pressed(Jump))
			player.jump();
		player.vx = input.value(MoveX) * player.speed;
	}
}
```

| Method | Returns |
|---|---|
| `pressed(action)` | True if the action went down in this frame, even if it came up again in the same frame. |
| `held(action)` | True while the action is down. |
| `released(action)` | True if the action came up in this frame. |
| `value(action)` | The value, from -1 to 1. Keys and buttons give 1 while they are down, and a gamepad axis gives its position. |

Each action is down while its value is at least 0.5 from 0. If more than one
binding is active, the value with the largest size wins. Keys of
`@:keyAxis` add up, so both keys down give 0. Shortcuts do not hide their
keys from other actions: while `Control` and `S` are down, an action bound
to `@:keys(KeyS)` is down too.

Keys match by position or by character, as `KeyboardEvent.code` and
`KeyboardEvent.key` do in a browser. `@:keys` and `@:keyAxis` match the key
in that place, so WASD stays in place on any keyboard layout. In a
`@:shortcut`, letters and digits match the key that types them, so
`@:shortcut(Control, KeyZ)` is the key marked Z on an AZERTY keyboard too.
Other keys of a shortcut, such as `Space`, match by position.

The bindings become a table at compile time, so the actions need no lookup
at run time. Names that are not a key, a button or an axis are compile errors at the
metadata, and so is a set without `@:actions`.

## Gamepads

hxn-window reports every supported gamepad with the same positional
buttons, the W3C standard layout that gilrs and the SDL controller database
map each pad to. So `@:buttons(South)` is the bottom face button on Xbox,
PlayStation, Nintendo and Steam pads alike, and an app writes no mapping of
its own.

| Family | Vendor | `South` | `East` | `West` | `North` |
|---|---|---|---|---|---|
| `Xbox` | 0x045E | A | B | X | Y |
| `PlayStation` | 0x054C | Cross | Circle | Square | Triangle |
| `Nintendo` | 0x057E | B | A | Y | X |
| `Steam` | 0x28DE | A | B | X | Y |
| `Generic` | other | South | East | West | North |

`devices.gamepadFamily` is the family of the connected pad, from the USB
vendor id that hxn-window reports. `Gamepads.label(family, button)` is the
label that a button carries on that family, for button prompts, and
`input.gamepadLabel(action)` is the label of the action's first gamepad
button on the connected pad:

```haxe
hint.text = 'Press ${input.gamepadLabel(Jump)} to jump'; // "A", "Cross" or "B"
```

`@:buttons(Confirm)` and `@:buttons(Cancel)` follow each family's
convention: `Confirm` is `East` on Nintendo pads, where A sits, and `South`
on the others, and `Cancel` is the other of the two. Menus bind these, and
gameplay binds positions.

## Devices and the pointer

The resource `Devices` holds the state of each key, each mouse button and
the first connected gamepad, for systems that read a key without an action:
`devices.key(KeyW)`, `devices.mouse(Right)`, `devices.gamepadAxis(LeftY)`,
`devices.gamepadPressed(South)`.
`keyPressed`, `keyReleased`, `mousePressed` and `mouseReleased` report what
went down or came up in the frame. `shift`, `control`, `alt` and `superKey`
are the modifiers that the window reports. When the window loses the focus,
the plugin releases every key and button.

hxn-window passes on winit's events, which report changes and never the
current state, as a browser does. So the plugin keeps the state of keys and
mouse buttons, and nothing more. The rest is winit's own: the modifiers
come from `ModifiersChanged`, the character of a key from its logical key,
and `pressed` and `released` from the state in each event. So a click
within one frame is not lost. The gamepad state is the snapshot that
`hxn.window.Gamepad.snapshot` copies once a frame.

The resource `Pointer` is the mouse cursor, or the primary touch on a touch
screen, which is the first finger down while no other is: `x` and `y` in
physical pixels of the window, and `down`, `pressed`, `released` and
`touches`, the number of fingers down. winit 0.30 reports the mouse and
touches as separate events, so the pointer joins them. For each finger, with
its phase, its force and its id as winit reports them, read the `Touch`
events in `Res<hxn.me.Events<hxn.window.Event>>`.

The plugin's system reads the events in `Begin`, after the window plugin
publishes them. Systems in `Fixed`, `Update` and `Render` read the state of
the current frame.

## Signals

Code that reacts to changes, such as a UI built on `hxn.Reactive`, can read
the input as `hxn.Signal` values:

| Call | Signal | Set in each frame in which |
|---|---|---|
| `input.signal(action)` | Whether the action is down. | The action goes down or comes up. |
| `pointer.signal()` | The `Pointer`. | The pointer moves, goes down or up, or a touch begins or ends. |
| `devices.signal()` | The `Devices`. | Keys, mouse buttons or gamepad values change, or a gamepad connects or disconnects. |

The signals of `Pointer` and `Devices` carry the same object in every
frame, so they carry the stream of input as it changes, and setting them
allocates nothing. Effects read the current fields of the value:

```haxe
@:system(Start)
static function watch(input:Res<Input<Action>>, devices:Res<Devices>) {
	var jump = input.signal(Jump);
	hxn.Reactive.effect(() -> label.text = jump.value ? "Jumping" : "");

	var keys = devices.signal();
	hxn.Reactive.effect(() -> {
		var d = keys.value;
		hint.visible = d.key(ControlLeft) || d.key(ControlRight);
	});
}
```

For keys held together, `@:shortcut` on an action is shorter, and players
can rebind it. The devices signal serves code that reads the keys
themselves.

The plugin creates each signal the first time that code asks for it. It
sets the signals in `Begin`, in one `hxn.Reactive.batch`, so that each
effect runs at most once a frame. Until code asks for a signal, the plugin
does no signal work. Systems that run each frame read `Input`, `Devices`
and `Pointer` directly instead.

## Checks

In `tests/input`, run `hxn check hl cpp cppia app.hxml --vm ash`. The check
opens a hidden window and posts key, mouse and cursor events to it. In
`tests`, `haxe action-errors.hxml` compiles wrong action sets and makes sure
that each one fails with its error.
