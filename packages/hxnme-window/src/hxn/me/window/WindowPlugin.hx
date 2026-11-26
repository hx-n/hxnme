package hxn.me.window;

import haxe.Timer;
import hxn.me.AppLoop;
import hxn.me.Display;
import hxn.me.Events;
import hxn.me.Project;
import hxn.me.ResMut;
import hxn.window.Event;
import hxn.window.Window;
import hxn.window.WindowAttributes;

/**
	`WindowPlugin` opens the app's window and runs its frames as the app's
	host. When the app runs, the plugin opens the window with the keys of the
	`[window]` table in `hxnme.toml`. The host runs a frame at each refresh of
	the monitor that shows the window, and reads the window's events between
	frames. When the app is compiled to wasm with hxcpp, `run` returns, and
	the browser runs each turn of the host.

	If `Display.vsync` is true and the window is visible, the present waits
	for the refresh. The host then runs each frame after the present of the
	last frame returns. It still waits until most of a period has passed, in
	case a driver's present returns early. Otherwise the host waits on its
	own timer.

	The host sets `Display` from the window's size and scale. It sets
	`Lifecycle` from the window's focus and visibility, and from the
	platform's suspend and resume. When the user closes the window, the app
	stops. The plugin's system `publish` also puts each event of the window in
	`Events<hxn.window.Event>`, in `Begin` of the frame that follows the event.
**/
@:plugin("hxnme-window", description = "Opens the app's window and paces its frames")
@:provides(hxn.me.Host)
class WindowPlugin {
	/** The window, after the app starts to run. **/
	public var window(default, null):Null<Window>;

	// When the present waits for the refresh, the next frame is due this part
	// of a refresh period after the last frame starts.
	static inline final PRESENT_SHARE = 0.9;

	// `queued` holds the events since the last frame, until `publish` moves
	// them to the queue.
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
		#if !hxnme_mobile
		// On Android and iOS, the window fills the screen.
		attributes.width(Project.integer("window.width", 1280));
		attributes.height(Project.integer("window.height", 720));
		attributes.resizable(Project.flag("window.resizable", true));
		attributes.fullscreen(Project.flag("window.fullscreen", false));
		#end
		attributes.visible(Project.flag("window.visible", true));
		var window = Window.open(attributes);
		attributes.close();
		this.window = window;
		visible = Project.flag("window.visible", true);
		measure(window, loop.display, window.scaleFactor());
		loop.lifecycle.set(suspended, visible, focused);
		loop.display.setRefresh(rate(window));
		var period = 1 / loop.display.refresh;
		var last = Timer.stamp();
		var next = last;
		#if emscripten
		// The browser runs the frames. Each turn reads the window's events, runs
		// the frame that is due, if any, and returns to the browser. The browser
		// then delivers the next events.
		function turn() {
			while (loop.lifecycle.running) {
				var event = window.poll();
				switch event {
					case None:
						break;
					case _:
						handle(event, loop);
				}
			}
			var now = Timer.stamp();
			if (loop.lifecycle.running && !suspended && now >= next) {
				loop.frame(now - last);
				last = now;
				next += period;
				if (next < now)
					next = now;
			}
			if (loop.lifecycle.running)
				hxn.native.Emscripten.later(turn);
			else {
				window.close();
				this.window = null;
			}
		}
		hxn.native.Emscripten.later(turn);
		return;
		#end
		while (loop.lifecycle.running) {
			if (suspended) {
				// The app runs no frame while it is suspended, so the host waits for
				// the platform to resume it.
				handle(window.wait(-1), loop);
				last = next = Timer.stamp();
				continue;
			}
			// The present of a hidden or occluded window does not wait for the
			// refresh, so the timer paces that window. When the present waits
			// for the refresh, the next frame is due most of a period after the
			// last one started. Such a present returns after that time, so the
			// host does not wait. If a present returns early, the host still
			// waits until the frame is due, so the frames do not run faster
			// than the display shows them.
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

	// Returns the frames in a second. That is the refresh rate of the monitor
	// that shows the window, or `window.rate` in hxnme.toml for a platform
	// that does not report the refresh rate.
	function rate(window:Window):Float {
		var monitor = window.currentMonitor();
		var millihertz = monitor.valid() ? monitor.refreshRate() : 0;
		monitor.close();
		return millihertz > 0 ? millihertz / 1000 : Project.number("window.rate", 60);
	}

	// Sets the size of the display and its safe area from the window. On Android and iOS, the
	// display is the whole screen, and the window's content is the safe area within it.
	static function measure(window:Window, display:Display, scale:Float):Void {
		#if hxnme_mobile
		var left = window.innerX() - window.x(), top = window.innerY() - window.y();
		display.set(window.outerWidth(), window.outerHeight(), scale);
		display.setSafeArea(left, top, window.outerWidth() - window.width() - left, window.outerHeight() - window.height() - top);
		#else
		display.set(window.width(), window.height(), scale);
		#end
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
			case Resized(_, _):
				measure(this.window, display, display.scale);
			case ScaleFactorChanged(scale):
				measure(this.window, display, scale);
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
