package hxn.me.gpu;

/**
	`Cameras` holds the app's cameras, as a resource. It starts with
	`main`, an orthographic camera that shows one world unit for each logical
	pixel, centered on the world's origin. Renderers draw once for each
	enabled camera, in the order of `Camera.order`.
**/
class Cameras {
	public final main = new Camera();
	final list:Array<Camera> = [];

	public function new() {
		list.push(main);
	}

	public function add(camera:Camera):Void {
		if (list.indexOf(camera) < 0)
			list.push(camera);
	}

	public function remove(camera:Camera):Void
		list.remove(camera);

	/** Returns the enabled cameras from the lowest `order` up. **/
	public function sorted():Array<Camera> {
		var out = [for (c in list) if (c.enabled) c];
		haxe.ds.ArraySort.sort(out, (a, b) -> a.order - b.order);
		return out;
	}

	public function iterator():Iterator<Camera>
		return list.iterator();
}
