---
name: hxnme-input
description: Read input in an hxnme app with the hxnme-input haxelib (package `hxn.me.input`), the input plugin of the hxn media engine, on HashLink, Ash, hxcpp and CPPIA. Use when an app binds keys, mouse buttons or gamepads to typed actions, reads the pointer or a touch, queries a key directly, or when changing the plugin itself.
---

# hxnme-input

## Setup

List the window and input plugins in the app's `hxnme.toml`:

```toml
plugins = ["hxnme-window", "hxnme-input"]
```

## Actions

Declare each set of actions as an enum abstract over `Int` with `@:actions`,
and bind each value with metadata:

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

The metadata are `@:keys` (names of `hxn.window.KeyCode`), `@:mouse` (`Left`,
`Right`, `Middle`, `Back`, `Forward`), `@:buttons` (names of
`hxn.window.GamepadButton`), `@:axis` (names of `hxn.window.GamepadAxis`),
`@:keyAxis(negative, positive)` and `@:shortcut(...)`. `@:shortcut` takes
two or more keys held together. In it, `Control`, `Shift`, `Alt` and
`Super` read the window's modifier state. `@:keys` and `@:keyAxis` match
keys by position (`KeyboardEvent.code`). In a shortcut, letters and digits
match the key that types them (`KeyboardEvent.key`), so the shortcut
follows the keyboard layout. Each `@:shortcut` is one alternative, and it
does not hide its keys from other actions. Number the values from 0 without
gaps, as an enum abstract does by default.

```haxe
@:system(Update)
static function move(input:Res<hxn.me.input.Input<Action>>, player:ResMut<Player>) {
	if (input.pressed(Jump))
		player.jump();
	player.vx = input.value(MoveX) * player.speed;
}
```

`Input<A>` has `pressed`, `held`, `released` and `value` (-1 to 1).
`pressed` and `released` come from the frame's events, so a tap within one
frame reports both. Each action is down while its value is at least 0.5
from 0. The value with the largest size wins, and the keys of `@:keyAxis`
add up. The bindings become a table at compile time. Wrong names and a set
without `@:actions` are compile errors.

## Gamepads

Bind gamepad buttons by position (`South`, `East`, `West`, `North`, ...).
hxn-window maps every supported pad to the W3C standard layout through gilrs
and the SDL controller database. One binding therefore covers Xbox,
PlayStation, Nintendo and Steam pads. Never bind a console label such as
`Triangle`.

- `devices.gamepadFamily`: `Xbox`, `PlayStation`, `Nintendo`, `Steam` or
  `Generic`, from the USB vendor id (`GamepadFamily.ofVendor`).
- `Gamepads.label(family, button)` and `input.gamepadLabel(action)`: the
  printed label for prompts, such as "A", "Cross" or "B" for `South`.
- `@:buttons(Confirm)` and `@:buttons(Cancel)`: `East` and `South` on
  Nintendo pads, `South` and `East` on the others. Use them for menus.

## Devices and the pointer

- `Res<hxn.me.input.Devices>`: `key(code)`, `keyPressed`, `keyReleased`,
  `mouse(button)`, `mousePressed`, `mouseReleased`, the modifiers `shift`,
  `control`, `alt` and `superKey`, and `gamepadButton(button)`,
  `gamepadAxis(axis)` and `gamepad` (connected) for the first gamepad, read
  from `Gamepad.snapshot` once a frame.
- `Res<hxn.me.input.Pointer>`: `x`, `y` (physical pixels), `down`,
  `pressed`, `released`, `touches`. It follows the mouse, or the primary
  touch, which is the first finger down while no other is.
- The `Touch` events in `Res<hxn.me.Events<hxn.window.Event>>` give each
  finger, with winit's `TouchPhase`, `TouchForce` and id. Do not recompute
  what winit reports. The plugin keeps only the state that winit's events
  leave out, which is the keys and buttons held.

The plugin reads window and gamepad events in `Begin`, after the window
plugin publishes them. Systems in `Fixed`, `Update` and `Render` therefore
see the current frame. When the window loses the focus, the plugin releases
every key.

## Signals

For code that reacts to changes, such as a UI on `hxn.Reactive`:

- `input.signal(action)`: a `Signal<Bool>`, set when the action goes down
  or comes up.
- `pointer.signal()`: a `Signal<Pointer>` that carries the pointer itself,
  set in each frame in which it moved, went down or up, or a touch changed.
- `devices.signal()`: a `Signal<Devices>` that carries the devices, set in
  each frame in which a key, a button or a gamepad value changed.

The signals of the pointer and the devices carry the same object every
frame, so setting them allocates nothing. Effects read the fields, for
example `keys.value.key(ControlLeft) && keys.value.key(KeyS)`. For keys held
together, use `@:shortcut` on an action instead. The plugin creates each
signal on first use. It sets the signals in `Begin` in one
`Reactive.batch`, so each effect runs at most once a frame. Systems read the
resources directly.

## Checks

```
cd tests/input && hxn check hl cpp cppia app.hxml --vm ash
cd tests && haxe action-errors.hxml
```

The input check posts events with `hxn.me.window.WindowPlugin.post` in a
`Begin` system that sets `before = hxn.me.window.WindowPlugin`. Follow the
[hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md) and the
[kernel skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme/SKILL.md).
