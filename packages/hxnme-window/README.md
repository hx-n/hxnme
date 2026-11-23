# hxnme-window

The window of an hxnme app, in `hxn.me.window`. The plugin opens the window
when the app runs, and it is the app's host: it paces the frames and reads
the window's events between frames. It is built on
[hxn-window](https://github.com/hx-n/hxn-window).

List the plugin in the app's `hxnme.toml`, with the window's keys:

```toml
plugins = ["hxnme-window"]

[window]
title = "Game"
width = 1280
height = 720
```

| Key | Effect |
|---|---|
| `window.title` | The title. The default is `hxnme`. |
| `window.width`, `window.height` | The size in logical pixels. The defaults are 1280 and 720. |
| `window.resizable` | Whether the user can resize the window. The default is `true`. |
| `window.fullscreen` | Whether the window fills the screen. The default is `false`. |
| `window.visible` | Whether the window shows. The default is `true`. |
| `window.rate` | The frames in a second if the platform does not report the refresh rate of the monitor. The default is 60. |

The host runs a frame at each refresh of the monitor that shows the window.
It sets the kernel resources from the window:

| Event | Effect |
|---|---|
| The window opens, resizes or changes scale | `Display` gets the size in physical pixels and the scale. |
| The window gains or loses the focus | `Lifecycle.focused` changes. |
| The window is hidden or shown again | `Lifecycle.visible` changes. |
| The platform suspends or resumes the app | `Lifecycle.suspended` changes. The app runs no frame while it is suspended. |
| The user closes the window | The app stops after the current frame. |

Each event of the window is also in the resource
`hxn.me.Events<hxn.window.Event>`. The plugin's system `publish` fills the
queue in `Begin`, with the events since the last frame. Systems that read
the queue in `Begin` run after it with `after = hxn.me.window.WindowPlugin`.
The input plugin reads it this way. `WindowPlugin.post(event)` queues an
event as if the window had sent it, for checks and for input replay.

Other plugins reach the window through `hxn.me.Plugins.hxnme_window.window`,
for example to make a GPU surface from its native handles.

## Checks

In `tests/window`, run `hxn check hl cpp cppia app.hxml --vm ash`. The check
opens a hidden window, runs three frames and closes it.
