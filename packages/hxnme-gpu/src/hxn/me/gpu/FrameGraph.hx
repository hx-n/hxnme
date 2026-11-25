package hxn.me.gpu;

import hxn.gpu.GpuDevice;
import hxn.gpu.Texture;

/**
	`FrameGraph` holds the passes that draw each frame, in the order that they
	run. Plugins and the app add each pass once. The graph then runs the
	pass in every frame while it is enabled, so drawing a frame makes no new
	pass objects. The graph records all passes of a frame into one command
	encoder and submits them together.
**/
class FrameGraph {
	final passes:Array<Pass> = [];
	// `frameDepth` holds the frame's depth texture. The graph makes it when a
	// pass with depth draws into the frame.
	var frameDepth:Null<Texture>;
	// `cleared` lists the depth textures that the graph cleared in this frame.
	final cleared:Array<Texture> = [];

	public function new() {}

	public function add(pass:Pass):Void {
		var at = passes.length;
		while (at > 0 && passes[at - 1].order > pass.order)
			at--;
		passes.insert(at, pass);
	}

	public function remove(pass:Pass):Void
		passes.remove(pass);

	// Returns the frame's depth texture, made again when the frame's size changes.
	function frameDepthFor(device:GpuDevice, frame:Texture, gpu:Gpu):Texture {
		if (frameDepth != null && (frameDepth.width != frame.width || frameDepth.height != frame.height)) {
			gpu.retire(frameDepth);
			frameDepth = null;
		}
		if (frameDepth == null)
			frameDepth = device.createTexture({width: frame.width, height: frame.height, format: Depth32Float, usage: RenderTarget});
		return frameDepth;
	}

	/** Returns the passes in the order that they run. **/
	public function iterator():Iterator<Pass>
		return passes.iterator();

	// Records each enabled pass into `frame` or into its render target, then submits all of them.
	@:allow(hxn.me.gpu.GpuPlugin) function run(device:GpuDevice, frame:Texture, gpu:Gpu):Void {
		var encoder = device.createCommandEncoder();
		var frameCleared = false;
		cleared.resize(0);
		for (pass in passes) {
			if (!pass.enabled)
				continue;
			var into = pass.target == null ? frame : pass.target.resolve(device, frame, gpu);
			var color:hxn.gpu.Descriptors.ColorAttachment = if (pass.target == null) {
				var clear = pass.clear != null ? pass.clear : frameCleared ? null : gpu.clear;
				frameCleared = true;
				clear != null ? {target: into, clear: clear} : {target: into, keep: true};
			} else {
				pass.keep ? {target: into, keep: true} : {target: into, clear: pass.clear};
			}
			var depth:Null<hxn.gpu.Descriptors.DepthAttachment> = null;
			if (pass.depth) {
				var texture = pass.target == null ? frameDepthFor(device, frame, gpu) : pass.target.resolveDepth(device, gpu);
				var first = cleared.indexOf(texture) < 0;
				if (first)
					cleared.push(texture);
				depth = first ? {target: texture, clear: 1.0} : {target: texture, keep: true};
			}
			var recording = encoder.beginRenderPassWith({colors: [color], depth: depth});
			pass.draw(recording, into);
			recording.end();
		}
		if (!frameCleared)
			encoder.beginRenderPass(frame, gpu.clear).end();
		device.submit(encoder);
	}
}
