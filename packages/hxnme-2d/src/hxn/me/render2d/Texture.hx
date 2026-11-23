package hxn.me.render2d;

import haxe.io.Bytes;
import hxn.gpu.GpuDevice;
import hxn.gpu.Texture as GpuTexture;

/**
	`Texture` is an image that sprites draw. The app makes it from RGBA
	pixels, 4 bytes for each pixel and rows top first, at any time. The 2D
	renderer uploads it to the GPU in the first frame after the device opens,
	and then releases the pixels.
**/
class Texture {
	public final width:Int;
	public final height:Int;

	/** The GPU texture, or null until the renderer uploads it. **/
	public var texture(default, null):Null<GpuTexture>;

	var pixels:Null<Bytes>;

	public function new(width:Int, height:Int, pixels:Bytes) {
		if (pixels.length < width * height * 4)
			throw 'a ${width}x$height RGBA image takes ${width * height * 4} bytes, not ${pixels.length}';
		this.width = width;
		this.height = height;
		this.pixels = pixels;
	}

	/** Returns a texture of one pixel in `color` (0xRRGGBB), at `alpha`. **/
	public static function solid(color:Int, alpha = 1.0):Texture {
		var pixels = Bytes.alloc(4);
		pixels.set(0, (color >> 16) & 0xFF);
		pixels.set(1, (color >> 8) & 0xFF);
		pixels.set(2, color & 0xFF);
		pixels.set(3, Math.round(alpha * 255));
		return new Texture(1, 1, pixels);
	}

	@:allow(hxn.me.render2d) function upload(device:GpuDevice):GpuTexture {
		if (texture == null) {
			texture = device.createTexture({width: width, height: height, format: Rgba8Unorm, usage: Sampled});
			device.writeTexture(texture, pixels);
			pixels = null;
		}
		return texture;
	}
}
