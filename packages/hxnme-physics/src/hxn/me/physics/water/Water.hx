package hxn.me.physics.water;

import hxn.me.physics.diagnostics.Diagnostics;
import hxn.me.physics.geom.ConvexHull;
import hxn.me.physics.geom.MassProperties;
import hxn.me.physics.geom.ShapeDef.ShapeKind;
import hxn.Float32Buffer;
import hxn.Int32Buffer;
import hxn.me.math.Vec3;
import hxn.me.physics.core.Handles.BodyId;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.core.World;

/** Settings for `Water`; any left out take their defaults. */
typedef WaterOptions = {
	/** Height of the still surface; 0 by default. */
	?level:Float,
	/** Mass a unit volume (area, for planar shapes): 1000 by default, water in kilograms a cubic metre. */
	?density:Float,
	/**
	 * Drag, per second. Each shape is pushed toward the current, at the
	 * centre of its part under water, by `linearDrag` times the water's mass
	 * it displaces times how fast the water passes that point: a floating
	 * body's velocity closes on the current's at about `linearDrag` a second,
	 * and a current turns a wheel by its paddles. 1 by default.
	 */
	?linearDrag:Float,
	/** How fast a body's spin dies away, per second, scaled by how much of it is under; 1 by default. */
	?angularDrag:Float,
	/**
	 * Pressure drag on the faces the water runs into: each face under water
	 * is pushed along its normal by half the water's density times this
	 * coefficient times its area times the square of the water's speed into
	 * it. About 1 for a blunt face; 0, the default, leaves it off.
	 */
	?faceDrag:Float,
	/** The water's velocity. */
	?current:Array<Float>,
	/** The water's extent across the surface: min x, max x, min z, max z; unbounded by default. */
	?bounds:Array<Float>,
}

/**
 * A body of water in a physics world: it floats the bodies in it by the
 * volume of their shapes under its surface, drags each shape toward its
 * current where it is under, presses on the faces the water runs into, and
 * damps their spin. Call `apply(dt)` before each `world.step(dt)`.
 *
 * Each shape's submerged volume and its centre are found by cutting the
 * shape at the surface: exactly for boxes, prisms and hulls, whose mass uses
 * their core, and for rounded shapes from a convex tessellation scaled to
 * their exact volume. Planar shapes (no depth) float by area. A body
 * floating at rest is under by its density over the water's, as the mass
 * model and the cut agree. The surface may carry waves: a sum of
 * directional sine waves of fixed amplitude, length and speed, so the water
 * is a function of position and time and the world stays deterministic. On
 * waves each shape is cut at the surface's tangent plane under its centre.
 * Bodies count as in the water when their centre of mass is within its
 * bounds. Sleeping bodies on still water are left asleep. Allocates nothing
 * once each shape has been seen.
 */
class Water {
	public final world:World;
	public var level:Float;
	public var density:Float;
	public var linearDrag:Float;
	public var angularDrag:Float;
	public var faceDrag:Float;
	public var currentX:Float;
	public var currentY:Float;
	public var currentZ:Float;
	public var minX:Float;
	public var maxX:Float;
	public var minZ:Float;
	public var maxZ:Float;

	/** How far across from its centre of mass a body's centre of buoyancy may lie and still let it sleep. */
	public var restOffset = 1e-3;

	/** Seconds the water has been applied for; the waves move with it. */
	public var time(default, null) = 0.0;

	// Waves: amplitude, wave number (2 pi over length), direction across the surface, angular frequency and phase.
	final waves:Array<{
		amplitude:Float,
		number:Float,
		dx:Float,
		dz:Float,
		frequency:Float,
		phase:Float
	}> = [];

	// Per shape slot: its cut-up form, built when first met and rebuilt when the world's colliders change.
	final solids:Array<Null<Solid>> = [];
	var builtFor = -1;

	// Per body slot: the share of its volume under water at the last `apply`.
	final fraction:Float32Buffer;
	final wasIn:Int32Buffer;

	/** Bodies that came into the water, and that left it, at the last `apply`. */
	public final entered:Array<BodyId> = [];

	public final left:Array<BodyId> = [];

	/** Bodies the water acted on at the last `apply`. */
	public var touching(default, null) = 0;

	// Scratch for a shape's vertices in the world and their heights above the cutting plane.
	var wx:Float32Buffer;
	var wy:Float32Buffer;
	var wz:Float32Buffer;
	var above:Float32Buffer;
	var scratch = 64;
	// Each cut shape of the body being applied: volume, centre and shape slot, five numbers each.
	var cuts:Float32Buffer;
	var cutRoom = 16;
	// The body being pressed on, its step, and its velocity's lead to the step's average; the last placed shape's centre.
	var pressed = 0;
	var pressDt = 0.0;
	var aheadX = 0.0;
	var aheadY = 0.0;
	var aheadZ = 0.0;
	var centreX = 0.0;
	var centreY = 0.0;
	// The drag on the body being applied, gathered by `row`: its response to the body's motion (six by six), its push, and room to solve.
	final dragMatrix = new Float32Buffer(36);
	final dragImpulse = new Float32Buffer(6);
	final dragSystem = new Float32Buffer(42);
	// A face's part under water as a convex polygon of at most five corners, with a value at each to clip by; and room to clip into.
	final polyX = new Float32Buffer(8);
	final polyY = new Float32Buffer(8);
	final polyZ = new Float32Buffer(8);
	final polyD = new Float32Buffer(8);
	final clipX = new Float32Buffer(8);
	final clipY = new Float32Buffer(8);
	final clipZ = new Float32Buffer(8);
	final clipD = new Float32Buffer(8);
	var polyCount = 0;
	// Results of a cut: volume and the volume-weighted centre.
	var cutV = 0.0;
	var cutX = 0.0;
	var cutY = 0.0;
	var cutZ = 0.0;

	public function new(world:World, ?options:WaterOptions) {
		this.world = world;
		var o:WaterOptions = options == null ? {} : options;
		level = o.level == null ? 0.0 : o.level;
		density = o.density == null ? 1000.0 : o.density;
		linearDrag = o.linearDrag == null ? 1.0 : o.linearDrag;
		angularDrag = o.angularDrag == null ? 1.0 : o.angularDrag;
		faceDrag = o.faceDrag == null ? 0.0 : o.faceDrag;
		var c = o.current == null ? [0.0, 0.0, 0.0] : o.current;
		currentX = c[0];
		currentY = c.length > 1 ? c[1] : 0.0;
		currentZ = c.length > 2 ? c[2] : 0.0;
		var b = o.bounds;
		minX = b == null ? Math.NEGATIVE_INFINITY : b[0];
		maxX = b == null ? Math.POSITIVE_INFINITY : b[1];
		minZ = b == null ? Math.NEGATIVE_INFINITY : b[2];
		maxZ = b == null ? Math.POSITIVE_INFINITY : b[3];
		var bodies = world.bodyType.length;
		fraction = new Float32Buffer(bodies);
		wasIn = new Int32Buffer(bodies);
		wx = new Float32Buffer(64);
		wy = new Float32Buffer(64);
		wz = new Float32Buffer(64);
		above = new Float32Buffer(64);
		cuts = new Float32Buffer(cutRoom * 5);
	}

	/**
	 * Adds a wave of `amplitude` (half its height), `length` from crest to
	 * crest, travelling along (dx, dz) at `speed`; with no speed given, deep
	 * water's, sqrt(g length / 2 pi).
	 */
	public function addWave(amplitude:Float, length:Float, dx:Float = 1.0, dz:Float = 0.0, ?speed:Float, phase:Float = 0.0):Void {
		var l = Math.sqrt(dx * dx + dz * dz);
		if (l == 0.0) {
			dx = 1.0;
			l = 1.0;
		}
		var k = 2 * Math.PI / length;
		var g = Math.sqrt(world.gravity.x * world.gravity.x + world.gravity.y * world.gravity.y + world.gravity.z * world.gravity.z);
		var c = speed != null ? speed : Math.sqrt(g / k);
		waves.push({
			amplitude: amplitude,
			number: k,
			dx: dx / l,
			dz: dz / l,
			frequency: k * c,
			phase: phase
		});
	}

	/** The surface's height above (x, z) now. */
	public function heightAt(x:Float, z:Float):Float {
		var h = level;
		for (w in waves)
			h += w.amplitude * Math.sin(w.number * (w.dx * x + w.dz * z) - w.frequency * time + w.phase);
		return h;
	}

	/** How far (x, y, z) is under the surface; negative above it, and outside the water's bounds. */
	public function depthAt(x:Float, y:Float, z:Float):Float {
		if (x < minX || x > maxX || z < minZ || z > maxZ)
			return Math.NEGATIVE_INFINITY;
		return heightAt(x, z) - y;
	}

	/** The share of `body`'s volume under water at the last `apply`, 0 to 1. */
	public function submerged(body:BodyId):Float {
		return fraction[world.bodySlot(body)];
	}

	/** Floats, drags and turns the bodies in the water for a step of `dt`, then moves the waves on. */
	public function apply(dt:Float):Void {
		if (!(dt > 0.0) || !Math.isFinite(dt))
			return;
		if (builtFor != world.structureVersion) {
			for (i in 0...solids.length)
				solids[i] = null;
			builtFor = world.structureVersion;
		}
		entered.resize(0);
		left.resize(0);
		touching = 0;
		var g = world.gravity,
			gx:Float = g.x,
			gy:Float = g.y,
			gz:Float = g.z,
			moving = waves.length > 0;
		for (p in 0...world.activeBodyCount) {
			var b = world.activeBodyIds[p];
			if (world.bodyType[b] != (BodyType.Dynamic : Int)) {
				fraction[b] = 0.0;
				continue;
			}
			// A body asleep on still water stays as it settled, with the share under water it had.
			if (world.islands.isAwake[b] == 0 && !moving)
				continue;
			fraction[b] = 0.0;
			var cx:Float = world.worldCenterX[b],
				cz:Float = world.worldCenterZ[b];
			var inside = cx >= minX && cx <= maxX && cz >= minZ && cz <= maxZ;
			var volume = 0.0, total = 0.0, bx = 0.0, by = 0.0, bz = 0.0, pieces = 0;
			if (inside) {
				var s = world.firstShape[b];
				while (s >= 0) {
					var solid = solidOf(s);
					if (solid != null) {
						total += solid.volume;
						cut(solid, b, false);
						if (cutV > 0.0) {
							if (pieces == cutRoom) {
								var grown = new Float32Buffer(cutRoom * 10);
								for (i in 0...cutRoom * 5)
									grown[i] = cuts[i];
								cuts = grown;
								cutRoom *= 2;
							}
							var at = pieces * 5;
							cuts[at] = cutV;
							cuts[at + 1] = cutX / cutV;
							cuts[at + 2] = cutY / cutV;
							cuts[at + 3] = cutZ / cutV;
							cuts[at + 4] = s;
							pieces++;
						}
						volume += cutV;
						bx += cutX;
						by += cutY;
						bz += cutZ;
					}
					s = world.shapeNext[s];
				}
			}
			var share = total > 0.0 ? volume / total : 0.0;
			fraction[b] = share;
			var now = volume > 0.0 ? 1 : 0;
			if (now != wasIn[b]) {
				var id = (world.bodyGeneration[b] << 20) | b;
				if (now != 0)
					entered.push(id)
				else
					left.push(id);
				wasIn[b] = now;
			}
			if (volume <= 0.0)
				continue;
			touching++;
			if (world.islands.isAwake[b] == 0)
				world.wakeBodySlot(b);
			// Buoyancy: the weight of the water displaced, upward against gravity, at the centre of buoyancy.
			var lift = density * volume,
				ox = bx / volume,
				oy = by / volume,
				oz = bz / volume;
			impulse(b, -gx * lift * dt, -gy * lift * dt, -gz * lift * dt, ox, oy, oz);
			// Drag on each shape where it is under, then spin damping by the share under water.
			var ahead = dt * (World.SUBSTEPS + 1) / (2 * World.SUBSTEPS);
			pressed = b;
			pressDt = dt;
			aheadX = gx * ahead;
			aheadY = gy * ahead;
			aheadZ = gz * ahead;
			for (i in 0...36)
				dragMatrix[i] = 0.0;
			for (i in 0...6)
				dragImpulse[i] = 0.0;
			if (linearDrag > 0.0)
				for (k in 0...pieces)
					drag(linearDrag * density * cuts[k * 5] * dt, cuts[k * 5 + 1], cuts[k * 5 + 2], cuts[k * 5 + 3]);
			if (faceDrag > 0.0) {
				for (k in 0...pieces) {
					var solid = solids[Std.int(cuts[k * 5 + 4])];
					cut(solid, b, true);
					var t = solid.cells, n = solid.count;
					if (solid.planar)
						for (i in 0...n)
							edge(i, i + 1 == n ? 0 : i + 1);
					else
						for (f in 0...solid.cellCount)
							face(t[f * 3], t[f * 3 + 1], t[f * 3 + 2], n - 1);
				}
			}
			if (linearDrag > 0.0 || faceDrag > 0.0)
				settle();
			var spin = Math.exp(-angularDrag * share * dt);
			world.angVelX[b] = world.angVelX[b] * spin;
			world.angVelY[b] = world.angVelY[b] * spin;
			world.angVelZ[b] = world.angVelZ[b] * spin;
			// A body may sleep only where it would rest: buoyancy within a thousandth of its weight, and its centre of buoyancy under its
			// centre of mass. Elsewhere it is still bobbing or turning, slowly enough to pass for asleep, so it is kept awake.
			var weight = world.invMassY[b] > 0 ? density * volume * world.invMassY[b] : 1.0;
			var g2 = gx * gx + gy * gy + gz * gz;
			var rx = ox - world.worldCenterX[b],
				ry = oy - world.worldCenterY[b],
				rz = oz - world.worldCenterZ[b];
			var along = g2 > 0 ? (rx * gx + ry * gy + rz * gz) / g2 : 0.0;
			var sx = rx - gx * along,
				sy = ry - gy * along,
				sz = rz - gz * along;
			if (Math.abs(weight - 1.0) > 1e-3 || sx * sx + sy * sy + sz * sz > restOffset * restOffset)
				world.islands.sleepTimer[b] = 0.0;
		}
		time += dt;
	}

	/**
	 * Drag of `h` (impulse per unit of speed) at world point (px, py, pz) of
	 * body slot `pressed`, toward the current in every direction.
	 */
	function drag(h:Float, px:Float, py:Float, pz:Float):Void {
		var w = world, b = pressed;
		var rx = px - w.worldCenterX[b],
			ry = py - w.worldCenterY[b],
			rz = pz - w.worldCenterZ[b];
		var ox:Float = w.angVelX[b],
			oy:Float = w.angVelY[b],
			oz:Float = w.angVelZ[b];
		row(1, 0, 0, rx, ry, rz, h, currentX - (w.velX[b] + aheadX + oy * rz - oz * ry));
		row(0, 1, 0, rx, ry, rz, h, currentY - (w.velY[b] + aheadY + oz * rx - ox * rz));
		row(0, 0, 1, rx, ry, rz, h, currentZ - (w.velZ[b] + aheadZ + ox * ry - oy * rx));
	}

	/**
	 * Adds to the body's drag a push along unit direction (nx, ny, nz) at
	 * offset (rx, ry, rz) from its centre of mass, `h` times `s`, the water's
	 * speed along that direction there, less the body's.
	 */
	inline function row(nx:Float, ny:Float, nz:Float, rx:Float, ry:Float, rz:Float, h:Float, s:Float):Void {
		var j0 = nx, j1 = ny, j2 = nz, j3 = ry * nz - rz * ny, j4 = rz * nx - rx * nz, j5 = rx * ny - ry * nx;
		var m = dragMatrix, f = dragImpulse;
		for (i in 0...6) {
			var ji = i == 0 ? j0 : i == 1 ? j1 : i == 2 ? j2 : i == 3 ? j3 : i == 4 ? j4 : j5;
			f[i] = f[i] + h * s * ji;
			var hj = h * ji;
			m[i * 6] = m[i * 6] + hj * j0;
			m[i * 6 + 1] = m[i * 6 + 1] + hj * j1;
			m[i * 6 + 2] = m[i * 6 + 2] + hj * j2;
			m[i * 6 + 3] = m[i * 6 + 3] + hj * j3;
			m[i * 6 + 4] = m[i * 6 + 4] + hj * j4;
			m[i * 6 + 5] = m[i * 6 + 5] + hj * j5;
		}
	}

	/**
	 * Applies the drag gathered by `row` to body slot `pressed`, implicitly:
	 * the change in velocity and spin d solves (1 + M^-1 H) d = M^-1 f, with H
	 * the drag's response to the body's motion and f its push at the step's
	 * start, so every push sees the others and none overshoots.
	 */
	function settle():Void {
		var w = world, b = pressed, h = dragMatrix, f = dragImpulse, a = dragSystem;
		var mx:Float = w.invMassX[b],
			my:Float = w.invMassY[b],
			mz:Float = w.invMassZ[b];
		var i00:Float = w.invIxx[b],
			i01:Float = w.invIxy[b],
			i02:Float = w.invIxz[b],
			i11:Float = w.invIyy[b],
			i12:Float = w.invIyz[b],
			i22:Float = w.invIzz[b];
		// a = [1 + M^-1 H | M^-1 f], six rows of seven.
		for (c in 0...7) {
			var v0 = c < 6 ? h[c] : f[0],
				v1 = c < 6 ? h[6 + c] : f[1],
				v2 = c < 6 ? h[12 + c] : f[2];
			var v3 = c < 6 ? h[18 + c] : f[3],
				v4 = c < 6 ? h[24 + c] : f[4],
				v5 = c < 6 ? h[30 + c] : f[5];
			a[c] = mx * v0;
			a[7 + c] = my * v1;
			a[14 + c] = mz * v2;
			a[21 + c] = i00 * v3 + i01 * v4 + i02 * v5;
			a[28 + c] = i01 * v3 + i11 * v4 + i12 * v5;
			a[35 + c] = i02 * v3 + i12 * v4 + i22 * v5;
		}
		for (i in 0...6)
			a[i * 7 + i] = a[i * 7 + i] + 1.0;
		// Gaussian elimination with partial pivoting.
		for (c in 0...6) {
			var best = c, size = Math.abs(a[c * 7 + c]);
			for (r in c + 1...6)
				if (Math.abs(a[r * 7 + c]) > size) {
					best = r;
					size = Math.abs(a[r * 7 + c]);
				}
			if (!(size > 1e-12))
				return;
			if (best != c)
				for (k in 0...7) {
					var t:Float = a[c * 7 + k];
					a[c * 7 + k] = a[best * 7 + k];
					a[best * 7 + k] = t;
				}
			var pivot:Float = a[c * 7 + c];
			for (r in c + 1...6) {
				var factor = a[r * 7 + c] / pivot;
				if (factor != 0.0)
					for (k in c...7)
						a[r * 7 + k] = a[r * 7 + k] - factor * a[c * 7 + k];
			}
		}
		for (c in 0...6) {
			var r = 5 - c, sum:Float = a[r * 7 + 6];
			for (k in r + 1...6)
				sum -= a[r * 7 + k] * a[k * 7 + 6];
			a[r * 7 + 6] = sum / a[r * 7 + r];
		}
		w.velX[b] = w.velX[b] + a[6];
		w.velY[b] = w.velY[b] + a[13];
		w.velZ[b] = w.velZ[b] + a[20];
		w.angVelX[b] = w.angVelX[b] + a[27];
		w.angVelY[b] = w.angVelY[b] + a[34];
		w.angVelZ[b] = w.angVelZ[b] + a[41];
	}

	/** Pressure drag on the part under water of the triangle of placed points i, j, k, facing away from placed point `inner`. */
	function face(i:Int, j:Int, k:Int, inner:Int):Void {
		if (above[i] >= 0 && above[j] >= 0 && above[k] >= 0)
			return;
		var ax:Float = wx[i], ay:Float = wy[i], az:Float = wz[i];
		var ux = wx[j] - ax,
			uy = wy[j] - ay,
			uz = wz[j] - az,
			vx = wx[k] - ax,
			vy = wy[k] - ay,
			vz = wz[k] - az;
		var nx = uy * vz - uz * vy,
			ny = uz * vx - ux * vz,
			nz = ux * vy - uy * vx;
		var l = Math.sqrt(nx * nx + ny * ny + nz * nz);
		if (!(l > 1e-12))
			return;
		nx /= l;
		ny /= l;
		nz /= l;
		if ((ax + wx[j] + wx[k] - 3 * wx[inner]) * nx + (ay + wy[j] + wy[k] - 3 * wy[inner]) * ny + (az + wz[j] + wz[k] - 3 * wz[inner]) * nz < 0) {
			nx = -nx;
			ny = -ny;
			nz = -nz;
		}
		polyCount = 3;
		for (v in 0...3) {
			var p = v == 0 ? i : v == 1 ? j : k;
			polyX[v] = wx[p];
			polyY[v] = wy[p];
			polyZ[v] = wz[p];
			polyD[v] = above[p];
		}
		clip();
		press(nx, ny, nz);
	}

	/** Pressure drag on the part under water of the outline edge of placed points i, j of a planar shape, as a face of unit depth. */
	function edge(i:Int, j:Int):Void {
		if (above[i] >= 0 && above[j] >= 0)
			return;
		var ex:Float = wx[j] - wx[i],
			ey:Float = wy[j] - wy[i],
			l = Math.sqrt(ex * ex + ey * ey);
		if (!(l > 1e-12))
			return;
		var nx = ey / l, ny = -ex / l;
		if (((wx[i] + wx[j]) / 2 - centreX) * nx + ((wy[i] + wy[j]) / 2 - centreY) * ny < 0) {
			nx = -nx;
			ny = -ny;
		}
		polyCount = 2;
		polyX[0] = wx[i];
		polyY[0] = wy[i];
		polyZ[0] = wz[i];
		polyD[0] = above[i];
		polyX[1] = wx[j];
		polyY[1] = wy[j];
		polyZ[1] = wz[j];
		polyD[1] = above[j];
		clip();
		press(nx, ny, 0.0);
	}

	/** Keeps the part of the polygon (a segment when it has two points) where `polyD` is below 0. */
	function clip():Void {
		var n = polyCount, m = 0, closed = n > 2;
		for (i in 0...n) {
			var di:Float = polyD[i];
			if (di < 0) {
				clipX[m] = polyX[i];
				clipY[m] = polyY[i];
				clipZ[m] = polyZ[i];
				m++;
			}
			if (!closed && i == n - 1)
				break;
			var j = i + 1 == n ? 0 : i + 1, dj:Float = polyD[j];
			if ((di < 0) != (dj < 0)) {
				var t = di / (di - dj);
				clipX[m] = polyX[i] + (polyX[j] - polyX[i]) * t;
				clipY[m] = polyY[i] + (polyY[j] - polyY[i]) * t;
				clipZ[m] = polyZ[i] + (polyZ[j] - polyZ[i]) * t;
				m++;
			}
		}
		for (v in 0...m) {
			polyX[v] = clipX[v];
			polyY[v] = clipY[v];
			polyZ[v] = clipZ[v];
		}
		polyCount = m;
	}

	/**
	 * Pressure drag on the polygon (or segment), outward normal (nx, ny, nz),
	 * of body slot `pressed`, where the water runs into it. The water's
	 * speed into the face, s, varies linearly across it, so the push, half the
	 * density times the coefficient times the integral of s squared, and its
	 * centre of pressure are integrated exactly, and added to the body's drag
	 * as a push along the normal at that centre, with the drag's strength
	 * taken at the step's start.
	 */
	function press(nx:Float, ny:Float, nz:Float):Void {
		var w = world, b = pressed;
		var mx:Float = w.worldCenterX[b],
			my:Float = w.worldCenterY[b],
			mz:Float = w.worldCenterZ[b];
		var ox:Float = w.angVelX[b],
			oy:Float = w.angVelY[b],
			oz:Float = w.angVelZ[b];
		var vx = currentX - w.velX[b] - aheadX,
			vy = currentY - w.velY[b] - aheadY,
			vz = currentZ - w.velZ[b] - aheadZ;
		// The water's speed into the face at each corner: negative where it runs into it.
		var hit = false;
		for (v in 0...polyCount) {
			var rx = polyX[v] - mx, ry = polyY[v] - my, rz = polyZ[v] - mz;
			var s = (vx - oy * rz + oz * ry) * nx + (vy - oz * rx + ox * rz) * ny + (vz - ox * ry + oy * rx) * nz;
			polyD[v] = s;
			if (s < 0)
				hit = true;
		}
		if (!hit)
			return;
		// Where the water runs into it only: the speed at each new corner, which is 0 where it was cut.
		var n = polyCount;
		for (v in 0...n)
			clipD[v] = polyD[v];
		clip();
		var m = 0;
		for (v in 0...n) {
			var dv:Float = clipD[v];
			if (dv < 0)
				polyD[m++] = dv;
			var next = v + 1 == n ? 0 : v + 1;
			if ((n > 2 || v < n - 1) && (dv < 0) != (clipD[next] < 0))
				polyD[m++] = 0.0;
		}
		// Integrals of s squared, of the position times s squared, and of |s|, over the polygon's fan of triangles or the segment.
		var s2 = 0.0, sx = 0.0, sy = 0.0, sz = 0.0, s1 = 0.0;
		if (polyCount == 2) {
			var dx = polyX[1] - polyX[0],
				dy = polyY[1] - polyY[0],
				dz = polyZ[1] - polyZ[0],
				l = Math.sqrt(dx * dx + dy * dy + dz * dz);
			var a:Float = polyD[0], c:Float = polyD[1];
			var ja = l * (a * a / 4 + a * c / 6 + c * c / 12),
				jc = l * (c * c / 4 + a * c / 6 + a * a / 12);
			s2 = ja + jc;
			sx = polyX[0] * ja + polyX[1] * jc;
			sy = polyY[0] * ja + polyY[1] * jc;
			sz = polyZ[0] * ja + polyZ[1] * jc;
			s1 = l * -(a + c) / 2;
		} else {
			for (t in 1...polyCount - 1) {
				var ex = polyX[t] - polyX[0],
					ey = polyY[t] - polyY[0],
					ez = polyZ[t] - polyZ[0];
				var fx = polyX[t + 1] - polyX[0],
					fy = polyY[t + 1] - polyY[0],
					fz = polyZ[t + 1] - polyZ[0];
				var cx = ey * fz - ez * fy,
					cy = ez * fx - ex * fz,
					cz = ex * fy - ey * fx;
				var area = Math.sqrt(cx * cx + cy * cy + cz * cz) / 2;
				var a:Float = polyD[0],
					c:Float = polyD[t],
					e:Float = polyD[t + 1];
				// The integral over the triangle of each corner's barycentric weight times s squared.
				var ja = area * (a * a / 10 + (c * c + e * e) / 30 + (a * c + a * e) / 15 + c * e / 30);
				var jc = area * (c * c / 10 + (a * a + e * e) / 30 + (c * a + c * e) / 15 + a * e / 30);
				var je = area * (e * e / 10 + (a * a + c * c) / 30 + (e * a + e * c) / 15 + a * c / 30);
				s2 += ja + jc + je;
				sx += polyX[0] * ja + polyX[t] * jc + polyX[t + 1] * je;
				sy += polyY[0] * ja + polyY[t] * jc + polyY[t + 1] * je;
				sz += polyZ[0] * ja + polyZ[t] * jc + polyZ[t + 1] * je;
				s1 += area * -(a + c + e) / 3;
			}
		}
		if (!(s2 > 1e-18) || !(s1 > 0))
			return;
		var px = sx / s2, py = sy / s2, pz = sz / s2;
		// The push over the step, and the mean speed it acts on, as the drag a unit of speed makes there.
		var push = 0.5 * density * faceDrag * s2 * pressDt, speed = s2 / s1;
		row(nx, ny, nz, px - mx, py - my, pz - mz, push / speed, -speed);
	}

	/** An impulse at a world point on body slot `b`, as `World.applyImpulse`, without its handle checks. */
	inline function impulse(b:Int, jx:Float, jy:Float, jz:Float, px:Float, py:Float, pz:Float):Void {
		var w = world;
		w.velX[b] = w.velX[b] + jx * w.invMassX[b];
		w.velY[b] = w.velY[b] + jy * w.invMassY[b];
		w.velZ[b] = w.velZ[b] + jz * w.invMassZ[b];
		var rx = px - w.worldCenterX[b],
			ry = py - w.worldCenterY[b],
			rz = pz - w.worldCenterZ[b];
		var tx = ry * jz - rz * jy,
			ty = rz * jx - rx * jz,
			tz = rx * jy - ry * jx;
		w.angVelX[b] = w.angVelX[b] + w.invIxx[b] * tx + w.invIxy[b] * ty + w.invIxz[b] * tz;
		w.angVelY[b] = w.angVelY[b] + w.invIxy[b] * tx + w.invIyy[b] * ty + w.invIyz[b] * tz;
		w.angVelZ[b] = w.angVelZ[b] + w.invIxz[b] * tx + w.invIyz[b] * ty + w.invIzz[b] * tz;
	}

	/**
	 * Cuts shape `solid` on body slot `b` at the surface: its volume under
	 * water into `cutV`, and that volume times its centre into `cutX`..`cutZ`.
	 * With `place`, only puts its points in the world, with their heights
	 * above the cutting plane, unless it is clear of the water.
	 */
	function cut(solid:Solid, b:Int, place:Bool):Void {
		var w = world, qx:Float = w.rotX[b], qy:Float = w.rotY[b], qz:Float = w.rotZ[b], qw:Float = w.rotW[b];
		var px:Float = w.posX[b], py:Float = w.posY[b], pz:Float = w.posZ[b];
		// The body's rotation as a matrix.
		var r00 = 1 - 2 * (qy * qy + qz * qz),
			r01 = 2 * (qx * qy - qw * qz),
			r02 = 2 * (qx * qz + qw * qy);
		var r10 = 2 * (qx * qy + qw * qz),
			r11 = 1 - 2 * (qx * qx + qz * qz),
			r12 = 2 * (qy * qz - qw * qx);
		var r20 = 2 * (qx * qz - qw * qy),
			r21 = 2 * (qy * qz + qw * qx),
			r22 = 1 - 2 * (qx * qx + qy * qy);
		var lx = solid.centerX, ly = solid.centerY, lz = solid.centerZ;
		var cx = r00 * lx + r01 * ly + r02 * lz + px,
			cy = r10 * lx + r11 * ly + r12 * lz + py,
			cz = r20 * lx + r21 * ly + r22 * lz + pz;
		// The cutting plane: the surface, or its tangent plane under the shape's centre.
		var nx = 0.0, ny = 1.0, nz = 0.0, h = level;
		if (waves.length > 0) {
			var sx = 0.0, sz = 0.0;
			for (wave in waves) {
				var a = wave.number * (wave.dx * cx + wave.dz * cz) - wave.frequency * time + wave.phase;
				h += wave.amplitude * Math.sin(a);
				var slope = wave.amplitude * wave.number * Math.cos(a);
				sx += slope * wave.dx;
				sz += slope * wave.dz;
			}
			var l = Math.sqrt(sx * sx + 1 + sz * sz);
			nx = -sx / l;
			ny = 1 / l;
			nz = -sz / l;
		}
		// Height of the shape's centre above the plane through (cx, h, cz).
		var centre = (cy - h) * ny;
		cutV = 0.0;
		cutX = 0.0;
		cutY = 0.0;
		cutZ = 0.0;
		centreX = cx;
		centreY = cy;
		if (centre >= solid.reach)
			return;
		if (centre <= -solid.reach && !place) {
			cutV = solid.volume;
			cutX = cx * solid.volume;
			cutY = cy * solid.volume;
			cutZ = cz * solid.volume;
			return;
		}
		var n = solid.count;
		if (n > scratch) {
			scratch = n;
			wx = new Float32Buffer(n);
			wy = new Float32Buffer(n);
			wz = new Float32Buffer(n);
			above = new Float32Buffer(n);
		}
		var v = solid.points;
		for (i in 0...n) {
			var x:Float = v[i * 3],
				y:Float = v[i * 3 + 1],
				z:Float = v[i * 3 + 2];
			var X = r00 * x + r01 * y + r02 * z + px,
				Y = r10 * x + r11 * y + r12 * z + py,
				Z = r20 * x + r21 * y + r22 * z + pz;
			wx[i] = X;
			wy[i] = Y;
			wz[i] = Z;
			above[i] = (X - cx) * nx + (Y - h) * ny + (Z - cz) * nz;
		}
		if (place)
			return;
		var t = solid.cells;
		if (solid.planar) {
			for (k in 0...solid.cellCount)
				triangle(t[k * 3], t[k * 3 + 1], t[k * 3 + 2]);
		} else {
			// Tetrahedra fanned from the centre, which is the last point.
			for (k in 0...solid.cellCount)
				tetrahedron(t[k * 3], t[k * 3 + 1], t[k * 3 + 2], n - 1);
		}
	}

	/** Adds the part below the plane of the triangle of scratch points a, b, c. */
	function triangle(a:Int, b:Int, c:Int):Void {
		var da:Float = above[a], db:Float = above[b], dc:Float = above[c];
		var under = (da < 0 ? 1 : 0) + (db < 0 ? 1 : 0) + (dc < 0 ? 1 : 0);
		if (under == 0)
			return;
		var z:Float = wz[a];
		if (under == 3) {
			addTriangle(wx[a], wy[a], wx[b], wy[b], wx[c], wy[c], z, 1.0);
			return;
		}
		// Rotate so `a` is the odd one out: alone below (one under) or alone above (two under).
		var lone = under == 1 ? (da < 0 ? a : db < 0 ? b : c) : (da >= 0 ? a : db >= 0 ? b : c);
		var o1 = lone == a ? b : lone == b ? c : a,
			o2 = lone == a ? c : lone == b ? a : b;
		var d0:Float = above[lone], d1:Float = above[o1], d2:Float = above[o2];
		var t1 = d0 / (d0 - d1), t2 = d0 / (d0 - d2);
		var x1 = wx[lone] + (wx[o1] - wx[lone]) * t1,
			y1 = wy[lone] + (wy[o1] - wy[lone]) * t1;
		var x2 = wx[lone] + (wx[o2] - wx[lone]) * t2,
			y2 = wy[lone] + (wy[o2] - wy[lone]) * t2;
		if (under == 1)
			addTriangle(wx[lone], wy[lone], x1, y1, x2, y2, z, 1.0);
		else {
			addTriangle(wx[a], wy[a], wx[b], wy[b], wx[c], wy[c], z, 1.0);
			addTriangle(wx[lone], wy[lone], x1, y1, x2, y2, z, -1.0);
		}
	}

	inline function addTriangle(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float, z:Float, sign:Float):Void {
		var area = Math.abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) * 0.5 * sign;
		cutV += area;
		cutX += area * (ax + bx + cx) / 3;
		cutY += area * (ay + by + cy) / 3;
		cutZ += area * z;
	}

	// Points where edges meet the plane, three numbers each, for the pieces of a cut tetrahedron.
	final crossing = new Float32Buffer(12);

	/** Where the edge from scratch point `i` to `j` meets the plane, into crossing point `slot`. */
	inline function meet(i:Int, j:Int, slot:Int):Void {
		var di:Float = above[i], dj:Float = above[j], t = di / (di - dj);
		crossing[slot * 3] = wx[i] + (wx[j] - wx[i]) * t;
		crossing[slot * 3 + 1] = wy[i] + (wy[j] - wy[i]) * t;
		crossing[slot * 3 + 2] = wz[i] + (wz[j] - wz[i]) * t;
	}

	/** Adds the part below the plane of the tetrahedron of scratch points a, b, c, d. */
	function tetrahedron(a:Int, b:Int, c:Int, d:Int):Void {
		var ua = above[a] < 0,
			ub = above[b] < 0,
			uc = above[c] < 0,
			ud = above[d] < 0;
		var under = (ua ? 1 : 0) + (ub ? 1 : 0) + (uc ? 1 : 0) + (ud ? 1 : 0);
		if (under == 0)
			return;
		var x = wx, y = wy, z = wz, k = crossing;
		if (under == 4) {
			tet(x[a], y[a], z[a], x[b], y[b], z[b], x[c], y[c], z[c], x[d], y[d], z[d], 1.0);
			return;
		}
		if (under == 1 || under == 3) {
			// One vertex alone on its side: the small tetrahedron at it, added (alone below) or taken from the whole (alone above).
			var alone = under == 1;
			var lone = ua == alone ? a : ub == alone ? b : uc == alone ? c : d;
			var o1 = lone == a ? b : a,
				o2 = lone == a || lone == b ? c : b,
				o3 = lone == d ? c : d;
			meet(lone, o1, 0);
			meet(lone, o2, 1);
			meet(lone, o3, 2);
			if (!alone)
				tet(x[a], y[a], z[a], x[b], y[b], z[b], x[c], y[c], z[c], x[d], y[d], z[d], 1.0);
			tet(x[lone], y[lone], z[lone], k[0], k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8], alone ? 1.0 : -1.0);
			return;
		}
		// Two below (u0, u1) and two above (o0, o1): a wedge between triangles u0 / c00 / c01 and u1 / c10 / c11, as three tetrahedra.
		var u0 = ua ? a : ub ? b : c,
			u1 = ud ? d : uc && u0 != c ? c : ub && u0 != b ? b : c;
		var o0 = !ua ? a : !ub ? b : c,
			o1 = !ud ? d : !uc && o0 != c ? c : !ub && o0 != b ? b : c;
		meet(u0, o0, 0);
		meet(u0, o1, 1);
		meet(u1, o0, 2);
		meet(u1, o1, 3);
		tet(x[u0], y[u0], z[u0], k[0], k[1], k[2], k[3], k[4], k[5], k[9], k[10], k[11], 1.0);
		tet(x[u0], y[u0], z[u0], k[0], k[1], k[2], k[9], k[10], k[11], k[6], k[7], k[8], 1.0);
		tet(x[u0], y[u0], z[u0], k[6], k[7], k[8], k[9], k[10], k[11], x[u1], y[u1], z[u1], 1.0);
	}

	inline function tet(ax:Float, ay:Float, az:Float, bx:Float, by:Float, bz:Float, cx:Float, cy:Float, cz:Float, dx:Float, dy:Float, dz:Float,
			sign:Float):Void {
		var ux = bx - ax, uy = by - ay, uz = bz - az, vx = cx - ax, vy = cy - ay, vz = cz - az, qx = dx - ax, qy = dy - ay, qz = dz - az;
		var v = Math.abs(ux * (vy * qz - vz * qy) - uy * (vx * qz - vz * qx) + uz * (vx * qy - vy * qx)) / 6 * sign;
		cutV += v;
		cutX += v * (ax + bx + cx + dx) / 4;
		cutY += v * (ay + by + cy + dy) / 4;
		cutZ += v * (az + bz + cz + dz) / 4;
	}

	/** Shape slot `s`'s cut-up form, built on first use. */
	function solidOf(s:Int):Null<Solid> {
		while (solids.length <= s)
			solids.push(null);
		var solid = solids[s];
		if (solid == null) {
			solid = Solid.of(world, s);
			solids[s] = solid;
		}
		return solid.volume > 0 ? solid : null;
	}

	/** Every problem with the settings. */
	public function validate():Diagnostics {
		var d = new Diagnostics();
		if (!(density > 0) || !Math.isFinite(density))
			d.error("WATER_DENSITY", "water/density", 'The water\'s density is $density.', "above 0", '$density');
		if (!(linearDrag >= 0) || !(angularDrag >= 0) || !(faceDrag >= 0) || !Math.isFinite(linearDrag + angularDrag + faceDrag))
			d.error("WATER_DRAG", "water/drag", 'Drag is $linearDrag linear, $angularDrag angular and $faceDrag on faces.', "0 or more",
				'$linearDrag, $angularDrag, $faceDrag');
		if (!Math.isFinite(level) || !Math.isFinite(currentX + currentY + currentZ))
			d.error("WATER_VALUE", "water", 'Level $level, current $currentX, $currentY, $currentZ.', "finite numbers", "");
		if (minX > maxX || minZ > maxZ)
			d.error("WATER_BOUNDS", "water/bounds", 'Bounds $minX to $maxX across x and $minZ to $maxZ across z.', "minimum first", "");
		for (i in 0...waves.length) {
			var w = waves[i];
			if (!Math.isFinite(w.amplitude + w.number + w.frequency) || !(w.number > 0))
				d.error("WATER_WAVE", 'water/waves/$i', 'Wave $i has amplitude ${w.amplitude} and wave number ${w.number}.', "finite, with a positive length",
					"");
		}
		return d;
	}

	/** The water as JSON: settings, waves and what it touched at the last `apply`. */
	public function describe():String {
		inline function n(v:Float):String
			return Diagnostics.number(v);
		return
			'{"level":${n(level)},"density":${n(density)},"drag":[${n(linearDrag)},${n(angularDrag)},${n(faceDrag)}],"current":[${n(currentX)},${n(currentY)},${n(currentZ)}]'
			+
			',"bounds":[${n(minX)},${n(maxX)},${n(minZ)},${n(maxZ)}],"time":${n(time)},"waves":[${[for (w in waves) '{"amplitude":${n(w.amplitude)},"length":${n(2 * Math.PI / w.number)},"direction":[${n(w.dx)},${n(w.dz)}],"speed":${n(w.frequency / w.number)}}'].join(",")}]'
			+ ',"touching":$touching,"entered":${entered.length},"left":${left.length}}';
	}
}

/**
 * A shape cut into simple pieces for finding what lies under a plane:
 * triangles for a planar shape, tetrahedra fanned from its centre for a
 * solid, over points in the body's frame scaled about the centre so their
 * volume is the shape's exact volume. `reach` bounds every point's distance
 * from the centre.
 */
private class Solid {
	public var planar = false;

	/** Points, three numbers each; a solid's last point is its centre. */
	public var points:Float32Buffer;

	public var count = 0;

	/** Triangles, as three point indices each: a planar shape's pieces, or a solid's surface. */
	public var cells:Int32Buffer;

	public var cellCount = 0;
	public var volume = 0.0;
	public var centerX = 0.0;
	public var centerY = 0.0;
	public var centerZ = 0.0;
	public var reach = 0.0;

	function new() {}

	/** Rounding of a rounded shape: points around a circle, and rings of points on a sphere. */
	static inline var AROUND = 24;

	static inline var RINGS = 8;

	public static function of(w:World, s:Int):Solid {
		var solid = new Solid();
		var kind:Int = w.shapeKind[s],
			depth:Float = w.shapeDepth[s],
			radius:Float = w.shapeRadius[s],
			localZ:Float = w.shapeLocalZ[s];
		var offset = w.shapeVertOffset[s], count = w.shapeVertCount[s], pool = w.verts;
		var planar = depth == 0.0 && kind != (Hull : Int);
		solid.planar = planar;
		var exact:Float;
		var cloud:Array<Vec3> = [];
		if (planar) {
			// The outline, convex and anticlockwise, as triangles fanned from its first point.
			var outline:Array<Float> = [];
			if (kind == (Polygon : Int)) {
				for (i in 0...count) {
					outline.push(pool.vx[offset + i]);
					outline.push(pool.vy[offset + i]);
				}
				exact = MassProperties.polygon(pool, offset, count, 0, 0, 1).mass;
			} else {
				var ax = 0.0, ay = 0.0, bx = 0.0, by = 0.0;
				if (kind == (Segment : Int)) {
					ax = pool.vx[offset];
					ay = pool.vy[offset];
					bx = pool.vx[offset + 1];
					by = pool.vy[offset + 1];
				}
				var dir = Math.atan2(by - ay, bx - ax);
				// Half circle round b, then half circle round a: a stadium, or a circle when a and b meet.
				for (k in 0...AROUND + 1) {
					var t = dir - Math.PI / 2 + Math.PI * k / AROUND;
					outline.push(bx + Math.cos(t) * radius);
					outline.push(by + Math.sin(t) * radius);
				}
				for (k in 0...AROUND + 1) {
					var t = dir + Math.PI / 2 + Math.PI * k / AROUND;
					outline.push(ax + Math.cos(t) * radius);
					outline.push(ay + Math.sin(t) * radius);
				}
				var length = Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
				exact = 2 * radius * length + Math.PI * radius * radius;
			}
			var n = Std.int(outline.length / 2);
			// Anticlockwise, so the fan's areas are positive; the area and centroid of the outline as drawn.
			var twice = 0.0, cx = 0.0, cy = 0.0;
			for (i in 0...n) {
				var j = (i + 1) % n,
					x0 = outline[i * 2],
					y0 = outline[i * 2 + 1],
					x1 = outline[j * 2],
					y1 = outline[j * 2 + 1];
				var c = x0 * y1 - x1 * y0;
				twice += c;
				cx += (x0 + x1) * c;
				cy += (y0 + y1) * c;
			}
			if (Math.abs(twice) < 1e-18 || !(exact > 0))
				return solid;
			cx /= 3 * twice;
			cy /= 3 * twice;
			var scale = Math.sqrt(exact / (Math.abs(twice) / 2));
			solid.points = new Float32Buffer(n * 3);
			for (i in 0...n) {
				solid.points[i * 3] = cx + (outline[i * 2] - cx) * scale;
				solid.points[i * 3 + 1] = cy + (outline[i * 2 + 1] - cy) * scale;
				solid.points[i * 3 + 2] = localZ;
				solid.reach = Math.max(solid.reach, Math.sqrt(Math.pow(solid.points[i * 3] - cx, 2) + Math.pow(solid.points[i * 3 + 1] - cy, 2)));
			}
			solid.count = n;
			solid.cellCount = n - 2;
			solid.cells = new Int32Buffer(solid.cellCount * 3);
			for (k in 0...n - 2) {
				solid.cells[k * 3] = 0;
				solid.cells[k * 3 + 1] = k + 1;
				solid.cells[k * 3 + 2] = k + 2;
			}
			solid.volume = exact;
			solid.centerX = cx;
			solid.centerY = cy;
			solid.centerZ = localZ;
			return solid;
		}
		if (kind == (Hull : Int)) {
			for (i in 0...count)
				cloud.push(new Vec3(pool.vx[offset + i], pool.vy[offset + i], pool.vz[offset + i] + localZ));
			exact = MassProperties.hull(pool, offset, count, localZ, 1).mass;
		} else if (kind == (Polygon : Int)) {
			for (side in [-0.5, 0.5])
				for (i in 0...count)
					cloud.push(new Vec3(pool.vx[offset + i], pool.vy[offset + i], localZ + side * depth));
			exact = MassProperties.polygon(pool, offset, count, depth, localZ, 1).mass;
		} else {
			// A segment (or a point) swept along Z by the depth, rounded by the radius: spheres at the four ends of that core.
			var ax = 0.0, ay = 0.0, bx = 0.0, by = 0.0;
			if (kind == (Segment : Int)) {
				ax = pool.vx[offset];
				ay = pool.vy[offset];
				bx = pool.vx[offset + 1];
				by = pool.vy[offset + 1];
			}
			var ends = kind == (Segment : Int) ? [[ax, ay], [bx, by]] : [[0.0, 0.0]];
			// Only each end's outward half: the inner halves lie inside the hull, and their poles can meet.
			for (e in ends)
				for (side in [-0.5, 0.5]) {
					cloud.push(new Vec3(e[0], e[1], localZ + side * depth + (side > 0 ? radius : -radius)));
					for (ring in 1...RINGS) {
						var polar = Math.PI * ring / RINGS,
							rz = Math.cos(polar) * radius,
							rr = Math.sin(polar) * radius;
						if (side < 0 ? polar < Math.PI / 2 : polar > Math.PI / 2)
							continue;
						for (k in 0...AROUND) {
							var t = 2 * Math.PI * k / AROUND;
							cloud.push(new Vec3(e[0] + Math.cos(t) * rr, e[1] + Math.sin(t) * rr, localZ + side * depth + rz));
						}
					}
				}
			exact = (kind == (Segment : Int) ? MassProperties.capsule(pool, offset, radius, depth, localZ,
				1) : MassProperties.point(radius, depth, localZ, 1)).mass;
		}
		if (!(exact > 0) || cloud.length < 4)
			return solid;
		var faces = ConvexHull.triangles(cloud);
		// The hull's own volume and centroid, from tetrahedra fanned from its first point.
		var o = cloud[0], hv = 0.0, sx = 0.0, sy = 0.0, sz = 0.0;
		for (f in 0...Std.int(faces.length / 3)) {
			var a = cloud[faces[f * 3]],
				b = cloud[faces[f * 3 + 1]],
				c = cloud[faces[f * 3 + 2]];
			var ux = a.x - o.x, uy = a.y - o.y, uz = a.z - o.z, vx = b.x - o.x, vy = b.y - o.y, vz = b.z - o.z, qx = c.x - o.x, qy = c.y - o.y, qz = c.z - o.z;
			var v = (ux * (vy * qz - vz * qy) - uy * (vx * qz - vz * qx) + uz * (vx * qy - vy * qx)) / 6;
			hv += v;
			sx += v * (o.x + a.x + b.x + c.x) / 4;
			sy += v * (o.y + a.y + b.y + c.y) / 4;
			sz += v * (o.z + a.z + b.z + c.z) / 4;
		}
		if (!(Math.abs(hv) > 1e-18))
			return solid;
		var cx = sx / hv, cy = sy / hv, cz = sz / hv, scale = Math.pow(exact / Math.abs(hv), 1 / 3);
		var n = cloud.length;
		solid.points = new Float32Buffer((n + 1) * 3);
		for (i in 0...n) {
			var p = cloud[i];
			solid.points[i * 3] = cx + (p.x - cx) * scale;
			solid.points[i * 3 + 1] = cy + (p.y - cy) * scale;
			solid.points[i * 3 + 2] = cz + (p.z - cz) * scale;
			solid.reach = Math.max(solid.reach, Math.sqrt(Math.pow(p.x - cx, 2) + Math.pow(p.y - cy, 2) + Math.pow(p.z - cz, 2)) * scale);
		}
		solid.points[n * 3] = cx;
		solid.points[n * 3 + 1] = cy;
		solid.points[n * 3 + 2] = cz;
		solid.count = n + 1;
		solid.cellCount = Std.int(faces.length / 3);
		solid.cells = new Int32Buffer(faces.length);
		for (i in 0...faces.length)
			solid.cells[i] = faces[i];
		solid.volume = exact;
		solid.centerX = cx;
		solid.centerY = cy;
		solid.centerZ = cz;
		return solid;
	}
}
