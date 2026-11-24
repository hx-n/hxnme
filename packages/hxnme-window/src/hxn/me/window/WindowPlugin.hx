package hxn.me.window;

import haxe.Timer;
import hxn.me.AppLoop;
import hxn.me.Events;
import hxn.me.Project;
import hxn.me.ResMut;
import hxn.window.Event;
import hxn.window.Window;
import hxn.window.WindowAttributes;

/**
	The window of the app, and the host that paces its frames. The window
	opens when the app runs, with the keys of the `[window]` table in
	`hxnme.toml`. The host runs a frame at each refresh of the monitor that
	shows the window, and reads the window's events between frames. If
	`Display.vsync` is true and the window is visible, the present waits for
	the refresh, so the host runs each frame when the last one is presented.
	It still waits until most of a period has passed, in case a driver's
	present returns early. Otherwise the host waits on its own timer. It sets
	`Display` from the window's size and scale. It sets `Lifecycle` from the
	window's focus and visibility, and from the platform's suspend and resume.
	Closing the window stops the app. Each event of the window is also in
	`Events<hxn.window.Event>` for the frame that follows it, which the
	plugin's system `publish` fills in `Begin`.
**/
@:plugin("hxnme-window", description = "Opens the app's window and paces its frames")
@:provides(hxn.me.Host)
class WindowPlugin {
	/** The window, after the app starts to run. **/
	public var window(default, null):Null<Window>;

	// The part of a refresh period after a frame starts before the next one
	// is due, when the present waits for the refresh.
	static inline final PRESENT_SHARE = 0.9;

	// The events since the last frame, which `publish` moves to the queue.
	static final queued:Array<Event> = [];

	var suspended = false;
	var visible = true;
	var focused = true;

	public function new() {}

	public function start():Void {}

	/** Queues `event` as if the window had sent it. Checks and input replay use it. **/
	public static function post(event:Event):Void
		queued.push(event);

	@:system(Begin, description = "Publishes the window's events since the last frame")
	static function publish(events:ResMut<Events<Event>>) {
		for (event in queued)
			events.push(event);
		queued.resize(0);
	}

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
		loop.display.setRefresh(rate(window));
		var period = 1 / loop.display.refresh;
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
			// A hidden or occluded window does not wait for the refresh to
			// present, so the timer paces it. When the present waits for the
			// refresh, the next frame is due most of a period after the last
			// one started. A present that waits returns after that, so the
			// host does not wait. A present that returns early cannot run
			// frames faster than the display shows them.
			var presentPaces = loop.display.vsync && visible;
			var due = presentPaces ? last + period * PRESENT_SHARE : next;
			var left = due - Timer.stamp();
			var event = window.wait(left > 0 ? left : 0);
			switch event {
				case None:
				case _:
					handle(event, loop);
					continue;
			}
			if (Timer.stamp() < due)
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
		switch event {
			case None:
				return;
			case _:
				queued.push(event);
		}
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
