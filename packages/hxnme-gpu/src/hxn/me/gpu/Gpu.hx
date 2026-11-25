package hxn.me.gpu;

import hxn.gpu.Descriptors.Color;
import hxn.gpu.GpuDevice;
import hxn.gpu.GpuSurface;
import hxn.gpu.Resource;
import hxn.gpu.Texture;
import hxn.gpu.TextureFormat;

/**
	`Gpu` holds the app's GPU device, as a resource. The plugin opens the
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

	// Holds the resources that close after the GPU finishes the next frame that the plugin presents.
	final retired:Array<Resource> = [];

	public function new() {}

	/** Returns true when the device is open. Make pipelines and buffers only after that. **/
	public inline function ready():Bool
		return device != null;

	/**
		Closes `resource` after the GPU finishes the frames that use it. Passes
		must not use it after the frame in progress. hxn-gpu closes a resource
		at once, even if the GPU still reads it for an earlier frame, so use
		this for every resource that frames used.
	**/
	public function retire(resource:Resource):Void
		retired.push(resource);

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
		if (retired.length == 0)
			return;
		var closing = retired.copy();
		retired.resize(0);
		function close()
			for (resource in closing)
				resource.close();
		device.completed().then(_ -> close(), _ -> close());
	}
}
