---
name: hxnme-window
description: Open the window of an hxnme app with the hxnme-window haxelib (package `hxn.me.window`), the window plugin of the hxn media engine, on HashLink, Ash, hxcpp and CPPIA. Use when an app needs a window, frames paced at the monitor's refresh, the window's size, scale, focus and visibility in the kernel resources, or when changing the plugin itself.
---

# hxnme-window

## Setup

List the plugin in the app's `hxnme.toml` and set the window's keys in the
`[window]` table:

```toml
plugins = ["hxnme-window"]

[window]
title = "Game"
width = 1280
height = 720
```

The keys are `title`, `width` and `height` in logical pixels, `resizable`,
`fullscreen`, `visible`, and `rate`. `rate` sets the frames in a second for
a platform that does not report the monitor's refresh rate.

```haxe
class Main {
	static function main()
		hxn.me.App.run(Movement, Drawing);
}
```

## Behavior

The plugin provides `hxn.me.Host`, so it paces the app's frames. When the
app runs, it opens the window. It runs a frame at each refresh of the
window's monitor, and sets `Display.refresh` to that refresh rate. While
`Display.vsync` is true and the window is visible, the present paces the
frames. The host then only keeps each frame from starting before nine
tenths of a period. In a web page, the window is the page's canvas. When
the app is compiled to wasm with Ash, it runs in a worker and the host waits
as it does natively. When it is compiled to wasm with hxcpp, `run` returns
and the browser runs each turn of the host. Between frames, the host reads
the window's events:

- `Display` gets the size in physical pixels and the scale. On Android and iOS,
  the window fills the screen, and `Display` also gets the safe area insets.
- `Lifecycle.focused` and `Lifecycle.visible` follow the window.
- `Lifecycle.suspended` follows the platform. The app runs no frame while it is suspended.
- When the user closes the window, the app stops after the current frame.

Systems read these as `Res<hxn.me.Display>` and `Res<hxn.me.Lifecycle>`.
The plugin's `publish` system also puts every window event in
`Res<hxn.me.Events<hxn.window.Event>>`, in `Begin`. Systems that read it in
`Begin` add `after = hxn.me.window.WindowPlugin`. `WindowPlugin.post(event)`
queues a synthetic event. Checks and input replay use it.
Other plugins get the window, a `hxn.window.Window`, from
`hxn.me.Plugins.hxnme_window.window`.

## Checks

```
cd tests/window && hxn check hl cpp cppia app.hxml --vm ash
```

The check opens a hidden window. Follow the
[hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md) and the
[kernel skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme/SKILL.md).
