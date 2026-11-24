# hxnme-window

hxnme-window opens the window of an hxnme app and runs the app's frames.
Its package is `hxn.me.window`. When the app runs, the plugin opens the
window. It is also the app's host, so it paces the frames and reads the
window's events between frames. It uses
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
| `window.rate` | The frames in a second, for a platform that does not report the refresh rate of the monitor. The default is 60. |

The host runs a frame at each refresh of the monitor that shows the window,
and sets `Display.refresh` to the monitor's refresh rate. If the GPU plugin
presents with vsync, it sets `Display.vsync`. While `Display.vsync` is true
and the window is visible, the present paces the frames. The host then
starts each frame after the present of the last frame returns, but not
before nine tenths of a refresh period. Otherwise the host paces the frames
with its own timer.

In a web page, the window is the web page's canvas. When the program is
compiled to wasm with Ash, it runs in a worker with shared memory. The host
then waits for events and frames as it does natively. When the program is
compiled to wasm with hxcpp, `run` returns to the browser. The browser then
runs each turn of the host. Each turn reads the window's events and
returns to the browser. If a frame is due, the turn runs it before it
returns.

The host sets the kernel resources from the window:

| Event | Effect |
|---|---|
| The window opens, resizes or changes scale | `Display` gets the size in physical pixels and the scale. |
| The window gains or loses the focus | `Lifecycle.focused` changes. |
| The window is hidden or shown again | `Lifecycle.visible` changes. |
| The platform suspends or resumes the app | `Lifecycle.suspended` changes. The app runs no frame while it is suspended. |
| The user closes the window | The app stops after the current frame. |

The plugin also puts each event of the window in the resource
`hxn.me.Events<hxn.window.Event>`. Its system `publish` fills the queue in
`Begin`, with the events since the last frame. Systems that read the queue
in `Begin` set `after = hxn.me.window.WindowPlugin`, so they run after
`publish`. The input plugin reads the queue this way.
`WindowPlugin.post(event)` queues an event in the same way that the window
queues its own events. Checks and input replay use it.

Other plugins get the window from `hxn.me.Plugins.hxnme_window.window`, for
example to make a GPU surface from its native handles.

## Checks

In `tests/window`, run `hxn check hl cpp cppia app.hxml --vm ash`. The check
opens a hidden window, runs three frames and closes it.
