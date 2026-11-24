package hxn.me.render2d;

import haxe.io.Bytes;
import hxn.gpu.GpuDevice;
import hxn.gpu.Texture as GpuTexture;
import hxn.gpu.TextureFormat;

/**
	`Texture` is an image that sprites draw. The app makes it from RGBA
	pixels, 4 bytes for each pixel and rows top first, at any time. The 2D
	renderer uploads it to the GPU in the first frame after the device opens,
	and then releases the pixels.
**/
class Texture {
	public var width(default, null):Int;
	public var height(default, null):Int;

	/** The GPU texture, or null until the renderer uploads it. **/
	public var texture(default, null):Null<GpuTexture>;

	var format:TextureFormat;
	var pixels:Null<Bytes>;

	// Writes into part of the texture that wait for the next upload.
	var patches:Array<Patch>;

	public function new(width:Int, height:Int, pixels:Bytes) {
		this.width = width;
		this.height = height;
		this.pixels = check(width, height, pixels, 4);
		format = Rgba8Unorm;
		patches = [];
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

	/** Returns a texture with one byte of coverage for each pixel, which glyphs read from the red channel. **/
	@:allow(hxn.me.render2d) static function coverage(width:Int, height:Int, pixels:Bytes):Texture {
		// The constructor takes RGBA pixels, so this sets the fields itself.
		var made:Texture = Type.createEmptyInstance(Texture);
		made.width = width;
		made.height = height;
		made.pixels = check(width, height, pixels, 1);
		made.format = R8Unorm;
		made.patches = [];
		return made;
	}

	static function check(width:Int, height:Int, pixels:Bytes, size:Int):Bytes {
		if (pixels.length < width * height * size)
			throw 'a ${width}x$height image takes ${width * height * size} bytes, not ${pixels.length}';
		return pixels;
	}

	/**
		Writes `pixels` into the rectangle at `x`, `y`, `width` by `height`
		pixels, with `stride` bytes from the start of one row to the next. The
		write reaches the GPU at the next upload.
	**/
	@:allow(hxn.me.render2d) function write(x:Int, y:Int, width:Int, height:Int, pixels:Bytes, stride:Int):Void
		patches.push({x: x, y: y, width: width, height: height, pixels: pixels, stride: stride});

	/** Releases the GPU texture. The texture cannot draw after this. **/
	@:allow(hxn.me.render2d) function close():Void {
		if (texture != null)
			texture.close();
		texture = null;
		pixels = null;
		patches.resize(0);
	}

	@:allow(hxn.me.render2d) function upload(device:GpuDevice):GpuTexture {
		if (texture == null) {
			texture = device.createTexture({width: width, height: height, format: format, usage: Sampled});
			device.writeTexture(texture, pixels);
			pixels = null;
		}
		for (p in patches)
			device.writeTexture(texture, p.pixels, {x: p.x, y: p.y, width: p.width, height: p.height}, p.stride);
		patches.resize(0);
		return texture;
	}
}

private typedef Patch = {
	var x:Int;
	var y:Int;
	var width:Int;
	var height:Int;
	var pixels:Bytes;
	var stride:Int;
}
