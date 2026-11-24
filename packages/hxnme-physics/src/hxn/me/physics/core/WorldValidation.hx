package hxn.me.physics.core;

import hxn.me.physics.diagnostics.Diagnostics;
import hxn.me.physics.geom.ShapeDef.ShapeKind;
import hxn.me.physics.collision.BroadPhase;
import hxn.me.physics.core.Handles.BodyType;

/**
 * `WorldValidation` builds `World.validate`, which reports what is wrong with
 * a world as findings with stable codes and paths (`world/bodies/<slot>/...`, `world/shapes/<slot>`,
 * `world/joints/<slot>`, `world/capacity/...`). It reads the world's buffers
 * and allocates only the report.
 */
class WorldValidation {
	static inline function num(v:Float):String
		return Diagnostics.number(v);

	/** Sets how far from the origin a body can be before 32-bit positions lose millimeters. */
	public static inline var FAR = 10000.0;

	/** Sets how far past every static shape, along gravity, a dynamic body can be before it counts as fallen out. */
	public static inline var FALLEN = 100.0;

	/** Sets the share of a capacity in use that earns a warning. */
	public static inline var FULL = 0.9;

	/** Clears an optional report, or creates one, then fills it with the world's current findings. */
	public static function world(w:World, ?report:Diagnostics):Diagnostics {
		var d = report == null ? new Diagnostics() : report;
		d.items.resize(0);
		var g = w.gravity, gl = Math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
		var dx = gl > 0 ? g.x / gl : 0.0,
			dy = gl > 0 ? g.y / gl : 0.0,
			dz = gl > 0 ? g.z / gl : 0.0;
		// Finds the furthest that any static shape reaches along gravity. Each dynamic body well past it has
		// nothing left to land on.
		var floor = Math.NEGATIVE_INFINITY;
		for (p in 0...w.activeShapeCount) {
			var s = w.activeShapeIds[p];
			if (w.bodyType[w.shapeBody[s]] != BodyType.Static || w.shapeProxy[s] == BroadPhase.NULL_NODE)
				continue;
			var o = w.shapeProxy[s] * 6, a = w.broadPhase.aabb;
			var reach = Math.max(a[o] * dx, a[o + 3] * dx) + Math.max(a[o + 1] * dy, a[o + 4] * dy) + Math.max(a[o + 2] * dz, a[o + 5] * dz);
			if (reach > floor)
				floor = reach;
		}
		for (p in 0...w.activeBodyCount)
			body(w, d, w.bodySlot(w.bodyHandleAt(p)), floor, dx, dy, dz);
		for (p in 0...w.activeShapeCount)
			shape(w, d, w.activeShapeIds[p]);
		var j = w.joints;
		for (i in 0...j.count) {
			var id = j.activeIds[i];
			// Kinematic bodies are left out, because an animated rig keeps its joints for when its bodies go
			// dynamic.
			if (w.bodyType[j.bodyA[id]] == BodyType.Static && w.bodyType[j.bodyB[id]] == BodyType.Static)
				d.warning("WORLD_JOINT_STATIC", 'world/joints/$id',
					'The ${j.kindName(id)} joint connects bodies ${j.bodyA[id]} and ${j.bodyB[id]}, both of them static, so it holds nothing.',
					"a body that can move", "two static bodies", "Make one of its bodies dynamic, or destroy the joint.");
		}
		capacity(d, "bodies", w.activeBodyCount, w.bodyCapacity);
		capacity(d, "shapes", w.activeShapeCount, w.shapeCapacity);
		capacity(d, "joints", j.count, j.capacity);
		capacity(d, "contacts", w.contacts.count, w.contacts.maxContacts);
		capacity(d, "pairs", w.broadPhase.pairCount, w.broadPhase.maxPairs);
		return d;
	}

	static function body(w:World, d:Diagnostics, s:Int, floor:Float, dx:Float, dy:Float, dz:Float):Void {
		var px:Float = w.posX[s], py:Float = w.posY[s], pz:Float = w.posZ[s];
		var qx:Float = w.rotX[s],
			qy:Float = w.rotY[s],
			qz:Float = w.rotZ[s],
			qw:Float = w.rotW[s];
		var finite = Math.isFinite(px) && Math.isFinite(py) && Math.isFinite(pz) && Math.isFinite(qx) && Math.isFinite(qy) && Math.isFinite(qz)
			&& Math.isFinite(qw);
		if (!finite) {
			d.error("WORLD_NONFINITE", 'world/bodies/$s/pose', 'Body $s has a position or rotation that is not a number.', "finite values",
				'(${num(px)}, ${num(py)}, ${num(pz)}), (${num(qx)}, ${num(qy)}, ${num(qz)}, ${num(qw)})',
				"Find what wrote it; teleport the body to a valid pose.");
			return;
		}
		var vx:Float = w.velX[s], vy:Float = w.velY[s], vz:Float = w.velZ[s];
		var ax:Float = w.angVelX[s],
			ay:Float = w.angVelY[s],
			az:Float = w.angVelZ[s];
		if (!Math.isFinite(vx) || !Math.isFinite(vy) || !Math.isFinite(vz) || !Math.isFinite(ax) || !Math.isFinite(ay) || !Math.isFinite(az))
			d.error("WORLD_NONFINITE", 'world/bodies/$s/velocity', 'Body $s has a velocity that is not a number.', "finite values",
				'(${num(vx)}, ${num(vy)}, ${num(vz)}), (${num(ax)}, ${num(ay)}, ${num(az)})', "Find what wrote it; set its velocities to zero.");
		var length = Math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
		if (Math.abs(length - 1.0) > 1e-3)
			d.warning("WORLD_ROTATION", 'world/bodies/$s/rotation', 'Body $s has a rotation of length ${num(length)}, not 1, which skews its shapes.',
				"a unit quaternion", num(length), "Normalise the rotation before writing it, or use teleportBody.");
		var distance = Math.sqrt(px * px + py * py + pz * pz);
		if (distance > FAR)
			d.warning("WORLD_FAR", 'world/bodies/$s/position', 'Body $s is ${num(distance)} units from the origin, where 32-bit positions lose precision.',
				'within ${num(FAR)}', num(distance), "Keep play near the origin, or shift the world back toward it.");
		if (w.bodyType[s] != BodyType.Dynamic)
			return;
		var first = w.firstShape[s];
		if (first == -1) {
			d.error("WORLD_NO_MASS", 'world/bodies/$s/shapes', 'Dynamic body $s has no shapes, so it has no mass and never moves.', "at least one shape",
				"none", "Attach a shape with a density, or make the body kinematic.");
			return;
		}
		var solid = false, sh = first;
		while (sh != -1) {
			if (w.shapeSensor[sh] == 0)
				solid = true;
			sh = w.shapeNext[sh];
		}
		if (!solid)
			d.warning("WORLD_SENSOR_ONLY", 'world/bodies/$s/shapes',
				'Every shape on dynamic body $s is a sensor, so it touches nothing and falls through everything.', "a solid shape", "only sensors",
				"Add a solid shape, or make the body kinematic if it should only sense.");
		var depth = px * dx + py * dy + pz * dz;
		if (floor > Math.NEGATIVE_INFINITY && depth > floor + FALLEN)
			d.warning("WORLD_FELL_OUT", 'world/bodies/$s/position',
				'Dynamic body $s is ${num(depth - floor)} units past every static shape along gravity: it has fallen out of the world.',
				'within ${num(FALLEN)} of the static shapes', num(depth - floor), "Destroy or respawn bodies that fall this far.");
	}

	static function shape(w:World, d:Diagnostics, s:Int):Void {
		if (w.shapeSensor[s] != 0 || w.shapeRadius[s] > 0.0 || w.shapeDepth[s] > 0.0)
			return;
		var kind = w.shapeKind[s], o = w.shapeVertOffset[s], n = w.shapeVertCount[s], v = w.verts;
		var empty = false;
		switch (kind) {
			case ShapeKind.Point:
				empty = true;
			case ShapeKind.Segment:
				empty = n < 2 || v.vx[o] == v.vx[o + 1] && v.vy[o] == v.vy[o + 1];
			case ShapeKind.Polygon:
				var area = 0.0;
				for (i in 0...n) {
					var j = (i + 1) % n;
					area += v.vx[o + i] * v.vy[o + j] - v.vx[o + j] * v.vy[o + i];
				}
				empty = Math.abs(area) < 1e-12;
			default:
		}
		if (empty)
			d.error("WORLD_SHAPE_EMPTY", 'world/shapes/$s', 'Shape $s on body ${w.shapeBody[s]} has no area, depth or radius, so nothing can touch it.',
				"an area, a depth or a radius", "none", "Give it a radius or depth, or make it a sensor if it only marks a point.");
	}

	static function capacity(d:Diagnostics, what:String, used:Int, limit:Int):Void {
		if (limit > 0 && used >= Math.ceil(limit * FULL))
			d.warning("WORLD_CAPACITY", 'world/capacity/$what', 'The world is using $used of its $limit $what.', 'under ${Math.round(FULL * 100)}%',
				'$used of $limit', 'Create the world with room for more $what.');
	}
}
