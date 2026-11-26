# Running an app

`hxn.me.App.run` starts the plugins, makes the schedule and gives it to the
host. The host paces the frames. The frames stop after a system calls
`quit` on `Lifecycle`, or after the platform closes the app:

```haxe
class Main {
	static function main()
		hxn.me.App.run(Movement, Scoring);
}
```

The host calls `frame(seconds)` on an `hxn.me.AppLoop` for each frame, with
the seconds since the previous frame. The first frame runs `Start`. Then
each frame does these steps:

1. It runs `Begin`.
2. It advances the clock.
3. It runs `Fixed` one time for each fixed step that the frame completes.
4. It runs `Update` and `Render`.
5. It clears the event queues.

Vsync paces frames at the refresh rate of the display, and their timing
varies a little from frame to frame. If the refresh rate is close to the
step rate, frames can alternate between zero and two fixed steps. The loop
prevents that. If the steps that a frame owes are within `app.step_snap` of
a whole number, the loop rounds them to that number. It carries the
difference to the next frame.

While `Lifecycle.suspended` is true, a frame runs no phase, and the clock
does not advance. At the start of each frame, the loop calls
`hxn.Loop.sync`, which delivers the results of native libraries. On
HashLink, in `hxn run` and `hxn check`, each frame also calls
`hl.Api.checkReload()` for hot reload.

Make `App.run` the last statement of `main`. Under Emscripten, the host
returns from `App.run` before the frames run, and the browser runs the
frames from callbacks. Code after `App.run` then runs before the frames.

To run the phases from its own loop, the app calls `App.schedule` instead
of `App.run`, and gives the schedule to an `AppLoop`:

```haxe
hxn.me.Plugins.start();
var schedule = hxn.me.App.schedule(Movement, Scoring);
var loop = new hxn.me.AppLoop(schedule, schedule.time, schedule.lifecycle, schedule.display);
while (loop.frame(1 / 60)) {}
```

The schedule has three kernel resources. Systems take them in the same way
as other resources:

| Resource | Fields |
|---|---|
| `hxn.me.Time` | `delta`, the seconds of the last frame. `elapsed`, the seconds of all frames. `frame`, the number of frames. `step`, the seconds of a fixed step. `steps`, the fixed steps of this frame. `fixedElapsed`, the seconds of all fixed steps. `alpha`, the fraction of a fixed step, from 0 to 1, that the clock counted and did not run yet. |
| `hxn.me.Lifecycle` | `running`, `suspended`, `visible` and `focused`. `quit()` stops the app after the current frame. |
| `hxn.me.Display` | `width` and `height`, in physical pixels. `safeLeft`, `safeTop`, `safeRight` and `safeBottom`, the insets of the safe area that a notch, the status bar and the home indicator leave free. `scale`, the physical pixels for each logical pixel. `refresh`, the frames that the display shows in a second. `vsync`, whether presenting a frame waits for the refresh. |

The host reads the events of the platform, and it sets `Lifecycle` and
`Display`. `hxn.me.Host` is a service. Each service is an interface with
`@:service`. Plugins provide a service with `@:provides` on the plugin
class, and the class has the methods of the interface. As with
`hxn.me.Plugin`, `implements` is optional, and the kernel checks the
methods either way. `App.run` calls the host's `run` with the loop:

```haxe
@:plugin("hxnme-window")
@:provides(hxn.me.Host)
class WindowPlugin {
	public function new() {}

	public function start():Void {}

	public function run(loop:hxn.me.AppLoop):Void {
		// Wait for the next frame, then call loop.frame(seconds).
	}
}
```

Each service has one provider in an app at most. Two providers of one
service are a compile error. If no plugin provides `Host`, the app runs on
`hxn.me.HeadlessHost`. That host runs `app.rate` frames a second without a
window, with the display that the `display` keys set.
