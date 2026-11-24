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
	`Renderer` holds the GPU objects of the 2D renderer: the shader, one
	pipeline for each target format, and one vertex buffer for each instance
	field. In each frame, it uploads the contents of `Draw`.

	Each camera has its own view, with a pass in the frame graph. For each plane
	and clip that the frame draws on, the view also has a uniform buffer with
	the matrix of the camera times the matrix of the plane, and the clip. The pass draws the sprite
	groups of `Sprites` in the layers of the camera, then the runs of `Draw`.
	Each group and each run is one instanced draw.
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
	// Counts the cameras shown. Each plane view records the count when its uniforms are written, so they are written once for each camera in each frame.
	var shown = 0;
	// The world's XY plane, for runs without a plane.
	final flat = new Plane();
	// The key for runs without a clip.
	final open = new Clip(0, 0, 0, 0);
	final draw:Draw;
	final sprites:Sprites;
	var capacity = 0;

	public function new(gpu:Gpu, draw:Draw, sprites:Sprites) {
		this.gpu = gpu;
		device = gpu.device;
		this.draw = draw;
		this.sprites = sprites;
		shader = device.createShader(Shader);
		sampler = device.createSampler({filter: Linear});
	}

	/** Uploads the instances in `draw` and the changed parts of the sprite groups, for the passes of this frame. **/
	public function upload():Void {
		for (view in views)
			view.pass.enabled = false;
		uploadSprites();
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

	function uploadSprites():Void {
		sprites.refresh();
		var bytes = 0;
		for (group in sprites.groups) {
			var instances = group.instances;
			var length = instances.length;
			if (length == 0) {
				group.settle();
				continue;
			}
			group.texture.upload(device);
			if (instances.capacity > group.bufferCapacity) {
				// New buffers start empty, so every instance is uploaded.
				for (b in group.buffers)
					b.close();
				group.buffers.resize(0);
				group.bufferCapacity = instances.capacity;
				for (i in 0...Instances.FIELDS) {
					group.buffers.push(device.createBuffer({size: group.bufferCapacity * Instances.STRIDE, usage: Vertex}));
					device.writeBuffer(group.buffers[i], 0, instances.fields[i].sub(0, length * Instances.STRIDE));
					bytes += length * Instances.STRIDE;
				}
			} else
				for (i in 0...Instances.FIELDS) {
					// After a removal, the changed range can end past the group, so it is cut to the group's length.
					var high = group.high[i] < length ? group.high[i] : length;
					var low = group.low[i];
					if (low >= high)
						continue;
					var at = low * Instances.STRIDE, size = (high - low) * Instances.STRIDE;
					device.writeBuffer(group.buffers[i], at, instances.fields[i].sub(at, size));
					bytes += size;
				}
			group.settle();
		}
		sprites.count(bytes);
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
			view.pass.depth = camera.depth;
			gpu.graph.add(view.pass);
			views.set(camera, view);
		}
		view.pass.enabled = draw.instances.length > 0 || sprites.length > 0;
		camera.writeMatrix(width, height, matrix);
		params.setFloat(Shader.PARAMS_flags, camera.yDown() ? 1 : 0);
		shown++;
		for (group in sprites.groups)
			if (group.layer & camera.layers != 0 && group.instances.length > 0)
				writeUniforms(view, group.plane, group.clip);
		for (run in draw.runs)
			if (run.layer & camera.layers != 0)
				writeUniforms(view, run.plane, run.clip);
	}

	// Writes the camera's matrix times the matrix of `plane`, and `clip`, into the camera's uniforms for that plane and clip.
	function writeUniforms(view:View, plane:Null<Plane>, clip:Null<Clip>):Void {
		var on = view.on(plane != null ? plane : flat, clip != null ? clip : open, device);
		if (on.shown == shown)
			return;
		on.shown = shown;
		var plane = plane != null ? plane : flat;
		plane.writeMatrix(model);
		multiply(matrix, model, combined);
		// The uniform block of the shader gives each column its own offset.
		for (i in 0...4) {
			params.setFloat(Shader.PARAMS_matrix0 + i * 4, combined[i]);
			params.setFloat(Shader.PARAMS_matrix1 + i * 4, combined[4 + i]);
			params.setFloat(Shader.PARAMS_matrix3 + i * 4, combined[12 + i]);
		}
		if (clip != null) {
			params.setFloat(Shader.PARAMS_clipRect, clip.x);
			params.setFloat(Shader.PARAMS_clipRect + 4, clip.y);
			params.setFloat(Shader.PARAMS_clipRect + 8, clip.width);
			params.setFloat(Shader.PARAMS_clipRect + 12, clip.height);
			params.setFloat(Shader.PARAMS_clipShape, clip.radius);
			params.setFloat(Shader.PARAMS_clipShape + 4, clip.corner);
		}
		params.setFloat(Shader.PARAMS_clipShape + 8, clip != null ? 1 : 0);
		device.writeBuffer(on.uniforms, 0, params);
	}

	// Writes a times b into out. All three are 4x4 matrices, stored column by column.
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
		var pipeline = pipelineFor(into.format, camera.depth);
		pass.setPipeline(pipeline);
		for (group in sprites.groups)
			if (group.layer & camera.layers != 0 && group.instances.length > 0)
				drawRange(view, pass, pipeline, group.plane, group.clip, group.texture, group.buffers, 0, group.instances.length);
		for (run in draw.runs)
			if (run.layer & camera.layers != 0)
				drawRange(view, pass, pipeline, run.plane, run.clip, run.texture != null ? run.texture : white, buffers, run.start, run.count);
	}

	// Draws `count` instances of `source` from index `start`, on `plane` inside `clip`, with `image`.
	function drawRange(view:View, pass:RenderPass, pipeline:RenderPipeline, plane:Null<Plane>, clip:Null<Clip>, image:Texture, source:Array<Buffer>,
			start:Int, count:Int):Void {
		var shared = Shader.PARAMS_GROUP == Shader.TEXTURE_image_GROUP;
		var on = view.on(plane != null ? plane : flat, clip != null ? clip : open, device);
		if (!shared) {
			if (on.params == null)
				on.params = device.createBindGroup({
					pipeline: pipeline,
					group: Shader.PARAMS_GROUP,
					entries: [{binding: Shader.PARAMS_BINDING, buffer: on.uniforms}]
				});
			pass.setBindGroup(Shader.PARAMS_GROUP, on.params);
		}
		pass.setBindGroup(Shader.TEXTURE_image_GROUP, groupOf(on, image, pipeline, shared));
		for (i in 0...Instances.FIELDS)
			pass.setVertexBuffer(i, source[i], start * Instances.STRIDE);
		pass.draw(4, count);
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

	function pipelineFor(format:TextureFormat, depth:Bool):RenderPipeline {
		var key = '$format $depth';
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
			// Later content at the same depth draws over earlier content, as without depth.
			depth: depth ? {format: Depth32Float, compare: LessEqual} : null,
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

/** Each view holds what one camera needs to draw: its pass, and one plane view for each plane and clip. **/
private class View {
	public final camera:Camera;
	public var pass:Pass;
	final planes = new ObjectMap<Plane, ObjectMap<Clip, PlaneView>>();

	public function new(camera:Camera)
		this.camera = camera;

	/** Returns the plane view for `plane` and `clip`, and makes it on first use. **/
	public function on(plane:Plane, clip:Clip, device:GpuDevice):PlaneView {
		var clips = planes.get(plane);
		if (clips == null) {
			clips = new ObjectMap();
			planes.set(plane, clips);
		}
		var found = clips.get(clip);
		if (found == null) {
			found = new PlaneView(device.createBuffer({size: Shader.PARAMS_SIZE, usage: Uniform}));
			clips.set(clip, found);
		}
		return found;
	}
}

/** Each plane view holds one camera's uniform buffer for one plane and clip, and its bind groups. **/
private class PlaneView {
	public final uniforms:Buffer;
	// The count of cameras shown when the uniforms were last written.
	public var shown = -1;
	public var params:Null<BindGroup>;
	public final groups = new ObjectMap<Texture, BindGroup>();

	public function new(uniforms:Buffer)
		this.uniforms = uniforms;
}
