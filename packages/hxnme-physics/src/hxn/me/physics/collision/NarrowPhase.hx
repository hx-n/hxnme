package hxn.me.physics.collision;

import hxn.Float32Buffer;
import hxn.Float64Buffer;
import hxn.Int32Buffer;
import hxn.me.math.Vec3;
import hxn.me.math.Quat;
import hxn.me.physics.geom.VertexPool;
import hxn.me.physics.geom.ShapeDef;
import hxn.me.physics.geom.ShapeDef.ShapeKind;
import hxn.me.physics.collision.ManifoldClipper;
import hxn.me.physics.collision.ManifoldClipper.ClipTopology;
import hxn.me.physics.collision.ManifoldClipper.ClipWorkspace;

class ContactManifoldPool {
	public var count:Int = 0;

	/** The most contacts the pool holds; more in one step are dropped. */
	public var maxContacts:Int;

	/** Contacts the storage holds now. It doubles toward `maxContacts` when a step needs more. */
	public var capacity(default, null):Int = 0;

	public var bodyA:Int32Buffer;
	public var bodyB:Int32Buffer;
	public var shapeA:Int32Buffer;
	public var shapeB:Int32Buffer;
	public var featureId:Int32Buffer;
	public var normalX:Float32Buffer;
	public var normalY:Float32Buffer;
	public var normalZ:Float32Buffer;
	public var pointX:Float32Buffer;
	public var pointY:Float32Buffer;
	public var pointZ:Float32Buffer;
	public var penetration:Float32Buffer;
	public var normalImpulse:Float32Buffer;
	public var tangentImpulse1:Float32Buffer;
	public var tangentImpulse2:Float32Buffer;

	var previousCount:Int = 0;
	var previousShapeA:Int32Buffer;
	var previousShapeB:Int32Buffer;
	var previousFeatureId:Int32Buffer;
	var previousNormalX:Float32Buffer;
	var previousNormalY:Float32Buffer;
	var previousNormalZ:Float32Buffer;
	var previousNormalImpulse:Float32Buffer;
	var previousTangentImpulse1:Float32Buffer;
	var previousTangentImpulse2:Float32Buffer;
	var hashStamp:Int32Buffer;
	var hashIndex:Int32Buffer;
	var hashMask:Int;
	var epoch:Int = 1;

	/** Storage starts at `initialCapacity` contacts, or `maxContacts` if fewer. */
	public function new(maxContacts:Int = 8192, initialCapacity:Int = 256) {
		this.maxContacts = (maxContacts + 3) & ~3;
		allocate(Std.int(Math.min(this.maxContacts, (Std.int(Math.max(4, initialCapacity)) + 3) & ~3)));
	}

	function allocate(cap:Int):Void {
		var old = capacity, keep = count, keepPrevious = previousCount;
		inline function ints(a:Int32Buffer, n:Int):Int32Buffer {
			var b = new Int32Buffer(cap);
			if (a != null)
				b.blit(0, a, 0, n);
			return b;
		}
		inline function singles(a:Float32Buffer, n:Int):Float32Buffer {
			var b = new Float32Buffer(cap);
			if (a != null)
				b.blit(0, a, 0, n);
			return b;
		}
		bodyA = ints(bodyA, keep);
		bodyB = ints(bodyB, keep);
		shapeA = ints(shapeA, keep);
		shapeB = ints(shapeB, keep);
		featureId = ints(featureId, keep);
		normalX = singles(normalX, keep);
		normalY = singles(normalY, keep);
		normalZ = singles(normalZ, keep);
		pointX = singles(pointX, keep);
		pointY = singles(pointY, keep);
		pointZ = singles(pointZ, keep);
		penetration = singles(penetration, keep);
		normalImpulse = singles(normalImpulse, keep);
		tangentImpulse1 = singles(tangentImpulse1, keep);
		tangentImpulse2 = singles(tangentImpulse2, keep);
		previousShapeA = ints(previousShapeA, keepPrevious);
		previousShapeB = ints(previousShapeB, keepPrevious);
		previousFeatureId = ints(previousFeatureId, keepPrevious);
		previousNormalX = singles(previousNormalX, keepPrevious);
		previousNormalY = singles(previousNormalY, keepPrevious);
		previousNormalZ = singles(previousNormalZ, keepPrevious);
		previousNormalImpulse = singles(previousNormalImpulse, keepPrevious);
		previousTangentImpulse1 = singles(previousTangentImpulse1, keepPrevious);
		previousTangentImpulse2 = singles(previousTangentImpulse2, keepPrevious);
		capacity = cap;
		var hashCapacity = 4;
		while (hashCapacity < cap * 2)
			hashCapacity <<= 1;
		if (hashStamp != null && hashCapacity == hashStamp.length)
			return;
		hashMask = hashCapacity - 1;
		hashStamp = new Int32Buffer(hashCapacity);
		hashIndex = new Int32Buffer(hashCapacity);
		for (i in 0...hashCapacity)
			hashStamp[i] = 0;
		// The last step's contacts are looked up by the new table too.
		if (old > 0)
			for (i in 0...keepPrevious)
				insertPrevious(i);
	}

	/** Makes room for `n` contacts, up to `maxContacts`; returns whether there is. */
	public function reserve(n:Int):Bool {
		if (n <= capacity)
			return true;
		if (n > maxContacts)
			return false;
		var cap = capacity;
		while (cap < n)
			cap = cap * 2;
		allocate(Std.int(Math.min(maxContacts, cap)));
		return true;
	}

	function insertPrevious(i:Int):Void {
		var sa = previousShapeA[i],
			sb = previousShapeB[i],
			feature = previousFeatureId[i];
		var bucket = hash(sa, sb, feature);
		while (hashStamp[bucket] == epoch) {
			var old = hashIndex[bucket];
			if (previousShapeA[old] == sa && previousShapeB[old] == sb && previousFeatureId[old] == feature)
				break;
			bucket = (bucket + 1) & hashMask;
		}
		hashStamp[bucket] = epoch;
		hashIndex[bucket] = i;
	}

	inline function hash(a:Int, b:Int, feature:Int):Int {
		return (a * 73856093 ^ b * 19349663 ^ feature * 83492791) & hashMask;
	}

	public function beginStep():Void {
		// Epoch stamps retire old buckets without clearing the whole table each substep.
		epoch++;
		if (epoch == 0) {
			for (i in 0...hashStamp.length)
				hashStamp[i] = 0;
			epoch = 1;
		}
		for (i in 0...count) {
			previousShapeA[i] = shapeA[i];
			previousShapeB[i] = shapeB[i];
			previousFeatureId[i] = featureId[i];
			previousNormalX[i] = normalX[i];
			previousNormalY[i] = normalY[i];
			previousNormalZ[i] = normalZ[i];
			previousNormalImpulse[i] = normalImpulse[i];
			previousTangentImpulse1[i] = tangentImpulse1[i];
			previousTangentImpulse2[i] = tangentImpulse2[i];
			insertPrevious(i);
		}
		previousCount = count;
		count = 0;
	}

	/** Drops contacts that involve shape slot `shape`, keeping the others in order with their impulses. */
	public function removeShape(shape:Int):Void {
		var kept = 0;
		for (i in 0...count) {
			if (shapeA[i] == shape || shapeB[i] == shape)
				continue;
			if (kept != i)
				move(kept, i);
			kept++;
		}
		count = kept;
	}

	/** Drops contacts that involve body slot `body`, keeping the others in order with their impulses. */
	public function removeBody(body:Int):Void {
		var kept = 0;
		for (i in 0...count) {
			if (bodyA[i] == body || bodyB[i] == body)
				continue;
			if (kept != i)
				move(kept, i);
			kept++;
		}
		count = kept;
	}

	inline function move(dst:Int, src:Int):Void {
		bodyA[dst] = bodyA[src];
		bodyB[dst] = bodyB[src];
		shapeA[dst] = shapeA[src];
		shapeB[dst] = shapeB[src];
		featureId[dst] = featureId[src];
		normalX[dst] = normalX[src];
		normalY[dst] = normalY[src];
		normalZ[dst] = normalZ[src];
		pointX[dst] = pointX[src];
		pointY[dst] = pointY[src];
		pointZ[dst] = pointZ[src];
		penetration[dst] = penetration[src];
		normalImpulse[dst] = normalImpulse[src];
		tangentImpulse1[dst] = tangentImpulse1[src];
		tangentImpulse2[dst] = tangentImpulse2[src];
	}

	public function clear():Void {
		count = 0;
		previousCount = 0;
		epoch++;
		if (epoch == 0) {
			for (i in 0...hashStamp.length)
				hashStamp[i] = 0;
			epoch = 1;
		}
	}

	public function addContact(a:Int, b:Int, sa:Int, sb:Int, feature:Int, normal:Vec3, point:Vec3, depth:Float):Void {
		if (count >= capacity && !reserve(count + 1))
			return;
		var i = count++;
		bodyA[i] = a;
		bodyB[i] = b;
		shapeA[i] = sa;
		shapeB[i] = sb;
		featureId[i] = feature;
		normalX[i] = normal.x;
		normalY[i] = normal.y;
		normalZ[i] = normal.z;
		pointX[i] = point.x;
		pointY[i] = point.y;
		pointZ[i] = point.z;
		penetration[i] = depth;
		var bucket = hash(sa, sb, feature);
		while (hashStamp[bucket] == epoch) {
			var old = hashIndex[bucket];
			if (previousShapeA[old] == sa && previousShapeB[old] == sb && previousFeatureId[old] == feature)
				break;
			bucket = (bucket + 1) & hashMask;
		}
		if (hashStamp[bucket] == epoch) {
			var old = hashIndex[bucket];
			if (previousNormalX[old] * normal.x + previousNormalY[old] * normal.y + previousNormalZ[old] * normal.z > 0.8) {
				normalImpulse[i] = previousNormalImpulse[old];
				tangentImpulse1[i] = previousTangentImpulse1[old];
				tangentImpulse2[i] = previousTangentImpulse2[old];
				return;
			}
		}
		normalImpulse[i] = 0;
		tangentImpulse1[i] = 0;
		tangentImpulse2[i] = 0;
	}

	/** Visits the contacts and their warm starts for `WorldSnapshot`. The lookup epoch is left as it is: it only has to stay ahead of every stamp. */
	@:noCompletion public function visitState(s:hxn.me.physics.core.WorldSnapshot):Void {
		var live = count;
		var saved = s.int(count);
		reserve(saved);
		count = saved;
		var n = s.span(live, count);
		s.ints(bodyA, n);
		s.ints(bodyB, n);
		s.ints(shapeA, n);
		s.ints(shapeB, n);
		s.ints(featureId, n);
		s.singles(normalX, n);
		s.singles(normalY, n);
		s.singles(normalZ, n);
		s.singles(pointX, n);
		s.singles(pointY, n);
		s.singles(pointZ, n);
		s.singles(penetration, n);
		s.singles(normalImpulse, n);
		s.singles(tangentImpulse1, n);
		s.singles(tangentImpulse2, n);
	}
}

// GJK simplex: up to four Minkowski-difference vertices W = A - B, each with the
// A and B support points that produced it so witness points can be rebuilt.
private class GjkSimplex {
	public var n:Int = 0;
	public var wx:Float64Buffer;
	public var wy:Float64Buffer;
	public var wz:Float64Buffer;
	public var ax:Float64Buffer;
	public var ay:Float64Buffer;
	public var az:Float64Buffer;
	public var bx:Float64Buffer;
	public var by:Float64Buffer;
	public var bz:Float64Buffer;
	// Barycentric weights of the closest point, indexed like the vertices.
	public var lam:Float64Buffer;
	// Scratch weights for tetrahedron faces and degenerate-triangle edges.
	public var faceLam:Float64Buffer;
	public var edgeLam:Float64Buffer;
	public var bestLam:Float64Buffer;

	public function new() {
		wx = new Float64Buffer(4);
		wy = new Float64Buffer(4);
		wz = new Float64Buffer(4);
		ax = new Float64Buffer(4);
		ay = new Float64Buffer(4);
		az = new Float64Buffer(4);
		bx = new Float64Buffer(4);
		by = new Float64Buffer(4);
		bz = new Float64Buffer(4);
		lam = new Float64Buffer(4);
		faceLam = new Float64Buffer(4);
		edgeLam = new Float64Buffer(4);
		bestLam = new Float64Buffer(4);
	}

	public inline function set(i:Int, a:Vec3, b:Vec3):Void {
		ax[i] = a.x;
		ay[i] = a.y;
		az[i] = a.z;
		bx[i] = b.x;
		by[i] = b.y;
		bz[i] = b.z;
		wx[i] = ax[i] - bx[i];
		wy[i] = ay[i] - by[i];
		wz[i] = az[i] - bz[i];
	}

	public inline function setPoint(i:Int, pax:Float, pay:Float, paz:Float, pbx:Float, pby:Float, pbz:Float):Void {
		ax[i] = pax;
		ay[i] = pay;
		az[i] = paz;
		bx[i] = pbx;
		by[i] = pby;
		bz[i] = pbz;
		wx[i] = pax - pbx;
		wy[i] = pay - pby;
		wz[i] = paz - pbz;
	}

	public inline function copy(dst:Int, src:Int):Void {
		wx[dst] = wx[src];
		wy[dst] = wy[src];
		wz[dst] = wz[src];
		ax[dst] = ax[src];
		ay[dst] = ay[src];
		az[dst] = az[src];
		bx[dst] = bx[src];
		by[dst] = by[src];
		bz[dst] = bz[src];
		lam[dst] = lam[src];
	}
}

@:allow(hxn.me.physics.collision.NarrowPhase)
class NarrowPhaseWorkspace {
	var simplex:GjkSimplex;
	// Output of NarrowPhase.support.
	var supportX:Float = 0.0;
	var supportY:Float = 0.0;
	var supportZ:Float = 0.0;

	// Closest core points on A and on B left by NarrowPhase.separation.
	public var witnessAX(default, null):Float = 0.0;
	public var witnessAY(default, null):Float = 0.0;
	public var witnessAZ(default, null):Float = 0.0;
	public var witnessBX(default, null):Float = 0.0;
	public var witnessBY(default, null):Float = 0.0;
	public var witnessBZ(default, null):Float = 0.0;
	// Unit normal from B toward A left by NarrowPhase.separation.
	public var separationX(default, null):Float = 0.0;
	public var separationY(default, null):Float = 0.0;
	public var separationZ(default, null):Float = 0.0;

	// Closest point of A - B from the last NarrowPhase.closestPoints call.
	var closestX:Float = 0.0;
	var closestY:Float = 0.0;
	var closestZ:Float = 0.0;
	// Contact normal and single-point fallback handed to the manifold pool.
	var normal:Vec3;
	var point:Vec3;
	var epa:Epa;
	var pair:EpaPair;

	public function new() {
		simplex = new GjkSimplex();
		normal = new Vec3();
		point = new Vec3();
		epa = new Epa();
		pair = new EpaPair();
	}
}

/** The two posed shapes EPA expands between, giving support points of A - B without a closure. */
@:allow(hxn.me.physics.collision.NarrowPhase)
class EpaPair {
	var pool:VertexPool;
	var sA:ShapeDef;
	var sB:ShapeDef;
	var pax = 0.0;
	var pay = 0.0;
	var paz = 0.0;
	var qax = 0.0;
	var qay = 0.0;
	var qaz = 0.0;
	var qaw = 1.0;
	var pbx = 0.0;
	var pby = 0.0;
	var pbz = 0.0;
	var qbx = 0.0;
	var qby = 0.0;
	var qbz = 0.0;
	var qbw = 1.0;
	var ws:NarrowPhaseWorkspace;

	/** W = A - B of the last support point, whether or not it was new. */
	public var lastX(default, null) = 0.0;

	public var lastY(default, null) = 0.0;
	public var lastZ(default, null) = 0.0;

	public function new() {}

	/** Adds the support point of A - B along (dx, dy, dz) to `epa`; returns whether it was new. */
	public function support(epa:Epa, dx:Float, dy:Float, dz:Float):Bool {
		NarrowPhase.support(pool, sA, pax, pay, paz, qax, qay, qaz, qaw, dx, dy, dz, ws);
		var ax = ws.supportX, ay = ws.supportY, az = ws.supportZ;
		NarrowPhase.support(pool, sB, pbx, pby, pbz, qbx, qby, qbz, qbw, -dx, -dy, -dz, ws);
		lastX = ax - ws.supportX;
		lastY = ay - ws.supportY;
		lastZ = az - ws.supportZ;
		return epa.add(ax, ay, az, ws.supportX, ws.supportY, ws.supportZ);
	}
}

class DistanceResult {
	public var distance:Single;
	public var pointA:Vec3;
	public var pointB:Vec3;
	// Points from B toward A when the core shapes are separated.
	public var normal:Vec3;

	public function new(distance:Single, pointA:Vec3, pointB:Vec3, normal:Vec3) {
		this.distance = distance;
		this.pointA = pointA;
		this.pointB = pointB;
		this.normal = normal;
	}
}

@:allow(hxn.me.physics.collision.EpaPair)
class NarrowPhase {
	// Evaluates world-space core support point for any 2D or 3D shape
	static inline function worldSupport(pool:VertexPool, def:ShapeDef, pos:Vec3, rot:Quat, worldDir:Vec3):Vec3 {
		var localDir = Quat.invRotate(rot, worldDir);
		var localPt = def.getLocalSupport(pool, localDir);
		return Vec3.add(pos, Quat.rotate(rot, localPt));
	}

	/**
	 * World-space core support point of `def` at pose (p, q) along world
	 * direction d, written to the workspace's support fields.
	 */
	static function support(pool:VertexPool, def:ShapeDef, px:Float, py:Float, pz:Float, qx:Float, qy:Float, qz:Float, qw:Float, dx:Float, dy:Float, dz:Float,
			ws:NarrowPhaseWorkspace):Void {
		var tx = 2.0 * (qz * dy - qy * dz),
			ty = 2.0 * (qx * dz - qz * dx),
			tz = 2.0 * (qy * dx - qx * dy);
		var lx = dx + qw * tx + (qz * ty - qy * tz);
		var ly = dy + qw * ty + (qx * tz - qz * tx);
		var lz = dz + qw * tz + (qy * tx - qx * ty);
		var bx = 0.0, by = 0.0, bz = 0.0;
		var count = def.kind == ShapeKind.Point ? 0 : def.vertCount;
		if (count > 0) {
			var vx = pool.vx, vy = pool.vy, vz = pool.vz, offset = def.vertOffset;
			bx = vx[offset];
			by = vy[offset];
			bz = vz[offset];
			var best = bx * lx + by * ly + bz * lz;
			for (i in 1...count) {
				var cx:Float = vx[offset + i],
					cy:Float = vy[offset + i],
					cz:Float = vz[offset + i];
				var d = cx * lx + cy * ly + cz * lz;
				if (d > best) {
					best = d;
					bx = cx;
					by = cy;
					bz = cz;
				}
			}
		}
		var half = def.depth * 0.5;
		bz += def.localZ + (def.depth > 0.0 && lz != 0.0 ? (lz > 0.0 ? half : -half) : 0.0);
		var ux = 2.0 * (qy * bz - qz * by),
			uy = 2.0 * (qz * bx - qx * bz),
			uz = 2.0 * (qx * by - qy * bx);
		ws.supportX = px + bx + qw * ux + (qy * uz - qz * uy);
		ws.supportY = py + by + qw * uy + (qz * ux - qx * uz);
		ws.supportZ = pz + bz + qw * uz + (qx * uy - qy * ux);
	}

	static inline function clear(l:Float64Buffer):Void {
		l[0] = 0.0;
		l[1] = 0.0;
		l[2] = 0.0;
		l[3] = 0.0;
	}

	static inline function copyLam(dst:Float64Buffer, src:Float64Buffer):Void {
		dst[0] = src[0];
		dst[1] = src[1];
		dst[2] = src[2];
		dst[3] = src[3];
	}

	// Squared length of the point sum(l[i] * W[i]).
	static function weightedSq(s:GjkSimplex, l:Float64Buffer):Float {
		var x = 0.0, y = 0.0, z = 0.0;
		for (i in 0...s.n) {
			x += l[i] * s.wx[i];
			y += l[i] * s.wy[i];
			z += l[i] * s.wz[i];
		}
		return x * x + y * y + z * z;
	}

	// Closest point to the origin on segment W[i0]W[i1].
	static function segment(s:GjkSimplex, i0:Int, i1:Int, l:Float64Buffer):Void {
		clear(l);
		var px = s.wx[i0], py = s.wy[i0], pz = s.wz[i0];
		var ex = s.wx[i1] - px, ey = s.wy[i1] - py, ez = s.wz[i1] - pz;
		var ee = ex * ex + ey * ey + ez * ez;
		if (ee <= 1e-18) {
			l[i0] = 1.0;
			return;
		}
		var t = -(px * ex + py * ey + pz * ez) / ee;
		if (t <= 0.0)
			l[i0] = 1.0;
		else if (t >= 1.0)
			l[i1] = 1.0;
		else {
			l[i0] = 1.0 - t;
			l[i1] = t;
		}
	}

	// Closest point to the origin on triangle W[i0]W[i1]W[i2], by Voronoi region.
	static function triangle(s:GjkSimplex, i0:Int, i1:Int, i2:Int, l:Float64Buffer):Void {
		clear(l);
		var ax = s.wx[i0], ay = s.wy[i0], az = s.wz[i0];
		var bx = s.wx[i1], by = s.wy[i1], bz = s.wz[i1];
		var cx = s.wx[i2], cy = s.wy[i2], cz = s.wz[i2];
		var abx = bx - ax, aby = by - ay, abz = bz - az;
		var acx = cx - ax, acy = cy - ay, acz = cz - az;

		var d1 = -(abx * ax + aby * ay + abz * az);
		var d2 = -(acx * ax + acy * ay + acz * az);
		if (d1 <= 0.0 && d2 <= 0.0) {
			l[i0] = 1.0;
			return;
		}

		var d3 = -(abx * bx + aby * by + abz * bz);
		var d4 = -(acx * bx + acy * by + acz * bz);
		if (d3 >= 0.0 && d4 <= d3) {
			l[i1] = 1.0;
			return;
		}

		var vc = d1 * d4 - d3 * d2;
		if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) {
			var den = d1 - d3;
			var t = den > 0.0 ? d1 / den : 0.0;
			l[i0] = 1.0 - t;
			l[i1] = t;
			return;
		}

		var d5 = -(abx * cx + aby * cy + abz * cz);
		var d6 = -(acx * cx + acy * cy + acz * cz);
		if (d6 >= 0.0 && d5 <= d6) {
			l[i2] = 1.0;
			return;
		}

		var vb = d5 * d2 - d1 * d6;
		if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) {
			var den = d2 - d6;
			var t = den > 0.0 ? d2 / den : 0.0;
			l[i0] = 1.0 - t;
			l[i2] = t;
			return;
		}

		var va = d3 * d6 - d5 * d4;
		if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) {
			var den = (d4 - d3) + (d5 - d6);
			var t = den > 0.0 ? (d4 - d3) / den : 0.0;
			l[i1] = 1.0 - t;
			l[i2] = t;
			return;
		}

		// va + vb + vc is |ab x ac|^2; near zero the triangle is a sliver, so use its best edge.
		var sum = va + vb + vc;
		var abab = abx * abx + aby * aby + abz * abz;
		var acac = acx * acx + acy * acy + acz * acz;
		if (sum <= 1e-12 * abab * acac) {
			var e = s.edgeLam;
			var best = Math.POSITIVE_INFINITY;
			segment(s, i0, i1, e);
			var d = weightedSq(s, e);
			if (d < best) {
				best = d;
				copyLam(l, e);
			}
			segment(s, i0, i2, e);
			d = weightedSq(s, e);
			if (d < best) {
				best = d;
				copyLam(l, e);
			}
			segment(s, i1, i2, e);
			d = weightedSq(s, e);
			if (d < best) {
				copyLam(l, e);
			}
			return;
		}

		var v = vb / sum;
		var w = vc / sum;
		l[i0] = 1.0 - v - w;
		l[i1] = v;
		l[i2] = w;
	}

	// (W[j] - W[i]) x (W[k] - W[i]) . (W[m] - W[i]); an index of -1 stands for the origin.
	static function det(s:GjkSimplex, i:Int, j:Int, k:Int, m:Int):Float {
		var ix = i < 0 ? 0.0 : s.wx[i],
			iy = i < 0 ? 0.0 : s.wy[i],
			iz = i < 0 ? 0.0 : s.wz[i];
		var jx = (j < 0 ? 0.0 : s.wx[j]) - ix,
			jy = (j < 0 ? 0.0 : s.wy[j]) - iy,
			jz = (j < 0 ? 0.0 : s.wz[j]) - iz;
		var kx = (k < 0 ? 0.0 : s.wx[k]) - ix,
			ky = (k < 0 ? 0.0 : s.wy[k]) - iy,
			kz = (k < 0 ? 0.0 : s.wz[k]) - iz;
		var mx = (m < 0 ? 0.0 : s.wx[m]) - ix,
			my = (m < 0 ? 0.0 : s.wy[m]) - iy,
			mz = (m < 0 ? 0.0 : s.wz[m]) - iz;
		return (jy * kz - jz * ky) * mx + (jz * kx - jx * kz) * my + (jx * ky - jy * kx) * mz;
	}

	// Closest point to the origin on tetrahedron W[0..3]. A face is searched when the
	// origin lies on the far side of it from the opposite vertex; if none, the origin is inside.
	static function tetrahedron(s:GjkSimplex, l:Float64Buffer):Void {
		var vol = det(s, 0, 1, 2, 3);
		var e1 = (s.wx[1]
			- s.wx[0]) * (s.wx[1] - s.wx[0])
			+ (s.wy[1] - s.wy[0]) * (s.wy[1] - s.wy[0])
			+ (s.wz[1] - s.wz[0]) * (s.wz[1] - s.wz[0]);
		var e2 = (s.wx[2]
			- s.wx[0]) * (s.wx[2] - s.wx[0])
			+ (s.wy[2] - s.wy[0]) * (s.wy[2] - s.wy[0])
			+ (s.wz[2] - s.wz[0]) * (s.wz[2] - s.wz[0]);
		var e3 = (s.wx[3]
			- s.wx[0]) * (s.wx[3] - s.wx[0])
			+ (s.wy[3] - s.wy[0]) * (s.wy[3] - s.wy[0])
			+ (s.wz[3] - s.wz[0]) * (s.wz[3] - s.wz[0]);
		// Flat tetrahedra (e.g. two depth-0 shapes on one plane) have no reliable face sides.
		var flat = vol * vol <= 1e-12 * e1 * e2 * e3;

		var f = s.faceLam;
		var best = Math.POSITIVE_INFINITY;
		var inside = true;

		// Faces (i, j, k) with opposite vertex m.
		for (face in 0...4) {
			var i = 0, j = 1, k = 2, m = 3;
			switch (face) {
				case 1:
					i = 0;
					j = 2;
					k = 3;
					m = 1;
				case 2:
					i = 0;
					j = 3;
					k = 1;
					m = 2;
				case 3:
					i = 1;
					j = 3;
					k = 2;
					m = 0;
				default:
			}
			var outside = flat || det(s, i, j, k, -1) * det(s, i, j, k, m) < 0.0;
			if (!outside)
				continue;
			inside = false;
			triangle(s, i, j, k, f);
			var d = weightedSq(s, f);
			if (d < best) {
				best = d;
				copyLam(s.bestLam, f);
			}
		}

		if (!inside) {
			copyLam(l, s.bestLam);
			return;
		}

		var inv = 1.0 / vol;
		l[0] = det(s, -1, 1, 2, 3) * inv;
		l[1] = det(s, 0, -1, 2, 3) * inv;
		l[2] = det(s, 0, 1, -1, 3) * inv;
		l[3] = 1.0 - l[0] - l[1] - l[2];
	}

	public static function distancePair(pool:VertexPool, sA:ShapeDef, posA:Vec3, rotA:Quat, sB:ShapeDef, posB:Vec3, rotB:Quat,
			workspace:NarrowPhaseWorkspace = null):DistanceResult {
		var s = workspace == null ? new GjkSimplex() : workspace.simplex;
		var dir = Vec3.sub(posA, posB);
		if (Vec3.lengthSq(dir) < 1e-8)
			dir = new Vec3(1, 0, 0);
		s.set(0, worldSupport(pool, sA, posA, rotA, dir), worldSupport(pool, sB, posB, rotB, Vec3.scale(dir, -1.0)));
		s.n = 1;
		s.lam[0] = 1.0;
		var vx = s.wx[0], vy = s.wy[0], vz = s.wz[0];
		var vv = vx * vx + vy * vy + vz * vz;
		for (iter in 0...32) {
			if (vv <= 1e-12) {
				vv = 0.0;
				break;
			}
			var ak = worldSupport(pool, sA, posA, rotA, new Vec3(-vx, -vy, -vz));
			var bk = worldSupport(pool, sB, posB, rotB, new Vec3(vx, vy, vz));
			var wkx:Float = ak.x - bk.x,
				wky:Float = ak.y - bk.y,
				wkz:Float = ak.z - bk.z;
			if (vv - (vx * wkx + vy * wky + vz * wkz) <= 1e-6 * vv)
				break;
			var repeated = false;
			for (i in 0...s.n) {
				var dx = s.wx[i] - wkx, dy = s.wy[i] - wky, dz = s.wz[i] - wkz;
				if (dx * dx + dy * dy + dz * dz <= 1e-14) {
					repeated = true;
					break;
				}
			}
			if (repeated)
				break;
			s.set(s.n, ak, bk);
			s.n++;
			switch (s.n) {
				case 2:
					segment(s, 0, 1, s.lam);
				case 3:
					triangle(s, 0, 1, 2, s.lam);
				default:
					tetrahedron(s, s.lam);
			}
			var kept = 0;
			for (i in 0...s.n) {
				if (s.lam[i] > 0.0) {
					if (kept != i)
						s.copy(kept, i);
					kept++;
				}
			}
			s.n = kept;
			vx = 0.0;
			vy = 0.0;
			vz = 0.0;
			for (i in 0...s.n) {
				vx += s.lam[i] * s.wx[i];
				vy += s.lam[i] * s.wy[i];
				vz += s.lam[i] * s.wz[i];
			}
			var next = vx * vx + vy * vy + vz * vz;
			if (s.n == 4) {
				vv = 0.0;
				break;
			}
			if (next >= vv) {
				vv = next;
				break;
			}
			vv = next;
		}
		var ax = 0.0, ay = 0.0, az = 0.0;
		var bx = 0.0, by = 0.0, bz = 0.0;
		for (i in 0...s.n) {
			var weight = s.lam[i];
			ax += weight * s.ax[i];
			ay += weight * s.ay[i];
			az += weight * s.az[i];
			bx += weight * s.bx[i];
			by += weight * s.by[i];
			bz += weight * s.bz[i];
		}
		var distance:Single = Math.sqrt(vv);
		var normal = distance > 1e-6 ? new Vec3(vx / distance, vy / distance, vz / distance) : Vec3.normalize(dir);
		return new DistanceResult(distance, new Vec3(ax, ay, az), new Vec3(bx, by, bz), normal);
	}

	// Unified GJK Distance + Minkowski Skin Collision Detector

	/**
	 * GJK between the core shapes. Returns the squared distance, zero when the
	 * cores overlap; the closest point of A - B is left in the workspace and the
	 * simplex holds the witness points.
	 */
	static function closestPoints(pool:VertexPool, sA:ShapeDef, posA:Vec3, rotA:Quat, sB:ShapeDef, posB:Vec3, rotB:Quat, ws:NarrowPhaseWorkspace):Float {
		var s = ws.simplex;
		sA.ensureVertices(pool);
		sB.ensureVertices(pool);
		var pax:Float = posA.x, pay:Float = posA.y, paz:Float = posA.z;
		var qax:Float = rotA.x,
			qay:Float = rotA.y,
			qaz:Float = rotA.z,
			qaw:Float = rotA.w;
		var pbx:Float = posB.x, pby:Float = posB.y, pbz:Float = posB.z;
		var qbx:Float = rotB.x,
			qby:Float = rotB.y,
			qbz:Float = rotB.z,
			qbw:Float = rotB.w;

		// Initial search direction between centers
		var dx = pbx - pax, dy = pby - pay, dz = pbz - paz;
		if (dx * dx + dy * dy + dz * dz < 1e-8) {
			dx = 0.0;
			dy = 1.0;
			dz = 0.0;
		}
		support(pool, sA, pax, pay, paz, qax, qay, qaz, qaw, dx, dy, dz, ws);
		var sax = ws.supportX, say = ws.supportY, saz = ws.supportZ;
		support(pool, sB, pbx, pby, pbz, qbx, qby, qbz, qbw, -dx, -dy, -dz, ws);
		s.setPoint(0, sax, say, saz, ws.supportX, ws.supportY, ws.supportZ);
		s.n = 1;
		s.lam[0] = 1.0;

		var vx = s.wx[0], vy = s.wy[0], vz = s.wz[0];
		var vv = vx * vx + vy * vy + vz * vz;

		for (iter in 0...32) {
			// Origin reached: the core shapes overlap.
			if (vv <= 1e-12) {
				vv = 0.0;
				break;
			}

			support(pool, sA, pax, pay, paz, qax, qay, qaz, qaw, -vx, -vy, -vz, ws);
			var akx = ws.supportX, aky = ws.supportY, akz = ws.supportZ;
			support(pool, sB, pbx, pby, pbz, qbx, qby, qbz, qbw, vx, vy, vz, ws);
			var bkx = ws.supportX, bky = ws.supportY, bkz = ws.supportZ;
			var wkx:Float = akx - bkx;
			var wky:Float = aky - bky;
			var wkz:Float = akz - bkz;

			// No support point gets meaningfully closer than v: v is the closest point.
			if (vv - (vx * wkx + vy * wky + vz * wkz) <= 1e-6 * vv)
				break;

			// A repeated vertex means the simplex cannot improve further.
			var repeated = false;
			for (i in 0...s.n) {
				var ex = s.wx[i] - wkx, ey = s.wy[i] - wky, ez = s.wz[i] - wkz;
				if (ex * ex + ey * ey + ez * ez <= 1e-14) {
					repeated = true;
					break;
				}
			}
			if (repeated)
				break;

			s.setPoint(s.n, akx, aky, akz, bkx, bky, bkz);
			s.n++;

			switch (s.n) {
				case 2:
					segment(s, 0, 1, s.lam);
				case 3:
					triangle(s, 0, 1, 2, s.lam);
				default:
					tetrahedron(s, s.lam);
			}

			// Keep only the vertices supporting the closest point.
			var kept = 0;
			for (i in 0...s.n) {
				if (s.lam[i] > 0.0) {
					if (kept != i)
						s.copy(kept, i);
					kept++;
				}
			}
			s.n = kept;

			vx = 0.0;
			vy = 0.0;
			vz = 0.0;
			for (i in 0...s.n) {
				vx += s.lam[i] * s.wx[i];
				vy += s.lam[i] * s.wy[i];
				vz += s.lam[i] * s.wz[i];
			}
			var nvv = vx * vx + vy * vy + vz * vz;

			// A full tetrahedron survives reduction only when it encloses the origin.
			if (s.n == 4) {
				vv = 0.0;
				break;
			}
			if (nvv >= vv) {
				vv = nvv;
				break;
			}
			vv = nvv;
		}
		ws.closestX = vx;
		ws.closestY = vy;
		ws.closestZ = vz;
		return vv;
	}

	/**
	 * Distance between the core shapes, without rounding radii; the unit
	 * normal from B toward A and the closest core points are left in the
	 * workspace's separation and witness fields.
	 */
	public static function separation(pool:VertexPool, sA:ShapeDef, posA:Vec3, rotA:Quat, sB:ShapeDef, posB:Vec3, rotB:Quat, ws:NarrowPhaseWorkspace):Float {
		var distance = Math.sqrt(closestPoints(pool, sA, posA, rotA, sB, posB, rotB, ws));
		var s = ws.simplex;
		var ax = 0.0, ay = 0.0, az = 0.0, bx = 0.0, by = 0.0, bz = 0.0;
		for (i in 0...s.n) {
			var weight = s.lam[i];
			ax += weight * s.ax[i];
			ay += weight * s.ay[i];
			az += weight * s.az[i];
			bx += weight * s.bx[i];
			by += weight * s.by[i];
			bz += weight * s.bz[i];
		}
		ws.witnessAX = ax;
		ws.witnessAY = ay;
		ws.witnessAZ = az;
		ws.witnessBX = bx;
		ws.witnessBY = by;
		ws.witnessBZ = bz;
		if (distance > 1e-6) {
			ws.separationX = ws.closestX / distance;
			ws.separationY = ws.closestY / distance;
			ws.separationZ = ws.closestZ / distance;
		} else {
			var dx = posA.x - posB.x,
				dy = posA.y - posB.y,
				dz = posA.z - posB.z;
			var length = Math.sqrt(dx * dx + dy * dy + dz * dz);
			if (length < 1e-6) {
				dx = 1.0;
				dy = 0.0;
				dz = 0.0;
				length = 1.0;
			}
			ws.separationX = dx / length;
			ws.separationY = dy / length;
			ws.separationZ = dz / length;
		}
		return distance;
	}

	/** True when the rounded shapes overlap; used for sensors, which need no manifold. */
	public static function overlapPair(pool:VertexPool, sA:ShapeDef, posA:Vec3, rotA:Quat, sB:ShapeDef, posB:Vec3, rotB:Quat, ws:NarrowPhaseWorkspace):Bool {
		var vv = closestPoints(pool, sA, posA, rotA, sB, posB, rotB, ws);
		var radius = sA.radius + sB.radius;
		return vv <= 1e-12 || vv < radius * radius;
	}

	public static function collidePair(pool:VertexPool, sA:ShapeDef, bA:Int, posA:Vec3, rotA:Quat, sB:ShapeDef, bB:Int, posB:Vec3, rotB:Quat,
			out:ContactManifoldPool, shapeIdA:Int = -1, shapeIdB:Int = -1, topologyA:ClipTopology = null, topologyB:ClipTopology = null,
			clipWorkspace:ClipWorkspace = null, workspace:NarrowPhaseWorkspace = null):Bool {
		if (workspace == null)
			workspace = new NarrowPhaseWorkspace();
		var ws = workspace;
		var s = ws.simplex;
		var vv = closestPoints(pool, sA, posA, rotA, sB, posB, rotB, ws);
		var vx = ws.closestX, vy = ws.closestY, vz = ws.closestZ;

		var cwx:Single = vx, cwy:Single = vy, cwz:Single = vz;
		var cax = 0.0, cay = 0.0, caz = 0.0;
		var cbx = 0.0, cby = 0.0, cbz = 0.0;
		for (i in 0...s.n) {
			var li = s.lam[i];
			cax += li * s.ax[i];
			cay += li * s.ay[i];
			caz += li * s.az[i];
			cbx += li * s.bx[i];
			cby += li * s.by[i];
			cbz += li * s.bz[i];
		}

		var dist:Single = Math.sqrt(vv);
		var totalRadius:Single = sA.radius + sB.radius;

		if (dist < totalRadius || dist <= 1e-6) {
			var nx:Single = 0.0;
			var ny:Single = 1.0;
			var nz:Single = 0.0;
			var pen:Single = totalRadius - dist;

			if (dist > 1e-4) {
				var invDist:Single = -1.0 / dist;
				nx = cwx * invDist;
				ny = cwy * invDist;
				nz = cwz * invDist;
			} else {
				var epa = ws.epa, pair = ws.pair;
				epa.reset();
				for (i in 0...s.n)
					epa.add(s.ax[i], s.ay[i], s.az[i], s.bx[i], s.by[i], s.bz[i]);
				pair.pool = pool;
				pair.ws = ws;
				pair.sA = sA;
				pair.pax = posA.x;
				pair.pay = posA.y;
				pair.paz = posA.z;
				pair.qax = rotA.x;
				pair.qay = rotA.y;
				pair.qaz = rotA.z;
				pair.qaw = rotA.w;
				pair.sB = sB;
				pair.pbx = posB.x;
				pair.pby = posB.y;
				pair.pbz = posB.z;
				pair.qbx = rotB.x;
				pair.qby = rotB.y;
				pair.qbz = rotB.z;
				pair.qbw = rotB.w;
				var planar = !sA.hasDepth()
					&& !sB.hasDepth()
					&& Math.abs(rotA.x) + Math.abs(rotA.y) + Math.abs(rotB.x) + Math.abs(rotB.y) < 1e-4
					&& Math.abs(posA.z + sA.localZ - posB.z - sB.localZ) < 1e-4;
				if (planar ? epa.solve2D(pair) : epa.solve3D(pair)) {
					nx = epa.normalX;
					ny = epa.normalY;
					nz = epa.normalZ;
					pen = epa.depth + totalRadius;
					cax = epa.pointAX;
					cay = epa.pointAY;
					caz = epa.pointAZ;
					cbx = epa.pointBX;
					cby = epa.pointBY;
					cbz = epa.pointBZ;
				} else {
					var center = Vec3.sub(Vec3.add(posB, Quat.rotate(rotB, new Vec3(0, 0, sB.localZ))),
						Vec3.add(posA, Quat.rotate(rotA, new Vec3(0, 0, sA.localZ))));
					// EPA failure is rare; this fallback keeps its object arithmetic.
					if (planar)
						center.z = 0.0;
					var fallback = Vec3.normalize(center);
					nx = fallback.x;
					ny = fallback.y;
					nz = fallback.z;
					pen = totalRadius;
				}
			}

			if (pen <= 0.0)
				return false;

			if (!sA.hasDepth() && !sB.hasDepth() && Math.abs(posA.z - posB.z) < 1e-4) {
				var planarSq = nx * nx + ny * ny;
				if (planarSq < 1e-12) {
					nx = 0.0;
					ny = 1.0;
				} else {
					var inv = 1.0 / Math.sqrt(planarSq);
					nx *= inv;
					ny *= inv;
				}
				nz = 0.0;
			}

			var normal = ws.normal;
			normal.x = nx;
			normal.y = ny;
			normal.z = nz;
			var clipped = ManifoldClipper.generate(pool, sA, posA, rotA, sB, posB, rotB, normal, topologyA, topologyB, clipWorkspace);
			if (clipped.length > 0) {
				for (c in clipped)
					out.addContact(bA, bB, shapeIdA, shapeIdB, c.feature, normal, c.point, c.penetration);
			} else {
				var point = ws.point;
				point.x = 0.5 * (cax + cbx);
				point.y = 0.5 * (cay + cby);
				point.z = 0.5 * (caz + cbz);
				out.addContact(bA, bB, shapeIdA, shapeIdB, 0, normal, point, pen);
			}
			return true;
		}
		return false;
	}
}
