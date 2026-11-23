package hxn.me.gpu;

import hxn.gpu.GpuDevice;
import hxn.gpu.Texture;

/**
	`FrameGraph` holds the passes that draw each frame, in the order that they
	run. Plugins and the app add each pass one time. The graph then runs the
	pass in every frame while it is enabled, so drawing a frame makes no new
	pass objects. The graph records all passes of a frame into one command
	encoder and submits them together.
**/
class FrameGraph {
	final passes:Array<Pass> = [];

	public function new() {}

	public function add(pass:Pass):Void {
		var at = passes.length;
		while (at > 0 && passes[at - 1].order > pass.order)
			at--;
		passes.insert(at, pass);
	}

	public function remove(pass:Pass):Void
		passes.remove(pass);

	/** Returns the passes in the order that they run. **/
	public function iterator():Iterator<Pass>
		return passes.iterator();

	// Records each enabled pass into `frame` or into its render target, then submits all of them.
	@:allow(hxn.me.gpu.GpuPlugin) function run(device:GpuDevice, frame:Texture, gpu:Gpu):Void {
		var encoder = device.createCommandEncoder();
		var cleared = false;
		for (pass in passes) {
			if (!pass.enabled)
				continue;
			var into = pass.target == null ? frame : pass.target.resolve(device, frame);
			var recording = if (pass.target == null) {
				var clear = pass.clear != null ? pass.clear : cleared ? null : gpu.clear;
				cleared = true;
				clear != null ? encoder.beginRenderPass(into, clear) : encoder.beginRenderPass(into, null, true);
			} else {
				pass.keep ? encoder.beginRenderPass(into, null, true) : encoder.beginRenderPass(into, pass.clear);
			}
			pass.draw(recording, into);
			recording.end();
		}
		if (!cleared)
			encoder.beginRenderPass(frame, gpu.clear).end();
		device.submit(encoder);
	}
}
