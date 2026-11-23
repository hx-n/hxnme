package hxn.me.physics.collision;

import hxn.Float64Buffer;
import hxn.Int32Buffer;

/**
 * Expands a Minkowski polytope around the origin for core penetration, over
 * buffers kept from call to call, so a deep contact allocates nothing.
 *
 * The caller seeds vertices with `add` (each a point W = A - B with the A and
 * B support points that made it), then `solve3D` or `solve2D` pulls more
 * support points through `NarrowPhase.minkowskiSupport` and leaves the normal,
 * depth and witness points in the result fields.
 */
@:allow(hxn.me.physics.collision.NarrowPhase)
class Epa {
	static inline var MAX_VERTICES = 104;
	static inline var MAX_FACES = 512;
	static inline var MAX_EDGES = 256;
	// The initial hull is found by testing every triple, which needs its points as bits of an Int.
	static inline var MAX_SEED = 30;

	// Vertices: W = A - B, and the A and B support points.
	var count = 0;
	var wx = new Float64Buffer(MAX_VERTICES);
	var wy = new Float64Buffer(MAX_VERTICES);
	var wz = new Float64Buffer(MAX_VERTICES);
	var ax = new Float64Buffer(MAX_VERTICES);
	var ay = new Float64Buffer(MAX_VERTICES);
	var az = new Float64Buffer(MAX_VERTICES);
	var bx = new Float64Buffer(MAX_VERTICES);
	var by = new Float64Buffer(MAX_VERTICES);
	var bz = new Float64Buffer(MAX_VERTICES);

	// Faces: three vertex indices, the outward unit normal and the plane's distance from the origin.
	var faceCount = 0;
	var fa = new Int32Buffer(MAX_FACES);
	var fb = new Int32Buffer(MAX_FACES);
	var fc = new Int32Buffer(MAX_FACES);
	var fnx = new Float64Buffer(MAX_FACES);
	var fny = new Float64Buffer(MAX_FACES);
	var fnz = new Float64Buffer(MAX_FACES);
	var fdepth = new Float64Buffer(MAX_FACES);

	// Horizon edges while a vertex is added; the 2D ring of vertex indices.
	var edgeCount = 0;
	var ea = new Int32Buffer(MAX_EDGES);
	var eb = new Int32Buffer(MAX_EDGES);
	var ringCount = 0;
	var ring = new Int32Buffer(MAX_VERTICES);

	// Scratch for the initial hull: faces seen, by their points as bits, and a face's points ordered in its plane.
	var seenCount = 0;
	var seen = new Int32Buffer(4096);
	var orderCount = 0;
	var order = new Int32Buffer(MAX_SEED);
	var orderX = new Float64Buffer(MAX_SEED);
	var orderY = new Float64Buffer(MAX_SEED);
	var lower = new Int32Buffer(MAX_SEED + 1);
	var upper = new Int32Buffer(MAX_SEED + 1);

	/** The result: unit normal from B toward A's side, as the old solver gave it, the depth, and the witness points. */
	public var normalX(default, null) = 0.0;

	public var normalY(default, null) = 0.0;
	public var normalZ(default, null) = 0.0;
	public var depth(default, null) = 0.0;
	public var pointAX(default, null) = 0.0;
	public var pointAY(default, null) = 0.0;
	public var pointAZ(default, null) = 0.0;
	public var pointBX(default, null) = 0.0;
	public var pointBY(default, null) = 0.0;
	public var pointBZ(default, null) = 0.0;

	public function new() {}

	public inline function reset():Void {
		count = 0;
	}

	/** Adds a vertex unless one is already within rounding of it; returns whether it was added. */
	public function add(pax:Float, pay:Float, paz:Float, pbx:Float, pby:Float, pbz:Float):Bool {
		var x = pax - pbx, y = pay - pby, z = paz - pbz;
		for (i in 0...count) {
			var dx = wx[i] - x, dy = wy[i] - y, dz = wz[i] - z;
			if (dx * dx + dy * dy + dz * dz <= 1e-10)
				return false;
		}
		if (count == MAX_VERTICES)
			return false;
		var i = count++;
		wx[i] = x;
		wy[i] = y;
		wz[i] = z;
		ax[i] = pax;
		ay[i] = pay;
		az[i] = paz;
		bx[i] = pbx;
		by[i] = pby;
		bz[i] = pbz;
		return true;
	}

	function setResult(nx:Float, ny:Float, nz:Float, d:Float):Void {
		normalX = nx;
		normalY = ny;
		normalZ = nz;
		depth = d;
	}

	function segmentResult(i:Int, j:Int, nx:Float, ny:Float, nz:Float, d:Float):Void {
		setResult(nx, ny, nz, d);
		var ex = wx[j] - wx[i], ey = wy[j] - wy[i], ez = wz[j] - wz[i];
		var lenSq = ex * ex + ey * ey + ez * ez;
		var t = lenSq > 1e-12 ? -(wx[i] * ex + wy[i] * ey + wz[i] * ez) / lenSq : 0.0;
		t = Math.max(0.0, Math.min(1.0, t));
		pointAX = ax[i] + (ax[j] - ax[i]) * t;
		pointAY = ay[i] + (ay[j] - ay[i]) * t;
		pointAZ = az[i] + (az[j] - az[i]) * t;
		pointBX = bx[i] + (bx[j] - bx[i]) * t;
		pointBY = by[i] + (by[j] - by[i]) * t;
		pointBZ = bz[i] + (bz[j] - bz[i]) * t;
	}

	function triangleResult(f:Int):Void {
		var a = fa[f], b = fb[f], c = fc[f];
		var nx = fnx[f], ny = fny[f], nz = fnz[f], d = fdepth[f];
		setResult(nx, ny, nz, d);
		var abx = wx[b] - wx[a], aby = wy[b] - wy[a], abz = wz[b] - wz[a];
		var acx = wx[c] - wx[a], acy = wy[c] - wy[a], acz = wz[c] - wz[a];
		var apx = nx * d - wx[a], apy = ny * d - wy[a], apz = nz * d - wz[a];
		var d00 = abx * abx + aby * aby + abz * abz,
			d01 = abx * acx + aby * acy + abz * acz,
			d11 = acx * acx + acy * acy + acz * acz;
		var d20 = apx * abx + apy * aby + apz * abz,
			d21 = apx * acx + apy * acy + apz * acz;
		var den = d00 * d11 - d01 * d01;
		var v = den > 1e-18 ? (d11 * d20 - d01 * d21) / den : 0.0;
		var w = den > 1e-18 ? (d00 * d21 - d01 * d20) / den : 0.0;
		var u = 1.0 - v - w;
		u = Math.max(0.0, u);
		v = Math.max(0.0, v);
		w = Math.max(0.0, w);
		var sum = u + v + w;
		if (sum <= 0.0) {
			u = 1.0;
			sum = 1.0;
		}
		u /= sum;
		v /= sum;
		w /= sum;
		pointAX = ax[a] * u + ax[b] * v + ax[c] * w;
		pointAY = ay[a] * u + ay[b] * v + ay[c] * w;
		pointAZ = az[a] * u + az[b] * v + az[c] * w;
		pointBX = bx[a] * u + bx[b] * v + bx[c] * w;
		pointBY = by[a] * u + by[b] * v + by[c] * w;
		pointBZ = bz[a] * u + bz[b] * v + bz[c] * w;
	}

	/** Adds face (a, b, c), oriented by its winding alone: touching cores put the origin on face planes, where its side is decided by rounding. */
	function addFace(a:Int, b:Int, c:Int):Bool {
		if (faceCount == MAX_FACES)
			return false;
		var f = faceCount++;
		fa[f] = a;
		fb[f] = b;
		fc[f] = c;
		var abx = wx[b] - wx[a], aby = wy[b] - wy[a], abz = wz[b] - wz[a];
		var acx = wx[c] - wx[a], acy = wy[c] - wy[a], acz = wz[c] - wz[a];
		var nx = aby * acz - abz * acy,
			ny = abz * acx - abx * acz,
			nz = abx * acy - aby * acx;
		var len = Math.sqrt(nx * nx + ny * ny + nz * nz);
		if (len <= 1e-12) {
			fnx[f] = 0.0;
			fny[f] = 0.0;
			fnz[f] = 0.0;
			fdepth[f] = Math.POSITIVE_INFINITY;
			return true;
		}
		nx /= len;
		ny /= len;
		nz /= len;
		fnx[f] = nx;
		fny[f] = ny;
		fnz[f] = nz;
		fdepth[f] = nx * wx[a] + ny * wy[a] + nz * wz[a];
		return true;
	}

	/**
	 * Outward triangles of the hull of the seed vertices, each face of the hull
	 * found once from the triples that span it and fanned around its outline.
	 * Returns false when the seed has no volume.
	 */
	function buildHull():Bool {
		faceCount = 0;
		seenCount = 0;
		var n = count;
		if (n < 4 || n > MAX_SEED)
			return false;
		var minX = Math.POSITIVE_INFINITY,
			minY = Math.POSITIVE_INFINITY,
			minZ = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY,
			maxY = Math.NEGATIVE_INFINITY,
			maxZ = Math.NEGATIVE_INFINITY;
		for (v in 0...n) {
			if (!Math.isFinite(wx[v]) || !Math.isFinite(wy[v]) || !Math.isFinite(wz[v]))
				return false;
			minX = Math.min(minX, wx[v]);
			minY = Math.min(minY, wy[v]);
			minZ = Math.min(minZ, wz[v]);
			maxX = Math.max(maxX, wx[v]);
			maxY = Math.max(maxY, wy[v]);
			maxZ = Math.max(maxZ, wz[v]);
		}
		var scale = Math.max(maxX - minX, Math.max(maxY - minY, maxZ - minZ));
		if (scale <= 0.0)
			return false;
		var eps = scale * 1e-6;
		for (i in 0...n)
			for (j in i + 1...n) {
				var dx = wx[i] - wx[j], dy = wy[i] - wy[j], dz = wz[i] - wz[j];
				if (dx * dx + dy * dy + dz * dz <= eps * eps)
					return false;
			}
		var straight = eps * scale;
		for (i in 0...n)
			for (j in i + 1...n)
				for (k in j + 1...n) {
					var ex = wx[j] - wx[i],
						ey = wy[j] - wy[i],
						ez = wz[j] - wz[i];
					var gx = wx[k] - wx[i],
						gy = wy[k] - wy[i],
						gz = wz[k] - wz[i];
					var nx = ey * gz - ez * gy,
						ny = ez * gx - ex * gz,
						nz = ex * gy - ey * gx;
					var len = Math.sqrt(nx * nx + ny * ny + nz * nz);
					if (len <= eps * eps)
						continue;
					nx /= len;
					ny /= len;
					nz /= len;
					var positive = false, negative = false;
					for (v in 0...n) {
						var side = nx * (wx[v] - wx[i]) + ny * (wy[v] - wy[i]) + nz * (wz[v] - wz[i]);
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
					var distance = nx * wx[i] + ny * wy[i] + nz * wz[i];
					var mask = 0;
					for (v in 0...n)
						if (Math.abs(nx * wx[v] + ny * wy[v] + nz * wz[v] - distance) <= eps * 2.0)
							mask |= 1 << v;
					var known = false;
					for (s in 0...seenCount)
						if (seen[s] == mask) {
							known = true;
							break;
						}
					if (known)
						continue;
					if (seenCount == seen.length)
						return false;
					seen[seenCount++] = mask;

					// The face's points in its own plane, sorted by x then y, then wrapped by a monotone chain.
					var o = -1, second = -1;
					for (v in 0...n)
						if (mask & (1 << v) != 0) {
							if (o < 0)
								o = v;
							else if (second < 0)
								second = v;
						}
					var ux = wx[second] - wx[o],
						uy = wy[second] - wy[o],
						uz = wz[second] - wz[o];
					var ul = Math.sqrt(ux * ux + uy * uy + uz * uz);
					ux /= ul;
					uy /= ul;
					uz /= ul;
					var vx = ny * uz - nz * uy,
						vy = nz * ux - nx * uz,
						vz = nx * uy - ny * ux;
					orderCount = 0;
					for (v in 0...n)
						if (mask & (1 << v) != 0) {
							var dx = wx[v] - wx[o],
								dy = wy[v] - wy[o],
								dz = wz[v] - wz[o];
							var px = dx * ux + dy * uy + dz * uz,
								py = dx * vx + dy * vy + dz * vz;
							// Insertion keeps the order sorted as points arrive.
							var at = orderCount++;
							while (at > 0 && (orderX[at - 1] > px || (orderX[at - 1] == px && orderY[at - 1] > py))) {
								order[at] = order[at - 1];
								orderX[at] = orderX[at - 1];
								orderY[at] = orderY[at - 1];
								at--;
							}
							order[at] = v;
							orderX[at] = px;
							orderY[at] = py;
						}
					// Points within rounding of the outline's edges are left out, so no sliver triangle can turn the wrong way.
					var lowerCount = 0;
					for (p in 0...orderCount) {
						while (lowerCount >= 2 && cross2(lower[lowerCount - 2], lower[lowerCount - 1], p) <= straight)
							lowerCount--;
						lower[lowerCount++] = p;
					}
					var upperCount = 0;
					var p = orderCount - 1;
					while (p >= 0) {
						while (upperCount >= 2 && cross2(upper[upperCount - 2], upper[upperCount - 1], p) <= straight)
							upperCount--;
						upper[upperCount++] = p;
						p--;
					}
					var ringLength = lowerCount - 1 + upperCount - 1;
					if (ringLength < 3)
						continue;
					inline function ringAt(h:Int):Int
						return order[h < lowerCount - 1 ? lower[h] : upper[h - (lowerCount - 1)]];
					var a = ringAt(0);
					for (h in 1...ringLength - 1) {
						var b = ringAt(h), c = ringAt(h + 1);
						// Each triangle must face the way its face does and have area.
						var tx = (wy[b] - wy[a]) * (wz[c] - wz[a]) - (wz[b] - wz[a]) * (wy[c] - wy[a]);
						var ty = (wz[b] - wz[a]) * (wx[c] - wx[a]) - (wx[b] - wx[a]) * (wz[c] - wz[a]);
						var tz = (wx[b] - wx[a]) * (wy[c] - wy[a]) - (wy[b] - wy[a]) * (wx[c] - wx[a]);
						if (tx * nx + ty * ny + tz * nz <= straight)
							continue;
						if (!addFace(a, b, c))
							return false;
					}
				}
		return faceCount >= 4;
	}

	inline function cross2(i:Int, j:Int, k:Int):Float {
		return (orderX[j] - orderX[i]) * (orderY[k] - orderY[i]) - (orderY[j] - orderY[i]) * (orderX[k] - orderX[i]);
	}

	/** Records edge a→b of a face being removed; the reverse edge of a neighbour also being removed cancels it. */
	function addHorizon(a:Int, b:Int):Bool {
		for (i in 0...edgeCount)
			if (ea[i] == b && eb[i] == a) {
				edgeCount--;
				// Kept in order, as the faces built from them are.
				for (k in i...edgeCount) {
					ea[k] = ea[k + 1];
					eb[k] = eb[k + 1];
				}
				return true;
			}
		if (edgeCount == MAX_EDGES)
			return false;
		ea[edgeCount] = a;
		eb[edgeCount] = b;
		edgeCount++;
		return true;
	}

	/** Solves for a 3D pair; false when the polytope cannot be built or does not converge. */
	public function solve3D(pair:NarrowPhase.EpaPair):Bool {
		for (axis in 0...6) {
			var s = (axis & 1) == 0 ? 1.0 : -1.0;
			var k = axis >> 1;
			pair.support(this, k == 0 ? s : 0.0, k == 1 ? s : 0.0, k == 2 ? s : 0.0);
		}
		if (count < 4 || !buildHull())
			return false;
		for (f in 0...faceCount)
			if (fdepth[f] < -1e-5)
				return false;

		for (iter in 0...64) {
			var best = -1;
			for (f in 0...faceCount) {
				if (fdepth[f] == Math.POSITIVE_INFINITY)
					continue;
				if (best < 0 || fdepth[f] < fdepth[best])
					best = f;
			}
			if (best < 0)
				return false;
			var nx = fnx[best],
				ny = fny[best],
				nz = fnz[best],
				bestDepth = fdepth[best];
			var before = count;
			var added = pair.support(this, nx, ny, nz);
			// The support point, whether or not it was new.
			var px = pair.lastX, py = pair.lastY, pz = pair.lastZ;
			var gain = nx * px + ny * py + nz * pz - bestDepth;
			if (gain <= 1e-5 * Math.max(1.0, bestDepth) || before >= 96) {
				if (added)
					count--;
				triangleResult(best);
				return true;
			}
			// Any known vertex beyond the face plane means the face is not on the hull.
			if (!added) {
				fdepth[best] = Math.POSITIVE_INFINITY;
				continue;
			}
			var newIndex = count - 1;
			edgeCount = 0;
			var kept = 0;
			for (f in 0...faceCount) {
				if (fnx[f] * px + fny[f] * py + fnz[f] * pz - fdepth[f] > 1e-6) {
					if (!addHorizon(fa[f], fb[f]) || !addHorizon(fb[f], fc[f]) || !addHorizon(fc[f], fa[f]))
						return false;
				} else {
					if (kept != f) {
						fa[kept] = fa[f];
						fb[kept] = fb[f];
						fc[kept] = fc[f];
						fnx[kept] = fnx[f];
						fny[kept] = fny[f];
						fnz[kept] = fnz[f];
						fdepth[kept] = fdepth[f];
					}
					kept++;
				}
			}
			if (edgeCount == 0) {
				triangleResult(best);
				return true;
			}
			faceCount = kept;
			for (e in 0...edgeCount)
				if (!addFace(ea[e], eb[e], newIndex))
					return false;
		}
		return false;
	}

	/** Solves for a planar pair, in the XY plane; false when the ring cannot be built or does not converge. */
	public function solve2D(pair:NarrowPhase.EpaPair):Bool {
		pair.support(this, 1, 0, 0);
		pair.support(this, -1, 0, 0);
		pair.support(this, 0, 1, 0);
		pair.support(this, 0, -1, 0);
		buildRing();
		if (ringCount < 3)
			return false;
		for (iter in 0...64) {
			var best = Math.POSITIVE_INFINITY, bestIndex = -1;
			var bnx = 0.0, bny = 0.0;
			for (i in 0...ringCount) {
				var p = ring[i], q = ring[(i + 1) % ringCount];
				var ex = wx[q] - wx[p], ey = wy[q] - wy[p];
				var len = Math.sqrt(ex * ex + ey * ey);
				if (len <= 1e-10)
					continue;
				var nx = ey / len, ny = -ex / len;
				var d = nx * wx[p] + ny * wy[p] + 0.0 * wz[p];
				if (d < -1e-5)
					return false;
				if (d < best) {
					best = d;
					bestIndex = i;
					bnx = nx;
					bny = ny;
				}
			}
			if (bestIndex < 0)
				return false;
			var added = pair.support(this, bnx, bny, 0.0);
			var px = pair.lastX, py = pair.lastY, pz = pair.lastZ;
			var gain = bnx * px + bny * py - best;
			var duplicate = !added;
			if (!duplicate)
				for (i in 0...ringCount) {
					var v = ring[i], dx = wx[v] - px, dy = wy[v] - py, dz = wz[v] - pz;
					if (dx * dx + dy * dy + dz * dz <= 1e-10)
						duplicate = true;
				}
			if (gain <= 1e-5 * Math.max(1.0, best) || duplicate || ringCount == MAX_VERTICES) {
				if (added)
					count--;
				segmentResult(ring[bestIndex], ring[(bestIndex + 1) % ringCount], bnx, bny, 0.0, best);
				return true;
			}
			var at = bestIndex + 1;
			var k = ringCount++;
			while (k > at) {
				ring[k] = ring[k - 1];
				k--;
			}
			ring[at] = count - 1;
		}
		return false;
	}

	/** The convex outline of the vertices in XY, counter-clockwise, by a monotone chain. */
	function buildRing():Void {
		// Vertex indices sorted by x then y, in `order`.
		orderCount = 0;
		for (v in 0...count) {
			if (orderCount == MAX_SEED)
				break;
			var at = orderCount++;
			while (at > 0 && (wx[order[at - 1]] > wx[v] || (wx[order[at - 1]] == wx[v] && wy[order[at - 1]] > wy[v]))) {
				order[at] = order[at - 1];
				at--;
			}
			order[at] = v;
		}
		inline function turn(i:Int, j:Int, v:Int):Float
			return (wx[j] - wx[i]) * (wy[v] - wy[i]) - (wy[j] - wy[i]) * (wx[v] - wx[i]);
		var lowerCount = 0;
		for (p in 0...orderCount) {
			var v = order[p];
			while (lowerCount >= 2 && !(turn(lower[lowerCount - 2], lower[lowerCount - 1], v) > 1e-9))
				lowerCount--;
			lower[lowerCount++] = v;
		}
		var upperCount = 0;
		var p = orderCount - 1;
		while (p >= 0) {
			var v = order[p];
			while (upperCount >= 2 && !(turn(upper[upperCount - 2], upper[upperCount - 1], v) > 1e-9))
				upperCount--;
			upper[upperCount++] = v;
			p--;
		}
		ringCount = 0;
		for (i in 0...lowerCount - 1)
			ring[ringCount++] = lower[i];
		for (i in 0...upperCount - 1)
			ring[ringCount++] = upper[i];
	}
}
