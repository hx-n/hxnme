package hxn.me.gpu;

import hxn.gpu.GpuDevice;
import hxn.gpu.SurfaceTargets;
import hxn.me.Display;
import hxn.me.Lifecycle;
import hxn.me.Project;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.window.WindowPlugin;

/**
	`GpuPlugin` draws the app's frames with hxn-gpu. In the first frame, it
	opens hxn-gpu on the window of hxnme-window, with the drivers that the
	target compiles in. When the device is open, `Gpu` holds it. In each frame
	after that, the system `prepare` makes the surface the size of the window
	and takes the window's next frame in `Begin`. The system `present` runs the
	passes of the frame graph into that frame and shows it at the end of
	`Render`. Systems in `Render` that change what the passes draw must run
	before `present`, so they add `before = hxn.me.gpu.GpuPlugin.present`.

	`gpu.vsync` in hxnme.toml sets whether each frame waits for the display's
	refresh before it shows. The default is true. The plugin copies it to
	`Display.vsync`, so the host leaves the pacing of frames to the present.
**/
@:plugin("hxnme-gpu", description = "Opens the GPU on the app's window and draws a frame graph into each frame")
class GpuPlugin {
	public function new() {}

	public function start():Void {}

	@:system(Begin, after = WindowPlugin.publish, description = "Opens the GPU on the window, then takes each frame's texture")
	static function prepare(gpu:ResMut<Gpu>, lifecycle:Res<Lifecycle>, display:ResMut<Display>) {
		var window = hxn.me.Plugins.hxnme_window.window;
		if (window == null)
			return;
		var state:Gpu = gpu;
		if (state.device == null) {
			if (!state.opening && state.failure == null) {
				state.opening = true;
				var target = SurfaceTargets.ofWindow(window);
				GpuDevice.open({surface: target, required: [Presentation]}).then(device -> {
					state.opening = false;
					state.opened(device, device.createSurface(target));
				}, error -> {
					state.opening = false;
					state.failed(error.message);
					hxn.Log.error('hxnme-gpu: no GPU to draw with: ${error.message}', "hxnme.gpu");
				});
			}
			return;
		}
		if (lifecycle.suspended)
			return;
		var width = window.width();
		var height = window.height();
		if (width <= 0 || height <= 0)
			return;
		var surface = state.surface;
		if (surface.width != width || surface.height != height) {
			surface.configure(width, height, state.format, Project.flag("gpu.vsync", true));
			(display : Display).setVsync(surface.vsync);
		}
		state.take(surface.currentTexture());
	}

	@:system(Render, description = "Draws the frame graph into the frame and presents it")
	static function present(gpu:ResMut<Gpu>) {
		var state:Gpu = gpu;
		var frame = state.frame;
		if (frame == null)
			return;
		state.graph.run(state.device, frame, state);
		state.surface.present();
		state.shown();
	}
}
