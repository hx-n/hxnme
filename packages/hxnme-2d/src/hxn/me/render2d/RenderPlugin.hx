package hxn.me.render2d;

import hxn.me.Display;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.gpu.Cameras;
import hxn.me.gpu.Gpu;
import hxn.me.gpu.GpuPlugin;

/**
	`RenderPlugin` draws the app's 2D content with the GPU of hxnme-gpu,
	through the cameras of `Cameras`. In each frame, `reset` empties `Draw` in
	`Begin`, systems add to it in `Update`, and `upload` sends the instances
	and each camera's matrix to the GPU in `Render`, before hxnme-gpu draws the
	frame. Each enabled camera has a pass in the frame graph, into the frame or
	into its render target.
**/
@:plugin("hxnme-2d", description = "Draws sprites and shapes with one instanced shader")
class RenderPlugin {
	static var renderer:Null<Renderer>;

	public function new() {}

	public function start():Void {}

	@:system(Begin, description = "Empties Draw for the new frame")
	static function reset(draw:ResMut<Draw>) {
		(draw : Draw).clear();
	}

	@:system(Render, before = GpuPlugin.present, description = "Uploads the instances and each camera's matrix for this frame")
	static function upload(gpu:Res<Gpu>, cameras:Res<Cameras>, draw:Res<Draw>, display:Res<Display>) {
		var state:Gpu = gpu;
		if (!state.ready())
			return;
		if (renderer == null)
			renderer = new Renderer(state, draw);
		renderer.upload();
		for (camera in cameras.sorted()) {
			var target = camera.target;
			var scale = target == null ? display.scale : 1.0;
			var width = target == null ? display.width : (target.texture != null ? target.texture.width : target.width);
			var height = target == null ? display.height : (target.texture != null ? target.texture.height : target.height);
			renderer.show(camera, width * camera.viewport.width / scale, height * camera.viewport.height / scale);
		}
	}
}
