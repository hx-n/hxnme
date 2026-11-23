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

The keys are `title`, `width`, `height` (logical pixels), `resizable`,
`fullscreen`, `visible`, and `rate`, the frames in a second if the
platform does not report the monitor's refresh rate.

```haxe
class Main {
	static function main()
		hxn.me.App.run(Movement, Drawing);
}
```

## Behavior

The plugin provides `hxn.me.Host`, so it paces the app's frames. It opens
the window when the app runs and runs a frame at each refresh of the
window's monitor. Between frames it reads the window's events:

- `Display` gets the size in physical pixels and the scale.
- `Lifecycle.focused` and `Lifecycle.visible` follow the window.
- `Lifecycle.suspended` follows the platform. The app runs no frame while it is suspended.
- Closing the window stops the app after the current frame.

Systems read these as `Res<hxn.me.Display>` and `Res<hxn.me.Lifecycle>`.
Other plugins reach the window as `hxn.me.Plugins.hxnme_window.window`, a
`hxn.window.Window`.

## Checks

```
cd tests/window && hxn check hl cpp cppia app.hxml --vm ash
```

The check opens a hidden window. Follow the
[hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md) and the
[kernel skill](https://github.com/hx-n/hxnme/blob/main/skills/hxnme/SKILL.md).
