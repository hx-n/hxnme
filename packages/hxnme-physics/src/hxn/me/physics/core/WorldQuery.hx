package hxn.me.physics.core;

import hxn.me.physics.geom.ShapeDef;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.collision.NarrowPhase;
import hxn.me.physics.core.Handles.ShapeId;
import hl.NativeArray;

class QueryHit {
	public var shape:ShapeId;
	public var fraction:Single;
	public var point:Vec3;
	public var normal:Vec3;

	public function new(shape:ShapeId, fraction:Single, point:Vec3, normal:Vec3) {
		this.shape = shape;
		this.fraction = fraction;
		this.point = point;
		this.normal = normal;
	}
}

class WorldQuery {
	var world:World;
	// Candidate lists, one per nesting level: a queryAABB callback may run another query.
	var candidates:Array<NativeArray<Int>> = [];
	var entries:Array<NativeArray<Float>> = [];
	var depth:Int = 0;
	// Box written by `bounds`.
	var minX:Float = 0.0;
	var minY:Float = 0.0;
	var minZ:Float = 0.0;
	var maxX:Float = 0.0;
	var maxY:Float = 0.0;
	var maxZ:Float = 0.0;
	// Cast scratch: the target shape and its pose, the moving shape's pose, and the last hit found.
	var target:ShapeDef = new ShapeDef(ShapeKind.Point);
	var targetPos:Vec3 = new Vec3();
	var targetRot:Quat = new Quat();
	var movingPos:Vec3 = new Vec3();
	var rayShape:ShapeDef = new ShapeDef(ShapeKind.Point, 0, 0, 0.0, 0.0);
	var rayRotation:Quat = new Quat();
	var rayTranslation:Vec3 = new Vec3();
	var hitFraction:Float = 0.0;
	var hitX:Float = 0.0;
	var hitY:Float = 0.0;
	var hitZ:Float = 0.0;
	var hitNX:Float = 0.0;
	var hitNY:Float = 0.0;
	var hitNZ:Float = 0.0;
	var rayOrigin:Vec3 = new Vec3();

	/** The nearest hit of the last `rayCastNearest`: its shape, fraction, point and unit normal. */
	public var nearestShape(default, null):ShapeId = 0;

	public var nearestFraction(default, null):Float = 0.0;
	public var nearestX(default, null):Float = 0.0;
	public var nearestY(default, null):Float = 0.0;
	public var nearestZ(default, null):Float = 0.0;
	public var nearestNormalX(default, null):Float = 0.0;
	public var nearestNormalY(default, null):Float = 0.0;
	public var nearestNormalZ(default, null):Float = 0.0;

	public function new(world:World) {
		this.world = world;
	}

	static function finite(v:Vec3):Bool {
		return v != null && Math.isFinite(v.x) && Math.isFinite(v.y) && Math.isFinite(v.z);
	}

	/** Lets go of the candidate buffers, which are sized by the shape capacity, so the next query makes them for the new one. */
	public function releaseScratch():Void {
		candidates.resize(0);
		entries.resize(0);
	}

	/** Takes the candidate buffers for one more level of nesting. */
	function enter():Int {
		if (depth == candidates.length) {
			candidates.push(new NativeArray<Int>(world.shapeCapacity));
			entries.push(new NativeArray<Float>(world.shapeCapacity));
		}
		return depth++;
	}

	/**
	 * Box of `def` at the given pose: rotated core vertices, plus local Z
	 * offset and extrusion along the rotated Z axis, padded by the rounding
	 * radius. With `flatPlanar`, an unrotated planar shape gets no Z padding,
	 * which is the exact extent region queries test; casts pass false because
	 * a planar shape's radius still reaches along Z against volumetric shapes.
	 */
	function bounds(def:ShapeDef, px:Float, py:Float, pz:Float, x:Float, y:Float, z:Float, w:Float, flatPlanar:Bool):Void {
		var r00 = 1.0 - 2.0 * (y * y + z * z),
			r01 = 2.0 * (x * y - z * w),
			r02 = 2.0 * (x * z + y * w);
		var r10 = 2.0 * (x * y + z * w),
			r11 = 1.0 - 2.0 * (x * x + z * z),
			r12 = 2.0 * (y * z - x * w);
		var r20 = 2.0 * (x * z - y * w),
			r21 = 2.0 * (y * z + x * w),
			r22 = 1.0 - 2.0 * (x * x + y * y);
		var lx = 0.0, ly = 0.0, lz = 0.0, hx = 0.0, hy = 0.0, hz = 0.0;
		var count = def.kind == ShapeKind.Point ? 0 : def.vertCount;
		if (count > 0) {
			var verts = world.verts, offset = def.vertOffset;
			for (i in 0...count) {
				var vx:Float = verts.vx[offset + i],
					vy:Float = verts.vy[offset + i],
					vz:Float = verts.vz[offset + i];
				var wx = r00 * vx + r01 * vy + r02 * vz;
				var wy = r10 * vx + r11 * vy + r12 * vz;
				var wz = r20 * vx + r21 * vy + r22 * vz;
				if (i == 0) {
					lx = hx = wx;
					ly = hy = wy;
					lz = hz = wz;
					continue;
				}
				if (wx < lx)
					lx = wx;
				else if (wx > hx)
					hx = wx;
				if (wy < ly)
					ly = wy;
				else if (wy > hy)
					hy = wy;
				if (wz < lz)
					lz = wz;
				else if (wz > hz)
					hz = wz;
			}
		}
		var half = def.depth * 0.5,
			localZ:Float = def.localZ,
			radius:Float = def.radius;
		var planar = flatPlanar && !def.hasDepth() && Math.abs(x) + Math.abs(y) < 1e-5;
		var ex = half * Math.abs(r02) + radius,
			ey = half * Math.abs(r12) + radius;
		var ez = half * Math.abs(r22) + (planar ? 0.0 : radius);
		var ox = px + localZ * r02,
			oy = py + localZ * r12,
			oz = pz + localZ * r22;
		minX = ox + lx - ex;
		minY = oy + ly - ey;
		minZ = oz + lz - ez;
		maxX = ox + hx + ex;
		maxY = oy + hy + ey;
		maxZ = oz + hz + ez;
	}

	/** Loads world shape `slot` and its body's pose into the target scratch. */
	function loadTarget(slot:Int):Void {
		var body = world.shapeBody[slot];
		target.assign(world.shapeKind[slot], world.shapeVertOffset[slot], world.shapeVertCount[slot], world.shapeDepth[slot], world.shapeRadius[slot],
			world.shapeLocalZ[slot], world.shapeDensity[slot]);
		targetPos.x = world.posX[body];
		targetPos.y = world.posY[body];
		targetPos.z = world.posZ[body];
		targetRot.x = world.rotX[body];
		targetRot.y = world.rotY[body];
		targetRot.z = world.rotZ[body];
		targetRot.w = world.rotW[body];
	}

	inline function handle(slot:Int):ShapeId {
		return (world.shapeGeneration[slot] << 20) | slot;
	}

	public function queryAABB(min:Vec3, max:Vec3, mask:Int, callback:ShapeId->Bool):Void {
		if (!finite(min) || !finite(max) || callback == null || min.x > max.x || min.y > max.y || min.z > max.z)
			throw 'Invalid AABB query';
		var level = enter();
		var found = candidates[level];
		var count = world.broadPhase.overlappingBox(min.x, min.y, min.z, max.x, max.y, max.z, found);
		try {
			for (i in 0...count) {
				var slot = found[i];
				if ((world.shapeCategoryBits[slot] & mask) == 0)
					continue;
				loadTarget(slot);
				bounds(target, targetPos.x, targetPos.y, targetPos.z, targetRot.x, targetRot.y, targetRot.z, targetRot.w, true);
				if (minX > max.x || minY > max.y || minZ > max.z || maxX < min.x || maxY < min.y || maxZ < min.z)
					continue;
				if (!callback(handle(slot)))
					break;
			}
		} catch (error:Dynamic) {
			depth = level;
			throw error;
		}
		depth = level;
	}

	/** Casts `def` against world shape `slot`; on a hit at or before `maxFraction`, fills the hit fields and returns true. */
	function castOne(def:ShapeDef, startPos:Vec3, startRot:Quat, translation:Vec3, maxFraction:Float, slot:Int):Bool {
		loadTarget(slot);
		var ws = world.narrowWorkspace;
		var verts = world.verts;
		var planarTarget = !target.hasDepth() && Math.abs(targetRot.x) + Math.abs(targetRot.y) < 1e-5;
		var planarMoving = !def.hasDepth() && Math.abs(startRot.x) + Math.abs(startRot.y) < 1e-5;
		if (planarMoving && planarTarget) {
			var planeZ = targetPos.z + target.localZ;
			if (Math.abs(startPos.z + def.localZ - planeZ) > 1e-5 || Math.abs(translation.z) > 1e-5) {
				if (Math.abs(translation.z) < 1e-8)
					return false;
				var crossing:Single = (planeZ - startPos.z - def.localZ) / translation.z;
				if (crossing < 0.0 || crossing > maxFraction)
					return false;
				movingPos.x = startPos.x + translation.x * crossing;
				movingPos.y = startPos.y + translation.y * crossing;
				movingPos.z = startPos.z + translation.z * crossing;
				var distance = NarrowPhase.separation(verts, def, movingPos, startRot, target, targetPos, targetRot, ws);
				if (distance > def.radius + target.radius + 1e-5)
					return false;
				hitFraction = crossing;
				if (def.kind == ShapeKind.Point && def.radius == 0.0) {
					hitX = movingPos.x;
					hitY = movingPos.y;
					hitZ = movingPos.z;
				} else {
					hitX = 0.5 * (ws.witnessAX + ws.witnessBX);
					hitY = 0.5 * (ws.witnessAY + ws.witnessBY);
					hitZ = planeZ;
				}
				hitNX = 0.0;
				hitNY = 0.0;
				hitNZ = translation.z > 0 ? -1.0 : 1.0;
				return true;
			}
		}
		var length = Math.sqrt(translation.x * translation.x + translation.y * translation.y + translation.z * translation.z);
		var lastX = 0.0, lastY = 1.0, lastZ = 0.0;
		if (length >= 1e-6) {
			lastX = -translation.x / length;
			lastY = -translation.y / length;
			lastZ = -translation.z / length;
		}
		var fraction:Single = 0.0;
		for (i in 0...32) {
			movingPos.x = startPos.x + translation.x * fraction;
			movingPos.y = startPos.y + translation.y * fraction;
			movingPos.z = startPos.z + translation.z * fraction;
			var distance = NarrowPhase.separation(verts, def, movingPos, startRot, target, targetPos, targetRot, ws);
			var separation:Single = distance - def.radius - target.radius;
			if (separation <= 1e-5) {
				// Touching cores give no direction of their own; keep the last approach direction.
				var nx = distance > 1e-5 ? ws.separationX : lastX;
				var ny = distance > 1e-5 ? ws.separationY : lastY;
				var nz = distance > 1e-5 ? ws.separationZ : lastZ;
				hitFraction = fraction;
				hitX = ws.witnessBX + nx * target.radius;
				hitY = ws.witnessBY + ny * target.radius;
				hitZ = ws.witnessBZ + nz * target.radius;
				hitNX = nx;
				hitNY = ny;
				hitNZ = nz;
				return true;
			}
			lastX = ws.separationX;
			lastY = ws.separationY;
			lastZ = ws.separationZ;
			var speed = -(translation.x * lastX + translation.y * lastY + translation.z * lastZ);
			if (speed <= 1e-8)
				return false;
			var advance:Single = separation / speed;
			if (advance < 1e-7)
				advance = 1e-7;
			fraction += advance;
			if (fraction > maxFraction)
				return false;
		}
		return false;
	}

	/**
	 * Earliest fraction in [0, 1] at which the box `m`, moved by `t`, overlaps
	 * the current bounds; -1 when it never does.
	 */
	function entry(mMinX:Float, mMinY:Float, mMinZ:Float, mMaxX:Float, mMaxY:Float, mMaxZ:Float, tx:Float, ty:Float, tz:Float):Float {
		var enter = 0.0, exit = 1.0;
		for (a in 0...3) {
			var mLo = a == 0 ? mMinX : (a == 1 ? mMinY : mMinZ);
			var mHi = a == 0 ? mMaxX : (a == 1 ? mMaxY : mMaxZ);
			var cLo = a == 0 ? minX : (a == 1 ? minY : minZ);
			var cHi = a == 0 ? maxX : (a == 1 ? maxY : maxZ);
			var d = a == 0 ? tx : (a == 1 ? ty : tz);
			if (Math.abs(d) < 1e-12) {
				if (mHi < cLo || mLo > cHi)
					return -1.0;
				continue;
			}
			var first = (cLo - mHi) / d, last = (cHi - mLo) / d;
			if (first > last) {
				var t = first;
				first = last;
				last = t;
			}
			if (first > enter)
				enter = first;
			if (last < exit)
				exit = last;
			if (enter > exit)
				return -1.0;
		}
		return enter;
	}

	public function shapeCast(def:ShapeDef, startPos:Vec3, startRot:Quat, translation:Vec3, mask:Int = -1):QueryHit {
		if (def == null || !finite(startPos) || startRot == null || !finite(translation) || !Math.isFinite(startRot.x) || !Math.isFinite(startRot.y)
			|| !Math.isFinite(startRot.z) || !Math.isFinite(startRot.w) || !Math.isFinite(def.radius) || def.radius < 0.0)
			throw 'Invalid shape cast';
		if (!nearest(def, startPos, startRot, translation, mask))
			return null;
		return new QueryHit(nearestShape, nearestFraction, new Vec3(nearestX, nearestY, nearestZ), new Vec3(nearestNormalX, nearestNormalY, nearestNormalZ));
	}

	/**
	 * Casts a ray from (ox, oy, oz) to (ox, oy, oz) + (dx, dy, dz) and keeps
	 * its nearest hit in the `nearest` fields, with the fraction along that
	 * segment, from 0 to 1. Returns false when it hits nothing. Allocates
	 * nothing: for casting many rays a step, such as particles moving.
	 */
	public function rayCastNearest(ox:Float, oy:Float, oz:Float, dx:Float, dy:Float, dz:Float, mask:Int = -1):Bool {
		rayOrigin.x = ox;
		rayOrigin.y = oy;
		rayOrigin.z = oz;
		rayTranslation.x = dx;
		rayTranslation.y = dy;
		rayTranslation.z = dz;
		return nearest(rayShape, rayOrigin, rayRotation, rayTranslation, mask);
	}

	/** The nearest hit of `def` moved by `translation`, into the `nearest` fields; false when there is none. */
	function nearest(def:ShapeDef, startPos:Vec3, startRot:Quat, translation:Vec3, mask:Int):Bool {
		def.ensureVertices(world.verts);
		bounds(def, startPos.x, startPos.y, startPos.z, startRot.x, startRot.y, startRot.z, startRot.w, false);
		var mMinX = minX, mMinY = minY, mMinZ = minZ, mMaxX = maxX, mMaxY = maxY, mMaxZ = maxZ;
		var tx:Float = translation.x,
			ty:Float = translation.y,
			tz:Float = translation.z;
		var level = enter();
		var found = candidates[level], order = entries[level];
		var count = world.broadPhase.overlappingBox(mMinX
			+ Math.min(0.0, tx), mMinY
			+ Math.min(0.0, ty), mMinZ
			+ Math.min(0.0, tz),
			mMaxX
			+ Math.max(0.0, tx), mMaxY
			+ Math.max(0.0, ty), mMaxZ
			+ Math.max(0.0, tz), found);
		// Keep candidates whose own box the moving box actually enters, nearest entry first.
		var kept = 0;
		for (i in 0...count) {
			var slot = found[i];
			if ((world.shapeCategoryBits[slot] & mask) == 0 || world.shapeSensor[slot] != 0)
				continue;
			loadTarget(slot);
			bounds(target, targetPos.x, targetPos.y, targetPos.z, targetRot.x, targetRot.y, targetRot.z, targetRot.w, false);
			var at = entry(mMinX, mMinY, mMinZ, mMaxX, mMaxY, mMaxZ, tx, ty, tz);
			if (at < 0.0)
				continue;
			var j = kept++;
			while (j > 0 && order[j - 1] > at) {
				order[j] = order[j - 1];
				found[j] = found[j - 1];
				j--;
			}
			order[j] = at;
			found[j] = slot;
		}
		var best = -1;
		var bestFraction = 1.0, bestX = 0.0, bestY = 0.0, bestZ = 0.0, bestNX = 0.0, bestNY = 0.0, bestNZ = 0.0;
		for (i in 0...kept) {
			// A shape whose box is entered after the nearest hit cannot be hit sooner.
			if (best >= 0 && order[i] > bestFraction)
				break;
			var slot = found[i];
			if (!castOne(def, startPos, startRot, translation, bestFraction, slot))
				continue;
			if (best >= 0 && hitFraction >= bestFraction)
				continue;
			best = slot;
			bestFraction = hitFraction;
			bestX = hitX;
			bestY = hitY;
			bestZ = hitZ;
			bestNX = hitNX;
			bestNY = hitNY;
			bestNZ = hitNZ;
		}
		depth = level;
		if (best < 0)
			return false;
		nearestShape = handle(best);
		nearestFraction = bestFraction;
		nearestX = bestX;
		nearestY = bestY;
		nearestZ = bestZ;
		nearestNormalX = bestNX;
		nearestNormalY = bestNY;
		nearestNormalZ = bestNZ;
		return true;
	}

	public function rayCast(origin:Vec3, dir:Vec3, maxFraction:Single, mask:Int = -1, callback:QueryHit->Void = null):QueryHit {
		if (!finite(origin) || !finite(dir) || !Math.isFinite(maxFraction) || maxFraction < 0.0)
			throw 'Invalid ray cast';
		rayTranslation.x = dir.x * maxFraction;
		rayTranslation.y = dir.y * maxFraction;
		rayTranslation.z = dir.z * maxFraction;
		var hit = shapeCast(rayShape, origin, rayRotation, rayTranslation, mask);
		if (hit != null) {
			hit.fraction *= maxFraction;
			if (callback != null)
				callback(hit);
		}
		return hit;
	}
}
