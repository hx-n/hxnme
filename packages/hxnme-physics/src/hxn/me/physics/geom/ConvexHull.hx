package hxn.me.physics.geom;

import hxn.me.math.Vec3;

private class ProjectedVertex {
	public var index:Int;
	public var x:Float;
	public var y:Float;

	public function new(index:Int, x:Float, y:Float) {
		this.index = index;
		this.x = x;
		this.y = y;
	}
}

/**
 * Builds outward triangles from an unordered set of convex hull vertices.
 * The arithmetic is in 64-bit floats: plane tests must agree for every
 * triple of points on one face, which 32-bit vectors do not guarantee.
 */
class ConvexHull {
	static inline function cross2(a:ProjectedVertex, b:ProjectedVertex, c:ProjectedVertex):Float {
		return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
	}

	public static function triangles(points:Array<Vec3>):Array<Int> {
		if (points == null || points.length < 4)
			throw 'Hull needs at least four vertices';
		var count = points.length;
		var px = new Array<Float>(),
			py = new Array<Float>(),
			pz = new Array<Float>();
		var minX = Math.POSITIVE_INFINITY,
			minY = Math.POSITIVE_INFINITY,
			minZ = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY,
			maxY = Math.NEGATIVE_INFINITY,
			maxZ = Math.NEGATIVE_INFINITY;
		for (p in points) {
			if (p == null || !Math.isFinite(p.x) || !Math.isFinite(p.y) || !Math.isFinite(p.z))
				throw 'Hull vertices must be finite';
			px.push(p.x);
			py.push(p.y);
			pz.push(p.z);
			minX = Math.min(minX, p.x);
			minY = Math.min(minY, p.y);
			minZ = Math.min(minZ, p.z);
			maxX = Math.max(maxX, p.x);
			maxY = Math.max(maxY, p.y);
			maxZ = Math.max(maxZ, p.z);
		}
		var scale = Math.max(maxX - minX, Math.max(maxY - minY, maxZ - minZ));
		if (scale <= 0.0)
			throw 'Hull has zero volume';
		var eps = scale * 1e-6;
		for (i in 0...count)
			for (j in i + 1...count) {
				var dx = px[i] - px[j], dy = py[i] - py[j], dz = pz[i] - pz[j];
				if (dx * dx + dy * dy + dz * dz <= eps * eps)
					throw 'Hull has duplicate vertices';
			}

		// Faces seen so far, by the points on them, so each face is triangulated once.
		var faces = new Map<String, Bool>();
		var result:Array<Int> = [];
		for (i in 0...count)
			for (j in i + 1...count)
				for (k in j + 1...count) {
					var ex = px[j] - px[i],
						ey = py[j] - py[i],
						ez = pz[j] - pz[i];
					var fx = px[k] - px[i],
						fy = py[k] - py[i],
						fz = pz[k] - pz[i];
					var nx = ey * fz - ez * fy,
						ny = ez * fx - ex * fz,
						nz = ex * fy - ey * fx;
					var len = Math.sqrt(nx * nx + ny * ny + nz * nz);
					if (len <= eps * eps)
						continue;
					nx /= len;
					ny /= len;
					nz /= len;
					var positive = false, negative = false;
					for (v in 0...count) {
						var side = nx * (px[v] - px[i]) + ny * (py[v] - py[i]) + nz * (pz[v] - pz[i]);
						if (side > eps)
							positive = true;
						if (side < -eps)
							negative = true;
						if (positive && negative)
							break;
					}
					if ((positive && negative) || (!positive && !negative))
						continue;
					if (positive) {
						nx = -nx;
						ny = -ny;
						nz = -nz;
					}
					var distance = nx * px[i] + ny * py[i] + nz * pz[i];
					var face:Array<Int> = [];
					for (v in 0...count)
						if (Math.abs(nx * px[v] + ny * py[v] + nz * pz[v] - distance) <= eps * 2.0)
							face.push(v);
					var key = face.join(",");
					if (faces.exists(key))
						continue;
					faces.set(key, true);

					// The face's points in its own plane, ordered around it by a monotone chain.
					var o = face[0];
					var ux = px[face[1]] - px[o],
						uy = py[face[1]] - py[o],
						uz = pz[face[1]] - pz[o];
					var ul = Math.sqrt(ux * ux + uy * uy + uz * uz);
					ux /= ul;
					uy /= ul;
					uz /= ul;
					var vx = ny * uz - nz * uy,
						vy = nz * ux - nx * uz,
						vz = nx * uy - ny * ux;
					var projected:Array<ProjectedVertex> = [];
					for (index in face) {
						var dx = px[index] - px[o],
							dy = py[index] - py[o],
							dz = pz[index] - pz[o];
						projected.push(new ProjectedVertex(index, dx * ux + dy * uy + dz * uz, dx * vx + dy * vy + dz * vz));
					}
					projected.sort((a, b) -> a.x < b.x ? -1 : (a.x > b.x ? 1 : (a.y < b.y ? -1 : (a.y > b.y ? 1 : 0))));
					// Points within rounding of the outline's edges are left out, so no sliver triangle can turn the wrong way.
					var straight = eps * scale;
					var lower:Array<ProjectedVertex> = [];
					for (p in projected) {
						while (lower.length >= 2 && cross2(lower[lower.length - 2], lower[lower.length - 1], p) <= straight)
							lower.pop();
						lower.push(p);
					}
					var upper:Array<ProjectedVertex> = [];
					var reverse = projected.copy();
					reverse.reverse();
					for (p in reverse) {
						while (upper.length >= 2 && cross2(upper[upper.length - 2], upper[upper.length - 1], p) <= straight)
							upper.pop();
						upper.push(p);
					}
					var ring:Array<ProjectedVertex> = [];
					for (h in 0...lower.length - 1)
						ring.push(lower[h]);
					for (h in 0...upper.length - 1)
						ring.push(upper[h]);
					if (ring.length < 3)
						continue;
					for (h in 1...ring.length - 1) {
						var a = ring[0].index,
							b = ring[h].index,
							c = ring[h + 1].index;
						// Each triangle must face the way its face does and have area.
						var tx = (py[b] - py[a]) * (pz[c] - pz[a]) - (pz[b] - pz[a]) * (py[c] - py[a]);
						var ty = (pz[b] - pz[a]) * (px[c] - px[a]) - (px[b] - px[a]) * (pz[c] - pz[a]);
						var tz = (px[b] - px[a]) * (py[c] - py[a]) - (py[b] - py[a]) * (px[c] - px[a]);
						if (tx * nx + ty * ny + tz * nz <= straight)
							continue;
						result.push(a);
						result.push(b);
						result.push(c);
					}
				}
		if (result.length < 12)
			throw 'Hull vertices must span a 3D volume';
		return result;
	}
}
