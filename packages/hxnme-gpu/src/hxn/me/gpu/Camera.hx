package hxn.me.gpu;

import hxn.gpu.Descriptors.Color;

/**
	`Camera` sets what part of the world a renderer shows, for 2D and 3D
	alike. The world has y up. The camera sits at `x`, `y`, `z`, turned by the
	quaternion `rx`, `ry`, `rz`, `rw`, and looks along its -z. `projection` maps what it
	sees onto its view. The view is the part of the target that `viewport`
	sets, as parts of the target's width and height. The camera draws into
	`target`, or into the frame when `target` is null.

	Each renderer draws its content once for each enabled camera, in the
	order of `order`, and only the content whose layer bits share a bit with
	`layers`.
**/
class Camera {
	public var x = 0.0;
	public var y = 0.0;
	public var z = 0.0;

	/** The rotation as a quaternion: `rx`, `ry`, `rz`, `rw`. The default turns nothing. **/
	public var rx = 0.0;
	public var ry = 0.0;
	public var rz = 0.0;
	public var rw = 1.0;

	public var projection:Projection = Orthographic(0, -1000, 1000);

	/** The part of the target that the view covers: left, top, width and height, each from 0 to 1. **/
	public var viewport = {x: 0.0, y: 0.0, width: 1.0, height: 1.0};

	/** The render target to draw into, or null for the frame. Set it before the first frame. **/
	public var target:Null<RenderTarget>;

	/** The color that the camera's first pass clears its render target to, or null to keep what it holds. **/
	public var clear:Null<Color> = {r: 0, g: 0, b: 0, a: 0};

	/** Cameras draw from the lowest `order` up. **/
	public var order = 0;

	/** The layers that the camera shows, as bits. The default shows layer 1. **/
	public var layers = 1;

	/**
		When true, renderers test and write depth for what the camera shows, so
		nearer content hides farther content in any drawing order, such as
		planes that intersect. When false, later content draws over earlier
		content.
	**/
	public var depth = false;

	public var enabled = true;

	public function new() {}

	/** Turns the camera by `angle` radians about the z axis, as a 2D camera turns. **/
	public function roll(angle:Float):Void {
		rx = 0;
		ry = 0;
		rz = Math.sin(angle / 2);
		rw = Math.cos(angle / 2);
	}

	/** Returns true when the view has y down, as with `Screen`. **/
	public inline function yDown():Bool
		return projection.match(Screen);

	/**
		Writes the matrix that maps world points to clip space, for a view
		`width` by `height` logical pixels, into the 16 floats of `out`, column
		after column.
	**/
	public function writeMatrix(width:Float, height:Float, out:Array<Float>):Void {
		var m = switch projection {
			case Screen:
				[2 / width, 0, 0, 0, 0, -2 / height, 0, 0, 0, 0, 0, 0, -2 * x / width - 1, 2 * y / height + 1, 0.5, 1];
			case Orthographic(h, near, far):
				var viewHeight = h > 0 ? h : height;
				var viewWidth = viewHeight * width / height;
				multiply([2 / viewWidth, 0, 0, 0, 0, 2 / viewHeight, 0, 0, 0, 0, -1 / (far - near), 0, 0, 0, -near / (far - near), 1], view());
			case Perspective(fovY, near, far):
				var f = 1 / Math.tan(fovY / 2);
				multiply([f * height / width, 0, 0, 0, 0, f, 0, 0, 0, 0, far / (near - far), -1, 0, 0, near * far / (near - far), 0], view());
		}
		for (i in 0...16)
			out[i] = m[i];
	}

	// Returns the world-to-camera matrix, column-major. It moves the camera
	// to the origin, then applies the inverse rotation.
	function view():Array<Float> {
		var xx = rx * rx, yy = ry * ry, zz = rz * rz;
		var xy = rx * ry, xz = rx * rz, yz = ry * rz;
		var wx = rw * rx, wy = rw * ry, wz = rw * rz;
		// `r` holds the rotation's rows, which are the columns of its
		// inverse, column after column.
		var r = [
			1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy),
			2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx),
			2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)
		];
		var tx = -(r[0] * x + r[3] * y + r[6] * z);
		var ty = -(r[1] * x + r[4] * y + r[7] * z);
		var tz = -(r[2] * x + r[5] * y + r[8] * z);
		return [r[0], r[1], r[2], 0, r[3], r[4], r[5], 0, r[6], r[7], r[8], 0, tx, ty, tz, 1];
	}

	static function multiply(a:Array<Float>, b:Array<Float>):Array<Float> {
		var out = [for (_ in 0...16) 0.0];
		for (col in 0...4)
			for (row in 0...4) {
				var sum = 0.0;
				for (k in 0...4)
					sum += a[k * 4 + row] * b[col * 4 + k];
				out[col * 4 + row] = sum;
			}
		return out;
	}
}
