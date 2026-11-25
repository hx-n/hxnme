package hxn.me.render2d;

import haxe.io.Bytes;
import hxn.gpu.GpuDevice;
import hxn.gpu.Texture as GpuTexture;
import hxn.gpu.TextureFormat;

/**
	`Texture` holds an image that sprites draw. The app can make it at any
	time, from RGBA pixels with 4 bytes for each pixel and the top row first.
	In the first frame after the GPU device opens, the 2D renderer uploads it
	and releases the pixels.
**/
@:assetType(hxn.me.render2d.RenderAssets.texture)
class Texture {
	public var width(default, null):Int;
	public var height(default, null):Int;

	/** `texture` holds the GPU texture, or null until the renderer uploads it. **/
	public var texture(default, null):Null<GpuTexture>;

	/** `closed` is true after a call to `close`. **/
	public var closed(default, null) = false;

	// Holds the GPU texture that `adopt` replaced, until the start of the next frame.
	var replaced:Null<GpuTexture>;

	var format:TextureFormat;
	var pixels:Null<Bytes>;

	// Holds the textures that closed or that `adopt` changed. `release` closes their GPU textures at the start of the next frame, because draws earlier in the frame still use them.
	static final retired:Array<Texture> = [];

	// Holds the writes to parts of the texture that wait for the next upload.
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

	/**
		Closes the texture. What was drawn with it earlier in the frame still
		shows, and its GPU texture is released at the start of the next frame.
		The texture draws nothing after this.
	**/
	@:allow(hxn.me.render2d) function close():Void {
		if (closed)
			return;
		closed = true;
		pixels = null;
		patches.resize(0);
		retired.push(this);
	}

	// Gives this texture the image of `by`, a texture that nothing draws yet. Everything that draws this texture then shows that image.
	@:allow(hxn.me.render2d) function adopt(by:Texture):Void {
		width = by.width;
		height = by.height;
		pixels = by.pixels;
		format = by.format;
		patches = [];
		if (texture == null)
			return;
		if (replaced != null)
			replaced.close();
		replaced = texture;
		texture = null;
		retired.push(this);
	}

	// Releases the GPU textures that closed or were replaced before this frame, and returns their textures.
	@:allow(hxn.me.render2d) static function release():Array<Texture> {
		var released = retired.copy();
		for (t in released) {
			if (t.closed && t.texture != null) {
				t.texture.close();
				t.texture = null;
			}
			if (t.replaced != null) {
				t.replaced.close();
				t.replaced = null;
			}
		}
		retired.resize(0);
		return released;
	}

	// Returns the GPU texture, made and uploaded on first use, or null for a texture closed before it was uploaded.
	@:allow(hxn.me.render2d) function upload(device:GpuDevice):Null<GpuTexture> {
		if (closed)
			return texture;
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
