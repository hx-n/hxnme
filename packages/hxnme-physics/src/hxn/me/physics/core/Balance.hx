package hxn.me.physics.core;

import hxn.me.physics.diagnostics.Diagnostics;
import hxn.Float32Buffer;
import hxn.Int32Buffer;
import hxn.me.math.Vec3;
import hxn.me.physics.core.Handles;

/**
 * `Balance` measures how well a set of bodies, such as a character, is
 * balanced. It finds where the center of mass is and how fast it moves, the
 * support polygon that the set's contacts with the ground make, how far
 * inside that polygon the center of mass stands, and the capture point,
 * where the set must step to stop.
 *
 * "Up" is against gravity. The support polygon is the convex hull, seen from
 * above, of the points where something outside the set pushes a body of the
 * set upward. Planar sets have a support interval along X instead. Distances
 * to the support are signed: positive inside, negative outside. Call
 * `update` after each step. Each sleeping body keeps the support it had. If
 * a body is already asleep the first time it is measured, `Balance` wakes
 * it, so its support is known from the next step. That is the only way
 * measuring changes the simulation. Allocates nothing after construction.
 */
class Balance {
	/** Sets the most contact points that `Balance` considers. It ignores any more points. */
	public static inline var MAX_POINTS = 64;

	/** Each contact counts as support when its normal is within this cosine of up. */
	public static inline var SUPPORT_COSINE = 0.5;

	/** Sets the separation beyond which contacts are not touching. */
	public static inline var TOUCH = 0.005;

	public var world(default, null):World;
	public var planar(default, null):Bool;
	public var totalMass(default, null):Float = 0.0;

	public var comX(default, null):Float = 0.0;
	public var comY(default, null):Float = 0.0;
	public var comZ(default, null):Float = 0.0;
	public var velX(default, null):Float = 0.0;
	public var velY(default, null):Float = 0.0;
	public var velZ(default, null):Float = 0.0;

	/** Is true when something outside the set holds it up. */
	public var grounded(default, null):Bool = false;

	/** Holds the height of the center of mass above the support, along up. */
	public var height(default, null):Float = 0.0;

	/** Holds the signed distance from the center of mass, seen from above, to the edge of the support. It is negative infinity when the set is not grounded. */
	public var margin(default, null):Float = Math.NEGATIVE_INFINITY;

	/** Holds the point where the center of mass comes to rest over a point foot: center of mass + horizontal velocity · √(height / g). */
	public var captureX(default, null):Float = 0.0;

	public var captureY(default, null):Float = 0.0;
	public var captureZ(default, null):Float = 0.0;

	/** Holds the signed distance from the capture point to the edge of the support. */
	public var captureMargin(default, null):Float = Math.NEGATIVE_INFINITY;

	/** Counts the corners of the support polygon, or the two ends of the interval when planar. `supportX`..`supportZ` hold them in world space, anticlockwise seen from above. */
	public var supportCount(default, null):Int = 0;

	public var supportX(default, null):Float32Buffer;
	public var supportY(default, null):Float32Buffer;
	public var supportZ(default, null):Float32Buffer;

	var bodies:Array<BodyId>;
	var slots:Int32Buffer;
	var mass:Float32Buffer;
	var centroidX:Float32Buffer;
	var centroidY:Float32Buffer;
	var centroidZ:Float32Buffer;
	// Holds index + 1 of each body of the set, by slot, and 0 for other bodies. This tells the set's
	// contacts from other contacts.
	var member:Int32Buffer;

	/** Counts the bodies that `member` has room for. Bodies made after the world grew are not in the set. */
	var memberRoom = 0;
	// Holds the support points last seen under each body (body index, world position). Sleeping
	// bodies keep no contacts, so these points stand in for theirs.
	var keptBody:Int32Buffer;
	var keptX:Float32Buffer;
	var keptY:Float32Buffer;
	var keptZ:Float32Buffer;
	var keptCount = 0;
	var newBody:Int32Buffer;
	var newX:Float32Buffer;
	var newY:Float32Buffer;
	var newZ:Float32Buffer;
	// Marks each body that was seen awake, so its support is known.
	var seen:Int32Buffer;
	// These buffers hold the support points in plane coordinates, sorted, then the indices of the hull.
	var pu:Float32Buffer;
	var pv:Float32Buffer;
	var hull:Int32Buffer;
	var hullCount = 0;
	// These fields hold the up direction and two directions across it.
	var ux = 0.0;
	var uy = 1.0;
	var uz = 0.0;
	var ax = 1.0;
	var ay = 0.0;
	var az = 0.0;
	var bx = 0.0;
	var by = 0.0;
	var bz = -1.0;

	/** Measures `bodies` in `world`. With `planar`, a planar set gets a support interval along X. */
	public function new(world:World, bodies:Array<BodyId>, planar:Bool = false) {
		this.world = world;
		this.bodies = bodies.copy();
		this.planar = planar;
		var n = bodies.length;
		slots = new Int32Buffer(n + 1);
		mass = new Float32Buffer(n + 1);
		centroidX = new Float32Buffer(n + 1);
		centroidY = new Float32Buffer(n + 1);
		centroidZ = new Float32Buffer(n + 1);
		memberRoom = world.bodyCapacity;
		member = new Int32Buffer(memberRoom);
		for (i in 0...memberRoom)
			member[i] = 0;
		var c = new Vec3();
		for (i in 0...n) {
			slots[i] = world.bodySlot(bodies[i]);
			member[slots[i]] = i + 1;
			mass[i] = world.shapeMass(bodies[i], c);
			centroidX[i] = c.x;
			centroidY[i] = c.y;
			centroidZ[i] = c.z;
			totalMass += mass[i];
		}
		pu = new Float32Buffer(MAX_POINTS);
		pv = new Float32Buffer(MAX_POINTS);
		keptBody = new Int32Buffer(MAX_POINTS);
		keptX = new Float32Buffer(MAX_POINTS);
		keptY = new Float32Buffer(MAX_POINTS);
		keptZ = new Float32Buffer(MAX_POINTS);
		newBody = new Int32Buffer(MAX_POINTS);
		newX = new Float32Buffer(MAX_POINTS);
		newY = new Float32Buffer(MAX_POINTS);
		newZ = new Float32Buffer(MAX_POINTS);
		seen = new Int32Buffer(n + 1);
		for (i in 0...n)
			seen[i] = 0;
		hull = new Int32Buffer(MAX_POINTS * 2 + 2);
		supportX = new Float32Buffer(MAX_POINTS);
		supportY = new Float32Buffer(MAX_POINTS);
		supportZ = new Float32Buffer(MAX_POINTS);
	}

	/** Measures the bodies as the last step left them. */
	public function update():Void {
		var w = world;
		// Up is against gravity. Two directions across it make the plane seen from above.
		var g = w.gravity, gl = Math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
		if (gl > 0.0) {
			ux = -g.x / gl;
			uy = -g.y / gl;
			uz = -g.z / gl;
		} else {
			ux = 0.0;
			uy = 1.0;
			uz = 0.0;
		}
		ax = 1.0 - ux * ux;
		ay = -ux * uy;
		az = -ux * uz;
		var al = Math.sqrt(ax * ax + ay * ay + az * az);
		if (al < 1e-6) {
			ax = -uz * ux;
			ay = -uz * uy;
			az = 1.0 - uz * uz;
			al = Math.sqrt(ax * ax + ay * ay + az * az);
		}
		ax /= al;
		ay /= al;
		az /= al;
		bx = uy * az - uz * ay;
		by = uz * ax - ux * az;
		bz = ux * ay - uy * ax;

		// Finds the center of mass and its velocity. Each body's centroid moves with its velocity plus
		// its spin about the point that the velocity is for.
		var mx = 0.0, my = 0.0, mz = 0.0, vx = 0.0, vy = 0.0, vz = 0.0;
		for (i in 0...bodies.length) {
			var s = slots[i], m:Float = mass[i];
			if (m <= 0.0)
				continue;
			var qx:Float = w.rotX[s],
				qy:Float = w.rotY[s],
				qz:Float = w.rotZ[s],
				qw:Float = w.rotW[s];
			var lx:Float = centroidX[i],
				ly:Float = centroidY[i],
				lz:Float = centroidZ[i];
			var tx = 2.0 * (qy * lz - qz * ly),
				ty = 2.0 * (qz * lx - qx * lz),
				tz = 2.0 * (qx * ly - qy * lx);
			var cx = w.posX[s] + lx + qw * tx + (qy * tz - qz * ty);
			var cy = w.posY[s] + ly + qw * ty + (qz * tx - qx * tz);
			var cz = w.posZ[s] + lz + qw * tz + (qx * ty - qy * tx);
			var rx = cx - w.worldCenterX[s],
				ry = cy - w.worldCenterY[s],
				rz = cz - w.worldCenterZ[s];
			var wx = w.stepAngularVelocityX(s),
				wy = w.stepAngularVelocityY(s),
				wz = w.stepAngularVelocityZ(s);
			mx += m * cx;
			my += m * cy;
			mz += m * cz;
			vx += m * (w.stepVelocityX(s) + wy * rz - wz * ry);
			vy += m * (w.stepVelocityY(s) + wz * rx - wx * rz);
			vz += m * (w.stepVelocityZ(s) + wx * ry - wy * rx);
		}
		var total = totalMass > 0.0 ? totalMass : 1.0;
		comX = mx / total;
		comY = my / total;
		comZ = mz / total;
		velX = vx / total;
		velY = vy / total;
		velZ = vz / total;

		// The support points are where something outside the set pushes a body of the set upward.
		// Each sleeping body keeps no contacts but has not moved, so it keeps the points it had. If a
		// body was asleep since before it was first seen, it is woken once, so the next step finds
		// its contacts.
		var n = 0;
		for (i in 0...bodies.length) {
			var s = slots[i];
			var asleep = w.bodyType[s] == BodyType.Dynamic && w.islands.isAwake[s] == 0;
			if (!asleep) {
				seen[i] = 1;
				continue;
			}
			if (seen[i] == 0) {
				seen[i] = 1;
				w.wakeBody(bodies[i]);
				continue;
			}
			for (k in 0...keptCount)
				if (keptBody[k] == i && n < MAX_POINTS) {
					newBody[n] = i;
					newX[n] = keptX[k];
					newY[n] = keptY[k];
					newZ[n] = keptZ[k];
					n++;
				}
		}
		var c = w.contacts;
		for (k in 0...c.count) {
			var a = c.bodyA[k], b = c.bodyB[k];
			var inA = a < memberRoom && member[a] != 0, inB = b < memberRoom && member[b] != 0;
			if (inA == inB || c.penetration[k] < -TOUCH)
				continue;
			// The normal points from A to B. The set's body must be pushed up.
			var up = (c.normalX[k] * ux + c.normalY[k] * uy + c.normalZ[k] * uz) * (inB ? 1.0 : -1.0);
			if (up < SUPPORT_COSINE || n >= MAX_POINTS)
				continue;
			newBody[n] = (inA ? member[a] : member[b]) - 1;
			newX[n] = c.pointX[k];
			newY[n] = c.pointY[k];
			newZ[n] = c.pointZ[k];
			n++;
		}
		// Keep this step's points for next time, and project them onto the plane seen from above.
		var level = 0.0;
		for (k in 0...n) {
			var px:Float = newX[k], py:Float = newY[k], pz:Float = newZ[k];
			keptBody[k] = newBody[k];
			keptX[k] = px;
			keptY[k] = py;
			keptZ[k] = pz;
			pu[k] = px * ax + py * ay + pz * az;
			pv[k] = planar ? 0.0 : px * bx + py * by + pz * bz;
			level += px * ux + py * uy + pz * uz;
		}
		keptCount = n;
		grounded = n > 0;
		supportCount = 0;
		var comU = comX * ax + comY * ay + comZ * az,
			comV = planar ? 0.0 : comX * bx + comY * by + comZ * bz;
		if (!grounded) {
			height = 0.0;
			margin = Math.NEGATIVE_INFINITY;
			captureMargin = Math.NEGATIVE_INFINITY;
			captureX = comX;
			captureY = comY;
			captureZ = comZ;
			return;
		}
		level /= n;
		height = comX * ux + comY * uy + comZ * uz - level;
		// The capture point is the center of mass carried on by its velocity across the plane for
		// √(height / g).
		var reach = gl > 0.0 && height > 0.0 ? Math.sqrt(height / gl) : 0.0;
		var vu = velX * ax + velY * ay + velZ * az,
			vv = planar ? 0.0 : velX * bx + velY * by + velZ * bz;
		var capU = comU + vu * reach, capV = comV + vv * reach;
		captureX = comX + (vu * ax + vv * bx) * reach;
		captureY = comY + (vu * ay + vv * by) * reach;
		captureZ = comZ + (vu * az + vv * bz) * reach;

		buildHull(n);
		for (i in 0...hullCount) {
			var u:Float = pu[hull[i]], v:Float = pv[hull[i]];
			supportX[i] = ax * u + bx * v + ux * level;
			supportY[i] = ay * u + by * v + uy * level;
			supportZ[i] = az * u + bz * v + uz * level;
		}
		supportCount = hullCount;
		margin = distance(comU, comV);
		captureMargin = distance(capU, capV);
	}

	/** Builds the support polygon of the first `n` points: their convex hull, or for a planar set the interval they span. Sorts the points in place. */
	function buildHull(n:Int):Void {
		// Sorts by u, then v, with an insertion sort, because there are few points and it allocates nothing.
		for (i in 1...n) {
			var u:Float = pu[i], v:Float = pv[i], j = i - 1;
			while (j >= 0 && (pu[j] > u || pu[j] == u && pv[j] > v)) {
				pu[j + 1] = pu[j];
				pv[j + 1] = pv[j];
				j--;
			}
			pu[j + 1] = u;
			pv[j + 1] = v;
		}
		if (planar || n == 1) {
			hull[0] = 0;
			hull[1] = n - 1;
			hullCount = n == 1 ? 1 : 2;
			return;
		}
		// Builds the hull with Andrew's monotone chain, and drops points on an edge.
		var k = 0;
		for (i in 0...n) {
			while (k >= 2 && cross(hull[k - 2], hull[k - 1], i) <= 1e-12)
				k--;
			hull[k++] = i;
		}
		var lower = k + 1, i = n - 2;
		while (i >= 0) {
			while (k >= lower && cross(hull[k - 2], hull[k - 1], i) <= 1e-12)
				k--;
			hull[k++] = i;
			i--;
		}
		hullCount = k > 1 ? k - 1 : k;
	}

	inline function cross(o:Int, a:Int, b:Int):Float {
		return (pu[a] - pu[o]) * (pv[b] - pv[o]) - (pv[a] - pv[o]) * (pu[b] - pu[o]);
	}

	/** Returns the signed distance from (u, v) to the edge of the support, positive inside. */
	function distance(u:Float, v:Float):Float {
		if (planar) {
			var lo:Float = pu[hull[0]], hi:Float = pu[hull[hullCount - 1]];
			return Math.min(u - lo, hi - u);
		}
		if (hullCount == 1)
			return -Math.sqrt((u - pu[hull[0]]) * (u - pu[hull[0]]) + (v - pv[hull[0]]) * (v - pv[hull[0]]));
		if (hullCount == 2)
			return -segment(u, v, hull[0], hull[1]);
		// Inside a convex anticlockwise polygon, every edge has the point on its left. The margin is the distance to the
		// nearest edge.
		var inside = true, nearest = Math.POSITIVE_INFINITY, outside = Math.POSITIVE_INFINITY;
		for (e in 0...hullCount) {
			var a = hull[e], b = hull[(e + 1) % hullCount];
			var eu:Float = pu[b] - pu[a], ev:Float = pv[b] - pv[a];
			var length = Math.sqrt(eu * eu + ev * ev);
			if (length == 0.0)
				continue;
			var side = (eu * (v - pv[a]) - ev * (u - pu[a])) / length;
			if (side < 0.0)
				inside = false;
			nearest = Math.min(nearest, side);
			outside = Math.min(outside, segment(u, v, a, b));
		}
		return inside ? nearest : -outside;
	}

	inline function segment(u:Float, v:Float, a:Int, b:Int):Float {
		var eu:Float = pu[b] - pu[a], ev:Float = pv[b] - pv[a];
		var l2 = eu * eu + ev * ev;
		var t = l2 == 0.0 ? 0.0 : ((u - pu[a]) * eu + (v - pv[a]) * ev) / l2;
		t = t < 0.0 ? 0.0 : t > 1.0 ? 1.0 : t;
		var du = u - (pu[a] + eu * t), dv = v - (pv[a] + ev * t);
		return Math.sqrt(du * du + dv * dv);
	}

	/** Returns a JSON snapshot of the measures. Equal states give equal text. */
	public function describe():String {
		inline function num(v:Float):String
			return Math.isFinite(v) ? Diagnostics.number(v) : "null";
		var out = new StringBuf();
		out.add('{"mass":${num(totalMass)},"centreOfMass":[${num(comX)},${num(comY)},${num(comZ)}],"velocity":[${num(velX)},${num(velY)},${num(velZ)}]');
		out.add(',"grounded":$grounded,"height":${num(height)},"margin":${num(margin)}');
		out.add(',"capturePoint":[${num(captureX)},${num(captureY)},${num(captureZ)}],"captureMargin":${num(captureMargin)},"support":[');
		for (i in 0...supportCount)
			out.add('${i > 0 ? "," : ""}[${num(supportX[i])},${num(supportY[i])},${num(supportZ[i])}]');
		out.add("]}");
		return out.toString();
	}
}
