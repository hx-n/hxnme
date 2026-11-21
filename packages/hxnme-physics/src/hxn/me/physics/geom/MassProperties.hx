package hxn.me.physics.geom;

import hxn.me.math.Vec3;

/** Mass, centroid, and inertia about the shape's local origin. */
class MassProperties {
	public var mass:Single = 0.0;
	public var ixx:Single = 0.0;
	public var iyy:Single = 0.0;
	public var izz:Single = 0.0;
	public var centroidX:Single = 0.0;
	public var centroidY:Single = 0.0;
	public var centroidZ:Single = 0.0;
	public var ixy:Single = 0.0;
	public var ixz:Single = 0.0;
	public var iyz:Single = 0.0;

	public function new() {}

	static function fromMoments(m:Float, sx:Float, sy:Float, sz:Float, xx:Float, yy:Float, zz:Float, xy:Float, xz:Float, yz:Float):MassProperties {
		var result = new MassProperties();
		if (m <= 0.0)
			return result;
		result.mass = m;
		result.centroidX = sx / m;
		result.centroidY = sy / m;
		result.centroidZ = sz / m;
		result.ixx = yy + zz;
		result.iyy = xx + zz;
		result.izz = xx + yy;
		result.ixy = -xy;
		result.ixz = -xz;
		result.iyz = -yz;
		return result;
	}

	/** Point skin is a disk when planar and a spherocylinder when extruded. */
	public static function point(radius:Single, depth:Single, localZ:Single, density:Single):MassProperties {
		if (radius <= 0.0 || depth < 0.0 || density <= 0.0)
			return new MassProperties();
		if (depth > 0.0)
			return roundedPlate(0.0, 0.0, 0.0, 0.0, radius, depth, localZ, density);
		var m = Math.PI * radius * radius * density;
		var radial = m * radius * radius / 4.0;
		return fromMoments(m, 0.0, 0.0, m * localZ, radial, radial, m * localZ * localZ, 0.0, 0.0, 0.0);
	}

	/** Polygon skin is collision-only; mass uses the core prism. */
	public static function polygon(pool:VertexPool, offset:Int, count:Int, depth:Single, localZ:Single, density:Single):MassProperties {
		var result = new MassProperties();
		if (count < 3 || density <= 0.0 || depth < 0.0)
			return result;

		var twiceArea:Float = 0.0;
		var xx:Float = 0.0;
		var yy:Float = 0.0;
		var xy:Float = 0.0;
		var cx:Float = 0.0;
		var cy:Float = 0.0;
		for (i in 0...count) {
			var j = (i + 1) == count ? 0 : i + 1;
			var x0:Float = pool.vx[offset + i], y0:Float = pool.vy[offset + i];
			var x1:Float = pool.vx[offset + j], y1:Float = pool.vy[offset + j];
			var cross = x0 * y1 - x1 * y0;
			twiceArea += cross;
			cx += (x0 + x1) * cross;
			cy += (y0 + y1) * cross;
			xx += cross * (x0 * x0 + x0 * x1 + x1 * x1);
			yy += cross * (y0 * y0 + y0 * y1 + y1 * y1);
			xy += cross * (2.0 * x0 * y0 + x0 * y1 + x1 * y0 + 2.0 * x1 * y1);
		}
		if (Math.abs(twiceArea) < 1e-12)
			return result;
		var sign = twiceArea < 0.0 ? -1.0 : 1.0;
		var thickness = depth > 0.0 ? depth : 1.0;
		var scale = density * thickness;
		result.mass = 0.5 * Math.abs(twiceArea) * scale;
		result.centroidX = cx / (3.0 * twiceArea);
		result.centroidY = cy / (3.0 * twiceArea);
		result.centroidZ = localZ;
		var intX2 = sign * xx * scale / 12.0;
		var intY2 = sign * yy * scale / 12.0;
		var transverse = result.mass * (localZ * localZ + depth * depth / 12.0);
		result.ixx = intY2 + transverse;
		result.iyy = intX2 + transverse;
		result.izz = intX2 + intY2;
		result.ixy = -sign * xy * scale / 24.0;
		result.ixz = -result.mass * result.centroidX * localZ;
		result.iyz = -result.mass * result.centroidY * localZ;
		return result;
	}

	/** Planar capsule or 3D round-ended plate. */
	public static function capsule(pool:VertexPool, offset:Int, radius:Single, depth:Single, localZ:Single, density:Single):MassProperties {
		var result = new MassProperties();
		if (radius <= 0.0 || density <= 0.0 || depth < 0.0)
			return result;
		var ax:Float = pool.vx[offset], ay:Float = pool.vy[offset];
		var bx:Float = pool.vx[offset + 1], by:Float = pool.vy[offset + 1];
		if (depth > 0.0)
			return roundedPlate(ax, ay, bx, by, radius, depth, localZ, density);
		var dx = bx - ax, dy = by - ay;
		var length = Math.sqrt(dx * dx + dy * dy);
		var ux = length > 0.0 ? dx / length : 1.0;
		var uy = length > 0.0 ? dy / length : 0.0;
		var cx = (ax + bx) * 0.5, cy = (ay + by) * 0.5;
		var scale = density;
		var rectMass = 2.0 * radius * length * scale;
		var capMass = 0.5 * Math.PI * radius * radius * scale;
		result.mass = rectMass + 2.0 * capMass;
		result.centroidX = cx;
		result.centroidY = cy;
		result.centroidZ = localZ;
		var diskQuarterMoment = Math.PI * radius * radius * radius * radius * scale / 8.0;
		var capCentroid = 4.0 * radius / (3.0 * Math.PI);
		var along = rectMass * radius * radius / 3.0 + 2.0 * diskQuarterMoment;
		var across = rectMass * length * length / 12.0 + 2.0 * (capMass * length * length / 4.0 + capMass * length * capCentroid + diskQuarterMoment);
		var intX2 = across * ux * ux + along * uy * uy + result.mass * cx * cx;
		var intY2 = across * uy * uy + along * ux * ux + result.mass * cy * cy;
		var transverse = result.mass * localZ * localZ;
		result.ixx = intY2 + transverse;
		result.iyy = intX2 + transverse;
		result.izz = intX2 + intY2;
		result.ixy = -((across - along) * ux * uy + result.mass * cx * cy);
		result.ixz = -result.mass * cx * localZ;
		result.iyz = -result.mass * cy * localZ;
		return result;
	}

	/** Minkowski sum of an XY segment, a Z interval, and a radius sphere. */
	static function roundedPlate(ax:Float, ay:Float, bx:Float, by:Float, radius:Float, depth:Float, localZ:Float, density:Float):MassProperties {
		var dx = bx - ax, dy = by - ay;
		var length = Math.sqrt(dx * dx + dy * dy);
		var ux = length > 0.0 ? dx / length : 1.0;
		var uy = length > 0.0 ? dy / length : 0.0;
		var cx = (ax + bx) * 0.5, cy = (ay + by) * 0.5;
		var r2 = radius * radius;
		var prism = density * 2.0 * radius * length * depth;
		var endEdges = density * Math.PI * r2 * depth;
		var topEdges = density * Math.PI * r2 * length;
		var corners = density * 4.0 * Math.PI * r2 * radius / 3.0;
		var m = prism + endEdges + topEdges + corners;
		var capOffset = 4.0 * radius / (3.0 * Math.PI);
		var u2 = prism * length * length / 12.0
			+ endEdges * (length * length / 4.0 + length * capOffset + r2 / 4.0)
			+ topEdges * length * length / 12.0
			+ corners * (length * length / 4.0 + 3.0 * length * radius / 8.0 + r2 / 5.0);
		var v2 = prism * r2 / 3.0 + (endEdges + topEdges) * r2 / 4.0 + corners * r2 / 5.0;
		var z2 = prism * depth * depth / 12.0
			+ topEdges * (depth * depth / 4.0 + depth * capOffset + r2 / 4.0)
			+ endEdges * depth * depth / 12.0
			+ corners * (depth * depth / 4.0 + 3.0 * depth * radius / 8.0 + r2 / 5.0);
		var xx = u2 * ux * ux + v2 * uy * uy + m * cx * cx;
		var yy = u2 * uy * uy + v2 * ux * ux + m * cy * cy;
		var xy = (u2 - v2) * ux * uy + m * cx * cy;
		return fromMoments(m, m * cx, m * cy, m * localZ, xx, yy, z2 + m * localZ * localZ, xy, m * cx * localZ, m * cy * localZ);
	}

	/** Hull skin is collision-only; integrate the outward core surface. */
	public static function hull(pool:VertexPool, offset:Int, count:Int, localZ:Single, density:Single):MassProperties {
		if (density <= 0.0)
			return new MassProperties();
		var points:Array<Vec3> = [];
		for (i in 0...count)
			points.push(new Vec3(pool.vx[offset + i], pool.vy[offset + i], pool.vz[offset + i] + localZ));
		var faces = ConvexHull.triangles(points);
		var origin = points[0];
		var volume:Float = 0.0, sx:Float = 0.0, sy:Float = 0.0, sz:Float = 0.0;
		var xx:Float = 0.0, yy:Float = 0.0, zz:Float = 0.0;
		var xy:Float = 0.0, xz:Float = 0.0, yz:Float = 0.0;
		for (f in 0...Std.int(faces.length / 3)) {
			var a = Vec3.sub(points[faces[f * 3]], origin);
			var b = Vec3.sub(points[faces[f * 3 + 1]], origin);
			var c = Vec3.sub(points[faces[f * 3 + 2]], origin);
			var v = Vec3.dot(a, Vec3.cross(b, c)) / 6.0;
			volume += v;
			sx += v * (a.x + b.x + c.x) / 4.0;
			sy += v * (a.y + b.y + c.y) / 4.0;
			sz += v * (a.z + b.z + c.z) / 4.0;
			xx += v * (a.x * a.x + b.x * b.x + c.x * c.x + a.x * b.x + a.x * c.x + b.x * c.x) / 10.0;
			yy += v * (a.y * a.y + b.y * b.y + c.y * c.y + a.y * b.y + a.y * c.y + b.y * c.y) / 10.0;
			zz += v * (a.z * a.z + b.z * b.z + c.z * c.z + a.z * b.z + a.z * c.z + b.z * c.z) / 10.0;
			xy += v * (2.0 * (a.x * a.y + b.x * b.y + c.x * c.y) + a.x * b.y + a.y * b.x + a.x * c.y + a.y * c.x + b.x * c.y + b.y * c.x) / 20.0;
			xz += v * (2.0 * (a.x * a.z + b.x * b.z + c.x * c.z) + a.x * b.z + a.z * b.x + a.x * c.z + a.z * c.x + b.x * c.z + b.z * c.x) / 20.0;
			yz += v * (2.0 * (a.y * a.z + b.y * b.z + c.y * c.z) + a.y * b.z + a.z * b.y + a.y * c.z + a.z * c.y + b.y * c.z + b.z * c.y) / 20.0;
		}
		if (volume <= 0.0)
			throw 'Hull has zero or inconsistent volume';
		return fromMoments(volume * density, (sx + volume * origin.x) * density, (sy + volume * origin.y) * density, (sz + volume * origin.z) * density,
			(xx + 2.0 * origin.x * sx + volume * origin.x * origin.x) * density, (yy + 2.0 * origin.y * sy + volume * origin.y * origin.y) * density,
			(zz + 2.0 * origin.z * sz + volume * origin.z * origin.z) * density,
			(xy + origin.x * sy + origin.y * sx + volume * origin.x * origin.y) * density,
			(xz + origin.x * sz + origin.z * sx + volume * origin.x * origin.z) * density,
			(yz + origin.y * sz + origin.z * sy + volume * origin.y * origin.z) * density);
	}
}
