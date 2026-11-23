package hxn.me.gpu;

import hxn.gpu.Descriptors.Color;
import hxn.gpu.RenderPass;
import hxn.gpu.Texture;

/**
	Each pass draws into the frame, or into `target` when `target` is not
	null. In each frame, the graph calls `draw` with the recording pass and
	the texture that the pass draws into, and `draw` records the commands.
	The first pass into the frame clears it to `Gpu.clear`, unless the pass
	sets `clear`. Later passes into the frame draw over what is there. Each
	pass into a render target clears the target to `clear`, or to transparent
	black when `clear` is null. With `keep`, the pass draws over what the
	target holds.
**/
class Pass {
	public final name:String;

	/** The render target that the pass draws into, or null for the frame. **/
	public final target:Null<RenderTarget>;

	public final draw:(pass:RenderPass, into:Texture) -> Void;

	/**
		The graph runs passes from the lowest `order` up. Passes with the same
		order run in the order that they were added.
	**/
	public var order:Int;

	/** The graph runs the pass only while this is true. **/
	public var enabled = true;

	/** The color that the pass clears its target to, or null. **/
	public var clear:Null<Color>;

	/** When true, the pass draws over what its render target holds, and does not clear it. **/
	public var keep = false;

	public function new(name:String, target:Null<RenderTarget>, draw:(pass:RenderPass, into:Texture) -> Void, order = 0) {
		this.name = name;
		this.target = target;
		this.draw = draw;
		this.order = order;
	}
}
