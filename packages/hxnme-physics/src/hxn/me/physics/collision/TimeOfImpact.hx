package hxn.me.physics.collision;

import hxn.Float32Buffer;
import hxn.Int32Buffer;
import hxn.me.physics.geom.ShapeDef;
import hxn.me.physics.geom.ShapeDef.ShapeKind;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyType;

class ToiHit {
	public var fraction:Single;
	public var shapeA:Int;
	public var shapeB:Int;
	public var normal:Vec3;

	public function new(fraction:Single, shapeA:Int, shapeB:Int, normal:Vec3) {
		this.fraction = fraction;
		this.shapeA = shapeA;
		this.shapeB = shapeB;
		this.normal = normal;
	}
}

class TimeOfImpact {
	public var resolvedImpacts(default, null):Int = 0;

	var world:World;
	var dx:Float32Buffer;
	var dy:Float32Buffer;
	var dz:Float32Buffer;
	var fast:Int32Buffer;
	// The largest move any body not checked as fast makes this segment; fast bodies' sweeps are widened by it.
	var slowReach:Float = 0.0;
	// Per-pair scratch and the hits of the current search, reused across calls.
	var shapeA:ShapeDef = new ShapeDef(ShapeKind.Point);
	var shapeB:ShapeDef = new ShapeDef(ShapeKind.Point);
	var posA:Vec3 = new Vec3();
	var posB:Vec3 = new Vec3();
	var rotA:Quat = new Quat();
	var rotB:Quat = new Quat();
	var atA:Vec3 = new Vec3();
	var atB:Vec3 = new Vec3();
	var candidates:Int32Buffer;
	var candidate:ToiHit = new ToiHit(0.0, -1, -1, new Vec3());
	var earliest:ToiHit = new ToiHit(0.0, -1, -1, new Vec3());

	public function new(world:World) {
		this.world = world;
		dx = new Float32Buffer(world.bodyCapacity);
		dy = new Float32Buffer(world.bodyCapacity);
		dz = new Float32Buffer(world.bodyCapacity);
		fast = new Int32Buffer(world.bodyCapacity);
		candidates = new Int32Buffer(world.shapeCapacity);
	}

	/** Makes the per-step scratch for the world's present capacities; it holds nothing between steps. */
	public function resize():Void {
		dx = new Float32Buffer(world.bodyCapacity);
		dy = new Float32Buffer(world.bodyCapacity);
		dz = new Float32Buffer(world.bodyCapacity);
		fast = new Int32Buffer(world.bodyCapacity);
		candidates = new Int32Buffer(world.shapeCapacity);
	}

	public function beginStep():Void {
		resolvedImpacts = 0;
	}

	function minimumRadius(body:Int):Single {
		var radius:Single = Math.POSITIVE_INFINITY;
		var shape = world.firstShape[body];
		while (shape != -1) {
			if (world.shapeProxy[shape] == BroadPhase.NULL_NODE) {
				shape = world.shapeNext[shape];
				continue;
			}
			var candidate = world.shapeRadius[shape];
			if (world.shapeKind[shape] == ShapeKind.Polygon || world.shapeKind[shape] == ShapeKind.Hull) {
				var box = world.shapeProxy[shape] * 6;
				var rx = (world.broadPhase.aabb[box + 3] - world.broadPhase.aabb[box]) * 0.5;
				var ry = (world.broadPhase.aabb[box + 4] - world.broadPhase.aabb[box + 1]) * 0.5;
				candidate = Math.min(rx, ry);
				if (world.shapeDepth[shape] > 0 || world.shapeKind[shape] == ShapeKind.Hull) {
					var rz = (world.broadPhase.aabb[box + 5] - world.broadPhase.aabb[box + 2]) * 0.5;
					candidate = Math.min(candidate, rz);
				}
			}
			if (candidate < radius)
				radius = candidate;
			shape = world.shapeNext[shape];
		}
		return radius;
	}

	function prepare(h:Single, frameDt:Single):Bool {
		var any = false;
		slowReach = 0.0;
		for (position in 0...world.activeBodyCount) {
			var body = world.activeBodyIds[position];
			var moving = world.bodyType[body] != BodyType.Static && world.islands.isAwake[body] != 0;
			var gx = moving && world.bodyType[body] == BodyType.Dynamic && world.invMassX[body] > 0 ? world.gravity.x * h : 0.0;
			var gy = moving && world.bodyType[body] == BodyType.Dynamic && world.invMassY[body] > 0 ? world.gravity.y * h : 0.0;
			var gz = moving && world.bodyType[body] == BodyType.Dynamic && world.invMassZ[body] > 0 ? world.gravity.z * h : 0.0;
			dx[body] = moving ? (world.velX[body] + gx) * h : 0.0;
			dy[body] = moving ? (world.velY[body] + gy) * h : 0.0;
			dz[body] = moving ? (world.velZ[body] + gz) * h : 0.0;
			var displacement = Math.sqrt(dx[body] * dx[body] + dy[body] * dy[body] + dz[body] * dz[body]);
			fast[body] = moving
				&& world.firstShape[body] != -1
				&& displacement > 1e-8
				&& (world.isBullet[body] != 0 || displacement * frameDt / h > minimumRadius(body)) ? 1 : 0;
			if (fast[body] != 0)
				any = true;
			else if (displacement > slowReach)
				slowReach = displacement;
		}
		return any;
	}

	/**
	 * Grows each fast body's shapes over the whole of their move, and by the
	 * furthest any other body moves, so a query from a fast shape finds every
	 * shape it could meet. Only fast bodies are touched: in a crowd, sweeping
	 * every moving body would rebuild most of the tree each segment.
	 */
	function sweptProxies():Void {
		var r = slowReach;
		for (position in 0...world.activeShapeCount) {
			var shape = world.activeShapeIds[position];
			var body = world.shapeBody[shape];
			if (fast[body] == 0)
				continue;
			var x = dx[body], y = dy[body], z = dz[body];
			var proxy = world.shapeProxy[shape];
			if (proxy == BroadPhase.NULL_NODE)
				continue;
			var o = proxy * 6;
			var aabb = world.broadPhase.aabb;
			world.broadPhase.updateProxy(proxy, aabb[o]
				+ Math.min(0.0, x)
				- r, aabb[o + 1]
				+ Math.min(0.0, y)
				- r, aabb[o + 2]
				+ Math.min(0.0, z)
				- r,
				aabb[o + 3]
				+ Math.max(0.0, x)
				+ r, aabb[o + 4]
				+ Math.max(0.0, y)
				+ r, aabb[o + 5]
				+ Math.max(0.0, z)
				+ r);
		}
	}

	function restoreProxies():Void {
		for (position in 0...world.activeBodyCount) {
			var body = world.activeBodyIds[position];
			if (fast[body] != 0)
				world.updateShapeAABBs(body, true);
		}
	}

	function allowed(a:Int, b:Int):Bool {
		var bodyA = world.shapeBody[a], bodyB = world.shapeBody[b];
		if (bodyA == bodyB || (world.bodyType[bodyA] == BodyType.Static && world.bodyType[bodyB] == BodyType.Static))
			return false;
		if (world.shapeSensor[a] != 0 || world.shapeSensor[b] != 0)
			return false;
		return world.joints.bodiesMayCollide(bodyA, bodyB)
			&& BroadPhase.filtersAllow(a, b, world.shapeCategoryBits, world.shapeMaskBits, world.shapeGroupIndex);
	}

	inline function load(def:ShapeDef, shape:Int):Void {
		def.assign(world.shapeKind[shape], world.shapeVertOffset[shape], world.shapeVertCount[shape], world.shapeDepth[shape], world.shapeRadius[shape],
			world.shapeLocalZ[shape], world.shapeDensity[shape]);
	}

	/** Core distance between the pair with A and B advanced by `fraction` of their moves; normal in the workspace. */
	inline function separationAt(bodyA:Int, bodyB:Int, fraction:Float):Float {
		atA.x = posA.x + dx[bodyA] * fraction;
		atA.y = posA.y + dy[bodyA] * fraction;
		atA.z = posA.z + dz[bodyA] * fraction;
		atB.x = posB.x + dx[bodyB] * fraction;
		atB.y = posB.y + dy[bodyB] * fraction;
		atB.z = posB.z + dz[bodyB] * fraction;
		return NarrowPhase.separation(world.verts, shapeA, atA, rotA, shapeB, atB, rotB, world.narrowWorkspace);
	}

	/** Conservative advancement for one pair; on a hit before `maxFraction`, fills `candidate` and returns true. */
	function castPair(a:Int, b:Int, maxFraction:Single):Bool {
		var bodyA = world.shapeBody[a], bodyB = world.shapeBody[b];
		load(shapeA, a);
		load(shapeB, b);
		posA.x = world.posX[bodyA];
		posA.y = world.posY[bodyA];
		posA.z = world.posZ[bodyA];
		posB.x = world.posX[bodyB];
		posB.y = world.posY[bodyB];
		posB.z = world.posZ[bodyB];
		rotA.x = world.rotX[bodyA];
		rotA.y = world.rotY[bodyA];
		rotA.z = world.rotZ[bodyA];
		rotA.w = world.rotW[bodyA];
		rotB.x = world.rotX[bodyB];
		rotB.y = world.rotY[bodyB];
		rotB.z = world.rotZ[bodyB];
		rotB.w = world.rotW[bodyB];
		var rx:Float = dx[bodyA] - dx[bodyB],
			ry:Float = dy[bodyA] - dy[bodyB],
			rz:Float = dz[bodyA] - dz[bodyB];
		var radii = shapeA.radius + shapeB.radius;
		var ws = world.narrowWorkspace;
		var planarA = !shapeA.hasDepth() && Math.abs(rotA.x) + Math.abs(rotA.y) < 1e-5;
		var planarB = !shapeB.hasDepth() && Math.abs(rotB.x) + Math.abs(rotB.y) < 1e-5;
		if (planarA && planarB) {
			var planeGap = posA.z + shapeA.localZ - posB.z - shapeB.localZ;
			if (Math.abs(planeGap) > 1e-5 || Math.abs(rz) > 1e-5) {
				if (Math.abs(rz) < 1e-8)
					return false;
				var crossing:Single = -planeGap / rz;
				if (crossing <= 0.0 || crossing > maxFraction)
					return false;
				if (separationAt(bodyA, bodyB, crossing) > radii + 1e-5)
					return false;
				return hit(crossing, a, b, 0.0, 0.0, rz > 0 ? -1.0 : 1.0);
			}
		}
		// Already touching at the start: the discrete contact handles it.
		var separation:Float = separationAt(bodyA, bodyB, 0.0) - radii;
		if (separation <= 1e-5)
			return false;
		var fraction:Single = 0.0;
		for (iter in 0...32) {
			if (iter > 0)
				separation = separationAt(bodyA, bodyB, fraction) - radii;
			var nx = ws.separationX, ny = ws.separationY, nz = ws.separationZ;
			if (separation <= 1e-5)
				return hit(fraction, a, b, nx, ny, nz);
			var speed = -(rx * nx + ry * ny + rz * nz);
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

	inline function hit(fraction:Single, a:Int, b:Int, nx:Float, ny:Float, nz:Float):Bool {
		candidate.fraction = fraction;
		candidate.shapeA = a;
		candidate.shapeB = b;
		candidate.normal.x = nx;
		candidate.normal.y = ny;
		candidate.normal.z = nz;
		return true;
	}

	/** Earliest impact among fast bodies this segment, or null. The returned hit is reused by the next call. */
	public function findEarliest(h:Single, frameDt:Single):ToiHit {
		if (!prepare(h, frameDt))
			return null;
		sweptProxies();
		var found = false;
		for (position in 0...world.activeShapeCount) {
			var a = world.activeShapeIds[position];
			var bodyA = world.shapeBody[a];
			if (fast[bodyA] == 0 || world.shapeProxy[a] == BroadPhase.NULL_NODE)
				continue;
			var count = world.broadPhase.overlapping(world.shapeProxy[a], candidates);
			for (k in 0...count) {
				var b = candidates[k];
				if (b == a || !allowed(a, b) || (fast[world.shapeBody[b]] != 0 && b < a))
					continue;
				if (castPair(a, b, found ? earliest.fraction : 1.0) && (!found || candidate.fraction < earliest.fraction)) {
					var t = earliest;
					earliest = candidate;
					candidate = t;
					found = true;
				}
			}
		}
		restoreProxies();
		return found ? earliest : null;
	}

	public function resolve(hit:ToiHit):Void {
		resolvedImpacts++;
		var a = world.shapeBody[hit.shapeA], b = world.shapeBody[hit.shapeB];
		if (world.bodyType[a] == BodyType.Dynamic)
			world.wakeBodySlot(a);
		if (world.bodyType[b] == BodyType.Dynamic)
			world.wakeBodySlot(b);
		var nx = hit.normal.x, ny = hit.normal.y, nz = hit.normal.z;
		var relative = (world.velX[a] - world.velX[b]) * nx + (world.velY[a] - world.velY[b]) * ny + (world.velZ[a] - world.velZ[b]) * nz;
		if (relative >= 0.0)
			return;
		var massA = nx * nx * world.invMassX[a] + ny * ny * world.invMassY[a] + nz * nz * world.invMassZ[a];
		var massB = nx * nx * world.invMassX[b] + ny * ny * world.invMassY[b] + nz * nz * world.invMassZ[b];
		var total = massA + massB;
		if (total <= 0.0)
			return;
		var restitution = Math.max(world.shapeRestitution[hit.shapeA], world.shapeRestitution[hit.shapeB]);
		var impulse = -(1.0 + restitution) * relative / total;
		world.velX[a] += impulse * nx * world.invMassX[a];
		world.velY[a] += impulse * ny * world.invMassY[a];
		world.velZ[a] += impulse * nz * world.invMassZ[a];
		world.velX[b] -= impulse * nx * world.invMassX[b];
		world.velY[b] -= impulse * ny * world.invMassY[b];
		world.velZ[b] -= impulse * nz * world.invMassZ[b];
	}
}
