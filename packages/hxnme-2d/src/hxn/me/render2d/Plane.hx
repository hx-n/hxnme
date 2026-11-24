package hxn.me.render2d;

/**
	`Plane` places 2D content in the 3D world. Content drawn on a plane lies in
	the plane's own XY plane. The plane maps that content into the world in
	three steps: it scales it by `scale`, turns it by the quaternion `rx`, `ry`,
	`rz`, `rw`, and moves it to `x`, `y`, `z`.
**/
class Plane {
	public var x = 0.0;
	public var y = 0.0;
	public var z = 0.0;
	public var rx = 0.0;
	public var ry = 0.0;
	public var rz = 0.0;
	public var rw = 1.0;
	public var scale = 1.0;

	public function new() {}

	/** Turns the plane by `angle` radians about the axis `ax`, `ay`, `az`, which must have length 1. **/
	public function rotate(angle:Float, ax:Float, ay:Float, az:Float):Void {
		var s = Math.sin(angle / 2);
		rx = ax * s;
		ry = ay * s;
		rz = az * s;
		rw = Math.cos(angle / 2);
	}

	/** Writes the matrix that maps the plane's coordinates to the world into the 16 floats of `out`, column after column. **/
	public function writeMatrix(out:Array<Float>):Void {
		var xx = rx * rx, yy = ry * ry, zz = rz * rz;
		var xy = rx * ry, xz = rx * rz, yz = ry * rz;
		var wx = rw * rx, wy = rw * ry, wz = rw * rz;
		out[0] = (1 - 2 * (yy + zz)) * scale;
		out[1] = 2 * (xy + wz) * scale;
		out[2] = 2 * (xz - wy) * scale;
		out[3] = 0;
		out[4] = 2 * (xy - wz) * scale;
		out[5] = (1 - 2 * (xx + zz)) * scale;
		out[6] = 2 * (yz + wx) * scale;
		out[7] = 0;
		out[8] = 2 * (xz + wy) * scale;
		out[9] = 2 * (yz - wx) * scale;
		out[10] = (1 - 2 * (xx + yy)) * scale;
		out[11] = 0;
		out[12] = x;
		out[13] = y;
		out[14] = z;
		out[15] = 1;
	}
}
