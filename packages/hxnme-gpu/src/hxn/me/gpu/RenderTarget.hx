package hxn.me.gpu;

import hxn.gpu.GpuDevice;
import hxn.gpu.Texture;
import hxn.gpu.TextureFormat;

/**
	`RenderTarget` holds a texture that passes draw into, and that later
	passes sample or the app reads back. The texture is `width` by `height`
	pixels, or `scale` times the size of the frame. When its size comes from
	the frame, it changes with the window. The frame graph makes the texture
	after the device opens, and makes it again when its size changes.
**/
class RenderTarget {
	public final format:TextureFormat;
	public final width:Int;
	public final height:Int;

	/** The size as a part of the frame's size, or 0 when the size is `width` by `height`. **/
	public final scale:Float;

	/** The texture, or null until the frame graph makes it. **/
	public var texture(default, null):Null<Texture>;

	public function new(width:Int, height:Int, ?format:TextureFormat, scale = 0.0) {
		this.width = width;
		this.height = height;
		this.format = format != null ? format : Rgba8Unorm;
		this.scale = scale;
	}

	/** Returns a target whose size is `scale` times the size of the frame. **/
	public static function ofFrame(scale:Float, ?format:TextureFormat):RenderTarget
		return new RenderTarget(0, 0, format, scale);

	@:allow(hxn.me.gpu.FrameGraph) function resolve(device:GpuDevice, frame:Texture):Texture {
		var w = scale > 0 ? Std.int(Math.max(1, Math.round(frame.width * scale))) : width;
		var h = scale > 0 ? Std.int(Math.max(1, Math.round(frame.height * scale))) : height;
		if (texture != null && (texture.width != w || texture.height != h)) {
			texture.close();
			texture = null;
		}
		if (texture == null)
			texture = device.createTexture({width: w, height: h, format: format, usage: RenderTarget | Sampled});
		return texture;
	}
}
