package hxn.me.gpu;

import hxn.gpu.Descriptors.Color;
import hxn.gpu.GpuDevice;
import hxn.gpu.GpuSurface;
import hxn.gpu.Texture;
import hxn.gpu.TextureFormat;

/**
	`Gpu` is the resource that holds the app's GPU device. The plugin opens the
	device on the app's window in the first frame. Opening the device takes
	some frames. Until it is open, `device` is null and the plugin draws no
	frame. In each frame that the plugin draws, `frame` is the texture of the
	window's next frame, from `Begin` to the end of `Render`, and the passes in
	`graph` draw into it.
**/
class Gpu {
	/** The device, or null until it opens. **/
	public var device(default, null):Null<GpuDevice>;

	/** The surface that shows frames in the window, or null until the device opens. **/
	public var surface(default, null):Null<GpuSurface>;

	/** The texture of the frame that the plugin draws now, or null when it draws no frame. **/
	public var frame(default, null):Null<Texture>;

	/** The texture format of the frames. Render pipelines that draw into the frame use it. **/
	public var format(default, null):TextureFormat = Rgba8Unorm;

	/** The color that the first pass of each frame clears the frame to. **/
	public var clear:Color = {r: 0, g: 0, b: 0, a: 1};

	/** The passes that draw each frame. **/
	public final graph = new FrameGraph();

	/** The number of frames that the plugin presented. **/
	public var presented(default, null) = 0;

	/** The reason that the device did not open, or null. **/
	public var failure(default, null):Null<String>;

	@:allow(hxn.me.gpu.GpuPlugin) var opening = false;

	public function new() {}

	/** Returns true when the device is open. Make pipelines and buffers only after that. **/
	public inline function ready():Bool
		return device != null;

	@:allow(hxn.me.gpu.GpuPlugin) function opened(device:GpuDevice, surface:GpuSurface):Void {
		this.device = device;
		this.surface = surface;
		format = surface.preferredFormat();
	}

	@:allow(hxn.me.gpu.GpuPlugin) function failed(message:String):Void
		failure = message;

	@:allow(hxn.me.gpu.GpuPlugin) function take(texture:Null<Texture>):Void
		frame = texture;

	@:allow(hxn.me.gpu.GpuPlugin) function shown():Void {
		frame = null;
		presented++;
	}
}
