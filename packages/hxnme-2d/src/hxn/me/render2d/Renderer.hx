package hxn.me.render2d;

import haxe.ds.ObjectMap;
import haxe.io.Bytes;
import hxn.gpu.BindGroup;
import hxn.gpu.Buffer;
import hxn.gpu.GpuDevice;
import hxn.gpu.RenderPass;
import hxn.gpu.RenderPipeline;
import hxn.gpu.Sampler;
import hxn.gpu.ShaderModule;
import hxn.gpu.Texture as GpuTexture;
import hxn.gpu.TextureFormat;
import hxn.me.gpu.Camera;
import hxn.me.gpu.Gpu;
import hxn.me.gpu.Pass;

/**
	`Renderer` holds the GPU objects of the 2D renderer: the shader, a pipeline
	for each target format, and one vertex buffer for each instance field. It
	uploads what `Draw` holds each frame. Each camera has a view of its own:
	a pass in the frame graph, and for each plane that the frame draws on, a
	uniform buffer with the camera's matrix times the plane's. The pass draws
	the runs of the camera's layers, with one instanced draw for each run.
**/
class Renderer {
	final device:GpuDevice;
	final gpu:Gpu;
	final shader:ShaderModule;
	final pipelines = new Map<String, RenderPipeline>();
	final sampler:Sampler;
	final white = Texture.solid(0xFFFFFF);
	final buffers:Array<Buffer> = [];
	final views = new ObjectMap<Camera, View>();
	final params = Bytes.alloc(Shader.PARAMS_SIZE);
	final matrix = [for (_ in 0...16) 0.0];
	final model = [for (_ in 0...16) 0.0];
	final combined = [for (_ in 0...16) 0.0];
	// The world's XY plane, for runs without a plane.
	final flat = new Plane();
	final draw:Draw;
	var capacity = 0;

	public function new(gpu:Gpu, draw:Draw) {
		this.gpu = gpu;
		device = gpu.device;
		this.draw = draw;
		shader = device.createShader(Shader);
		sampler = device.createSampler({filter: Linear});
	}

	/** Uploads the instances that `draw` holds, for the passes of this frame. **/
	public function upload():Void {
		for (view in views)
			view.pass.enabled = false;
		var instances = draw.instances;
		if (instances.length == 0)
			return;
		if (instances.length > capacity) {
			for (b in buffers)
				b.close();
			buffers.resize(0);
			capacity = instances.capacity;
			for (_ in 0...Instances.FIELDS)
				buffers.push(device.createBuffer({size: capacity * Instances.STRIDE, usage: Vertex}));
		}
		for (i in 0...Instances.FIELDS)
			device.writeBuffer(buffers[i], 0, instances.fields[i].sub(0, instances.length * Instances.STRIDE));
		for (run in draw.runs)
			if (run.texture != null)
				run.texture.upload(device);
	}

	/**
		Uploads `camera`'s matrix for a view `width` by `height` logical pixels,
		and turns on its pass for this frame.
	**/
	public function show(camera:Camera, width:Float, height:Float):Void {
		var view = views.get(camera);
		if (view == null) {
			view = new View(camera);
			view.pass = new Pass("2d", camera.target, (pass, into) -> record(view, pass, into), camera.order);
			if (camera.target != null)
				view.pass.clear = camera.clear;
			gpu.graph.add(view.pass);
			views.set(camera, view);
		}
		view.pass.enabled = draw.instances.length > 0;
		camera.writeMatrix(width, height, matrix);
		params.setFloat(Shader.PARAMS_flags, camera.yDown() ? 1 : 0);
		var last:Null<Plane> = null;
		var first = true;
		for (run in draw.runs) {
			if (run.layer & camera.layers == 0 || (!first && run.plane == last))
				continue;
			first = false;
			last = run.plane;
			var plane = run.plane != null ? run.plane : flat;
			plane.writeMatrix(model);
			multiply(matrix, model, combined);
			// Each column goes to its own offset, since the shader's uniform block lays them out.
			for (i in 0...4) {
				params.setFloat(Shader.PARAMS_matrix0 + i * 4, combined[i]);
				params.setFloat(Shader.PARAMS_matrix1 + i * 4, combined[4 + i]);
				params.setFloat(Shader.PARAMS_matrix3 + i * 4, combined[12 + i]);
			}
			device.writeBuffer(view.on(plane, device).uniforms, 0, params);
		}
	}

	// Writes a times b into out; all three are 4x4, column after column.
	static function multiply(a:Array<Float>, b:Array<Float>, out:Array<Float>):Void {
		for (col in 0...4)
			for (row in 0...4) {
				var sum = 0.0;
				for (k in 0...4)
					sum += a[k * 4 + row] * b[col * 4 + k];
				out[col * 4 + row] = sum;
			}
	}

	function record(view:View, pass:RenderPass, into:GpuTexture):Void {
		var camera = view.camera;
		var v = camera.viewport;
		if (v.x != 0 || v.y != 0 || v.width != 1 || v.height != 1) {
			var x = Math.round(v.x * into.width), y = Math.round(v.y * into.height);
			var w = Math.round(v.width * into.width), h = Math.round(v.height * into.height);
			pass.setViewport(x, y, w, h);
			pass.setScissorRect(x, y, w, h);
		}
		var pipeline = pipelineFor(into.format);
		pass.setPipeline(pipeline);
		var shared = Shader.PARAMS_GROUP == Shader.TEXTURE_image_GROUP;
		for (run in draw.runs) {
			if (run.layer & camera.layers == 0)
				continue;
			var on = view.on(run.plane != null ? run.plane : flat, device);
			if (!shared) {
				if (on.params == null)
					on.params = device.createBindGroup({
						pipeline: pipeline,
						group: Shader.PARAMS_GROUP,
						entries: [{binding: Shader.PARAMS_BINDING, buffer: on.uniforms}]
					});
				pass.setBindGroup(Shader.PARAMS_GROUP, on.params);
			}
			var image = run.texture != null ? run.texture : white;
			pass.setBindGroup(Shader.TEXTURE_image_GROUP, groupOf(on, image, pipeline, shared));
			for (i in 0...Instances.FIELDS)
				pass.setVertexBuffer(i, buffers[i], run.start * Instances.STRIDE);
			pass.draw(4, run.count);
		}
	}

	function groupOf(view:PlaneView, image:Texture, pipeline:RenderPipeline, shared:Bool):BindGroup {
		var group = view.groups.get(image);
		if (group == null) {
			var entries:Array<hxn.gpu.Descriptors.BindGroupEntry> = [
				{binding: Shader.TEXTURE_image, texture: image.upload(device)},
				{binding: Shader.TEXTURE_image + 1, sampler: sampler}
			];
			if (shared)
				entries.push({binding: Shader.PARAMS_BINDING, buffer: view.uniforms});
			group = device.createBindGroup({pipeline: pipeline, group: Shader.TEXTURE_image_GROUP, entries: entries});
			view.groups.set(image, group);
		}
		return group;
	}

	function pipelineFor(format:TextureFormat):RenderPipeline {
		var key = '$format';
		var found = pipelines.get(key);
		if (found != null)
			return found;
		var field = (location:Int) -> ({
			stride: Instances.STRIDE,
			perInstance: true,
			attributes: [{location: location, format: Float32x4, offset: 0}]
		} : hxn.gpu.Descriptors.VertexBufferLayout);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: format,
			topology: TriangleStrip,
			blend: hxn.gpu.Blend.alpha,
			vertexBuffers: [
				field(Shader.INPUT_rect),
				field(Shader.INPUT_uv),
				field(Shader.INPUT_color),
				field(Shader.INPUT_xform),
				field(Shader.INPUT_shape),
				field(Shader.INPUT_radius),
				field(Shader.INPUT_border)
			]
		});
		pipelines.set(key, pipeline);
		return pipeline;
	}
}

/** Each view holds what one camera needs to draw: its pass, and what it needs for each plane. **/
private class View {
	public final camera:Camera;
	public var pass:Pass;
	final planes = new ObjectMap<Plane, PlaneView>();

	public function new(camera:Camera)
		this.camera = camera;

	/** Returns what the camera needs to draw on `plane`, made on first use. **/
	public function on(plane:Plane, device:GpuDevice):PlaneView {
		var found = planes.get(plane);
		if (found == null) {
			found = new PlaneView(device.createBuffer({size: Shader.PARAMS_SIZE, usage: Uniform}));
			planes.set(plane, found);
		}
		return found;
	}
}

/** Each plane view holds one camera's uniform buffer for one plane, and its bind groups. **/
private class PlaneView {
	public final uniforms:Buffer;
	public var params:Null<BindGroup>;
	public final groups = new ObjectMap<Texture, BindGroup>();

	public function new(uniforms:Buffer)
		this.uniforms = uniforms;
}
