package hxn.me.window;

import haxe.Timer;
import hxn.me.AppLoop;
import hxn.me.Project;
import hxn.window.Event;
import hxn.window.Window;
import hxn.window.WindowAttributes;

/**
	The window of the app, and the host that paces its frames. The window
	opens when the app runs, with the keys of the `[window]` table in
	`hxnme.toml`. The host runs a frame at each refresh of the monitor that
	shows the window, and reads the window's events between frames. It sets
	`Display` from the window's size and scale. It sets `Lifecycle` from the
	window's focus and visibility, and from the platform's suspend and resume.
	Closing the window stops the app.
**/
@:plugin("hxnme-window", description = "Opens the app's window and paces its frames")
@:provides(hxn.me.Host)
class WindowPlugin {
	/** The window, after the app starts to run. **/
	public var window(default, null):Null<Window>;

	var suspended = false;
	var visible = true;
	var focused = true;

	public function new() {}

	public function start():Void {}

	public function run(loop:AppLoop):Void {
		var attributes = new WindowAttributes();
		attributes.title(Project.text("window.title", "hxnme"));
		attributes.width(Project.integer("window.width", 1280));
		attributes.height(Project.integer("window.height", 720));
		attributes.resizable(Project.flag("window.resizable", true));
		attributes.fullscreen(Project.flag("window.fullscreen", false));
		attributes.visible(Project.flag("window.visible", true));
		var window = Window.open(attributes);
		attributes.close();
		this.window = window;
		visible = Project.flag("window.visible", true);
		loop.display.set(window.width(), window.height(), window.scaleFactor());
		loop.lifecycle.set(suspended, visible, focused);
		var period = 1 / rate(window);
		var last = Timer.stamp();
		var next = last;
		while (loop.lifecycle.running) {
			if (suspended) {
				// While the app is suspended, it runs no frame, so wait for the
				// platform to resume it.
				handle(window.wait(-1), loop);
				last = next = Timer.stamp();
				continue;
			}
			var left = next - Timer.stamp();
			var event = window.wait(left > 0 ? left : 0);
			switch event {
				case None:
				case _:
					handle(event, loop);
					continue;
			}
			if (Timer.stamp() < next)
				continue;
			var now = Timer.stamp();
			if (!loop.frame(now - last))
				break;
			last = now;
			next += period;
			if (next < now)
				next = now;
		}
		window.close();
		this.window = null;
	}

	// The frames in a second: the refresh rate of the monitor that shows the
	// window, or `window.rate` in hxnme.toml if the platform does not report it.
	function rate(window:Window):Float {
		var monitor = window.currentMonitor();
		var millihertz = monitor.valid() ? monitor.refreshRate() : 0;
		monitor.close();
		return millihertz > 0 ? millihertz / 1000 : Project.number("window.rate", 60);
	}

	function handle(event:Event, loop:AppLoop):Void {
		var display = loop.display;
		switch event {
			case Closed:
				loop.lifecycle.quit();
			case Resized(width, height):
				display.set(width.low, height.low, display.scale);
			case ScaleFactorChanged(scale):
				display.set(display.width, display.height, scale);
			case Focused(focus):
				focused = focus;
			case Occluded(occluded):
				visible = !occluded;
			case Suspended:
				suspended = true;
			case Resumed:
				suspended = false;
			case _:
				return;
		}
		loop.lifecycle.set(suspended, visible, focused);
	}
}
