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
	the matrix of the camera times the matrix of the plane, and the clip. The
	pass draws the sprite groups of `Sprites` in the layers of the camera, then
	the runs of `Draw`. Each group and each run is one instanced draw.
**/
class Renderer {
	/**
		`SETS` gives the number of buffer sets that the renderer writes in turn,
		one set in each frame. The GPU finishes with a set long before the
		renderer writes it again, so the writes do not wait for the GPU.
	**/
	public static inline final SETS = 3;

	final device:GpuDevice;
	final gpu:Gpu;
	final shader:ShaderModule;
	final pipelines = new Map<String, RenderPipeline>();
	final sampler:Sampler;
	final white = Texture.solid(0xFFFFFF);
	// Holds the instance buffers of `Draw` in each set, and the number of instances that each set holds.
	final buffers:Array<Array<Buffer>> = [for (_ in 0...SETS) []];
	final capacities = [for (_ in 0...SETS) 0];
	// Holds the index of the set for this frame.
	var set = 0;
	final views = new ObjectMap<Camera, View>();
	final params = Bytes.alloc(Shader.PARAMS_SIZE);
	final matrix = [for (_ in 0...16) 0.0];
	final model = [for (_ in 0...16) 0.0];
	final combined = [for (_ in 0...16) 0.0];
	// Counts the cameras shown. Each plane view records the count when the renderer writes its uniforms, so the renderer writes them once for each camera in each frame.
	var shown = 0;
	// Stands for the world's XY plane in runs without a plane.
	final flat = new Plane();
	// Serves as the key for runs without a clip.
	final open = new Clip(0, 0, 0, 0);
	final draw:Draw;
	final sprites:Sprites;

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
		set = (set + 1) % SETS;
		for (view in views)
			view.pass.enabled = false;
		uploadSprites();
		var instances = draw.instances;
		if (instances.length == 0)
			return;
		var own = buffers[set];
		if (instances.length > capacities[set]) {
			for (b in own)
				gpu.retire(b);
			own.resize(0);
			capacities[set] = instances.capacity;
			for (field in 0...Instances.FIELDS)
				own.push(device.createBuffer({size: instances.capacity * Instances.stride(field), usage: Vertex}));
		}
		for (i in 0...Instances.FIELDS)
			device.writeBuffer(own[i], 0, instances.fields[i].sub(0, instances.length * Instances.stride(i)));
		for (run in draw.runs)
			if (run.texture != null)
				run.texture.upload(device);
	}

	function uploadSprites():Void {
		sprites.refresh();
		for (b in sprites.dropped)
			gpu.retire(b);
		sprites.dropped.resize(0);
		var bytes = 0;
		for (group in sprites.groups) {
			var instances = group.instances;
			var length = instances.length;
			if (length == 0) {
				group.settle(set);
				continue;
			}
			group.texture.upload(device);
			var own = group.buffers[set];
			if (instances.capacity > group.capacities[set]) {
				// New buffers start empty, so every instance is uploaded.
				for (b in own)
					gpu.retire(b);
				own.resize(0);
				group.capacities[set] = instances.capacity;
				for (i in 0...Instances.FIELDS) {
					own.push(device.createBuffer({size: instances.capacity * Instances.stride(i), usage: Vertex}));
					device.writeBuffer(own[i], 0, instances.fields[i].sub(0, length * Instances.stride(i)));
					bytes += length * Instances.stride(i);
				}
			} else
				for (i in 0...Instances.FIELDS) {
					// After a removal, the changed range can end past the group, so it is cut to the group's length.
					var high = group.high[set][i] < length ? group.high[set][i] : length;
					var low = group.low[set][i];
					if (low >= high)
						continue;
					var at = low * Instances.stride(i), size = (high - low) * Instances.stride(i);
					device.writeBuffer(own[i], at, instances.fields[i].sub(at, size));
					bytes += size;
				}
			group.settle(set);
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
		var on = view.on(plane != null ? plane : flat, clip != null ? clip : open, set, device);
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
		// Shadows draw first, so that no shadow covers a sprite.
		drawGroups(view, pass, pipeline, true);
		drawGroups(view, pass, pipeline, false);
		for (run in draw.runs)
			if (run.layer & camera.layers != 0)
				drawRange(view, pass, pipeline, run.plane, run.clip, run.texture != null ? run.texture : white, buffers[set], run.start, run.count);
	}

	/** Retires the GPU textures of the textures that closed or changed before this frame, and their bind groups. **/
	public function release():Void {
		var released = Texture.release(gpu);
		if (released.length > 0)
			for (view in views)
				view.forget(released, gpu);
	}

	// Draws the sprite groups in the camera's layers that hold shadows, or the groups that do not.
	function drawGroups(view:View, pass:RenderPass, pipeline:RenderPipeline, shadows:Bool):Void
		for (group in sprites.groups)
			if (group.shadows == shadows && group.layer & view.camera.layers != 0 && group.instances.length > 0)
				drawRange(view, pass, pipeline, group.plane, group.clip, group.texture, group.buffers[set], 0, group.instances.length);

	// Draws `count` instances of `source` from index `start`, on `plane` inside `clip`, with `image`.
	function drawRange(view:View, pass:RenderPass, pipeline:RenderPipeline, plane:Null<Plane>, clip:Null<Clip>, image:Texture, source:Array<Buffer>,
			start:Int, count:Int):Void {
		// Textures closed before their upload draw nothing.
		if (image.upload(device) == null)
			return;
		var shared = Shader.PARAMS_GROUP == Shader.TEXTURE_image_GROUP;
		var on = view.on(plane != null ? plane : flat, clip != null ? clip : open, set, device);
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
			pass.setVertexBuffer(i, source[i], start * Instances.stride(i));
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
		var field = (location:Int, field:Int) -> ({
			stride: Instances.stride(field),
			perInstance: true,
			attributes: [{location: location, format: Instances.packed(field) ? Unorm8x4 : Float32x4, offset: 0}]
		} : hxn.gpu.Descriptors.VertexBufferLayout);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: format,
			topology: TriangleStrip,
			blend: hxn.gpu.Blend.alpha,
			// Later content at the same depth draws over earlier content, as without depth.
			depth: depth ? {format: Depth32Float, compare: LessEqual} : null,
			vertexBuffers: [
				field(Shader.INPUT_rect, Instances.RECT),
				field(Shader.INPUT_uv, Instances.UV),
				field(Shader.INPUT_color, Instances.COLOR),
				field(Shader.INPUT_xform, Instances.XFORM),
				field(Shader.INPUT_shape, Instances.SHAPE),
				field(Shader.INPUT_radius, Instances.RADIUS),
				field(Shader.INPUT_border, Instances.BORDER)
			]
		});
		pipelines.set(key, pipeline);
		return pipeline;
	}
}

/** Each view holds what one camera needs to draw: its pass, and one plane view for each plane, clip and set of buffers. **/
private class View {
	public final camera:Camera;
	public var pass:Pass;
	final planes = [for (_ in 0...Renderer.SETS) new ObjectMap<Plane, ObjectMap<Clip, PlaneView>>()];

	public function new(camera:Camera)
		this.camera = camera;

	/** Retires and removes the bind groups of `textures` in every plane view. **/
	public function forget(textures:Array<Texture>, gpu:Gpu):Void
		for (sets in planes)
			for (clips in sets)
				for (on in clips)
					for (t in textures) {
						var group = on.groups.get(t);
						if (group != null) {
							gpu.retire(group);
							on.groups.remove(t);
						}
					}

	/** Returns the plane view for `plane` and `clip` in buffer set `set`, and makes it on first use. **/
	public function on(plane:Plane, clip:Clip, set:Int, device:GpuDevice):PlaneView {
		var clips = planes[set].get(plane);
		if (clips == null) {
			clips = new ObjectMap();
			planes[set].set(plane, clips);
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
	// Holds the count of cameras shown when the renderer last wrote the uniforms.
	public var shown = -1;
	public var params:Null<BindGroup>;
	public final groups = new ObjectMap<Texture, BindGroup>();

	public function new(uniforms:Buffer)
		this.uniforms = uniforms;
}
