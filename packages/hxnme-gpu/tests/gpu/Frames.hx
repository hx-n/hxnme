import hxn.me.Lifecycle;
import hxn.me.ResMut;
import hxn.me.gpu.Gpu;
import hxn.me.gpu.Pass;
import hxn.me.gpu.RenderTarget;

/**
	The check adds a pass that clears a 4x4 render target and a pass that
	clears the frame. After the plugin presents three frames, the check reads
	the target back and stops the app.
**/
class Frames {
	static final target = new RenderTarget(4, 4);
	static var reading = false;

	@:system(Start)
	static function setup(gpu:ResMut<Gpu>) {
		var into = new Pass("check target", target, (_, _) -> {});
		into.clear = {r: 0.25, g: 0.5, b: 0.75, a: 1};
		gpu.graph.add(into);
		var frame = new Pass("check frame", null, (_, _) -> {});
		frame.clear = {r: 1, g: 0, b: 0, a: 1};
		gpu.graph.add(frame);
		Sys.println("passes: " + [for (p in gpu.graph) p.name].join(", "));
	}

	@:system(Update)
	static function check(gpu:ResMut<Gpu>, lifecycle:ResMut<Lifecycle>) {
		if (gpu.failure != null) {
			Sys.println('no GPU: ${gpu.failure}');
			lifecycle.quit();
			return;
		}
		if (gpu.presented < 3 || reading)
			return;
		reading = true;
		var state:Lifecycle = lifecycle;
		gpu.device.readTexture(target.texture).then(pixels -> {
			Sys.println('frames presented: at least 3');
			Sys.println('target: ${target.texture.width}x${target.texture.height} of ${[for (c in 0...4) pixels.get(c)].join(", ")}');
			state.quit();
		}, e -> {
			Sys.println('readback failed: ${e.message}');
			state.quit();
		});
	}
}
