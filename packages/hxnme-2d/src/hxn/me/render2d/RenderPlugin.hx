package hxn.me.render2d;

import hxn.me.Display;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.gpu.Cameras;
import hxn.me.gpu.Gpu;
import hxn.me.gpu.GpuPlugin;

/**
	`RenderPlugin` draws the 2D content of the app on the GPU of hxnme-gpu,
	through the cameras in `Cameras`. Each frame has three stages:

	- In `Begin`, `reset` empties `Draw`.
	- In `Update`, the systems of the app add to `Draw` and change `Sprites`.
	- In `Render`, before hxnme-gpu draws the frame, `upload` sends the
	  instances, the changed parts of `Sprites` and the matrix of each camera to
	  the GPU.

	Each enabled camera has a pass in the frame graph. The pass draws into the
	frame, or into the render target of the camera.
**/
@:plugin("hxnme-2d", description = "Draws sprites, shapes, nine-slices and text on the GPU")
class RenderPlugin {
	static var renderer:Null<Renderer>;

	public function new() {}

	public function start():Void {}

	@:system(Begin, description = "Empties Draw for the new frame, and sets the scale for rasterizing text")
	static function reset(draw:ResMut<Draw>, typesetter:ResMut<Typesetter>, display:Res<Display>) {
		(draw : Draw).clear();
		(typesetter : Typesetter).begin(display.scale);
	}

	@:system(Render, before = GpuPlugin.present, description = "Uploads the instances, the changed sprites and each camera's matrix for this frame")
	static function upload(gpu:Res<Gpu>, cameras:Res<Cameras>, draw:Res<Draw>, sprites:Res<Sprites>, display:Res<Display>) {
		var state:Gpu = gpu;
		if (!state.ready())
			return;
		if (renderer == null)
			renderer = new Renderer(state, draw, sprites);
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
