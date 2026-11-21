import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.Handles.BodyId;
import hxn.me.physics.core.World;
import hxn.me.physics.water.Water;

/**
 * Water against analytic answers: the share of a shape under a surface for
 * a tilted cube, a lying pill and a disc at known depths; floating bodies
 * settling under by their density over the water's, in 2D and 3D; sinking
 * and rising; drag toward the current and damped spin; a current turning
 * a paddle wheel by drag where each paddle is under; pressure on faces
 * against a flat plate's exact drag, and a rotor under water turned by its
 * angled blades; enter and leave events; a float bobbing with a wave's period; replays bit for bit; sleep;
 * no allocation; findings.
 */
class WaterChecks {
	static inline var DT = 1.0 / 60.0;

	static function near(actual:Float, expected:Float, label:String, tolerance:Float):Void {
		if (!(Math.abs(actual - expected) <= tolerance)) throw '$label: expected $expected, got $actual';
	}

	/** A wide, shallow slab, 2 by 0.4 by 2: unlike a cube, it floats upright at any density. */
	static function slab(world:World, x:Float, y:Float, density:Float, planar:Bool = false):BodyId {
		var body = world.createBody(Dynamic, x, y, 0);
		world.attachShape(body, ShapeBuilder.makeBox(world.verts, 1, 0.2, planar ? 0 : 2, 0.01, 0, density));
		return body;
	}

	static function cube(world:World, x:Float, y:Float, density:Float, planar:Bool = false):BodyId {
		var body = world.createBody(Dynamic, x, y, 0);
		world.attachShape(body, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, planar ? 0 : 1, 0.01, 0, density));
		return body;
	}

	/** The share of `body` under still water at level 0, before anything moves. */
	static function share(world:World, body:BodyId):Float {
		var water = new Water(world);
		water.apply(DT);
		return water.submerged(body);
	}

	static function cutting():Void {
		// A cube turned 45 degrees about Z and about X, centre at the surface: half under, by symmetry, through every way a tetrahedron is cut.
		var world = new World(4, 4);
		var body = cube(world, 0, 0, 500);
		world.teleportBody(body, new Vec3(0, 0, 0), new Quat(0.3535534, 0, 0.3535534, 0.8660254));
		near(share(world, body), 0.5, "a turned cube centred on the surface", 1e-5);
		// A cube with its bottom 0.3 under: 0.3 of it.
		world.teleportBody(body, new Vec3(0, 0.2, 0), new Quat());
		near(share(world, body), 0.3, "an upright cube 0.3 under", 1e-5);
		// A pill lying along Z (radius 0.5, straight length 1) at several depths, against the exact cylinder segment and sphere cap.
		var r = 0.5, length = 1.0, worst = 0.0;
		var pill = world.createBody(Dynamic, 10, 0, 0);
		world.attachShape(pill, ShapeBuilder.makeCircle(r, length, 0, 500));
		for (h in [0.1, 0.25, 0.5, 0.8, 0.95]) {
			// h of the diameter under: the bottom at -h * 2r.
			world.teleportBody(pill, new Vec3(10, r - h * 2 * r, 0), new Quat());
			var depth = h * 2 * r, theta = 2 * Math.acos((r - depth) / r);
			var segment = r * r * (theta - Math.sin(theta)) / 2, cap = Math.PI * depth * depth * (3 * r - depth) / 3;
			var exact = (segment * length + cap) / (Math.PI * r * r * length + 4 / 3 * Math.PI * r * r * r);
			var got = share(world, pill);
			worst = Math.max(worst, Math.abs(got - exact));
		}
		if (worst > 2e-3) throw 'a lying pill strays $worst from the exact share';
		// A planar disc a quarter under, against the circular segment.
		var flat = new World(4, 4);
		var disc = flat.createBody(Dynamic, 0, 0.25, 0);
		flat.attachShape(disc, ShapeBuilder.makeCircle(0.5, 0, 0, 500));
		var theta = 2 * Math.acos(0.5 / 0.5 - 0.5);
		var exactDisc = (0.25 * (theta - Math.sin(theta)) / 2) / (Math.PI * 0.25);
		near(share(flat, disc), exactDisc, "a disc a quarter under", 2e-3);
		Sys.println('water: a turned cube on the surface is half under; an upright one 0.3 under is 0.3; a lying pill within $worst '
			+ 'of the exact share at five depths; a disc a quarter under within 0.002');
	}

	/** Steps `world` with `water` for `seconds`. */
	static function simulate(world:World, water:Water, seconds:Float):Void {
		for (_ in 0...Math.round(seconds / DT)) { water.apply(DT); world.step(DT); }
	}

	static function floating():Void {
		for (planar in [false, true]) for (density in [250.0, 500.0, 800.0]) {
			var world = new World(4, 4);
			// Let go with its bottom on the surface; drag damps the bobbing by e^(-drag * share * t / 2).
			var body = slab(world, 0, 0.2, density, planar);
			var water = new Water(world, {linearDrag: 3, angularDrag: 3});
			simulate(world, water, 30);
			var label = '${planar ? "planar" : "spatial"} slab of density $density';
			near(water.submerged(body), density / 1000, '$label under by density over the water\'s', 2e-3);
			// Its bottom is the draft, 0.4 times the density over the water's, under the surface.
			near(world.posY[world.bodySlot(body)], 0.2 - 0.4 * density / 1000, '$label floats at its draft', 2e-3);
		}
		// Heavier than water: down it goes, all of it under.
		var world = new World(4, 4);
		var floor = world.createBody(Static, 0, -5.5, 0);
		world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 10, 0.5, 10, 0.01));
		var stone = cube(world, 0, 0, 2500);
		var water = new Water(world);
		simulate(world, water, 10);
		if (!(world.posY[world.bodySlot(stone)] < -4.4) || water.submerged(stone) < 0.999) throw 'a stone ended at ${world.posY[world.bodySlot(stone)]}';
		// Lighter than water, let go below: up it comes and floats.
		var cork = slab(world, 3, -3, 400);
		water.linearDrag = 3; water.angularDrag = 3;
		simulate(world, water, 30);
		near(water.submerged(cork), 0.4, "a cork let go under water floats at its draft", 2e-3);
		Sys.println("water: slabs float under by density over the water's at 250, 500 and 800, in 2D and 3D; stones sink; corks rise and float");
	}

	static function currentAndSpin():Void {
		var world = new World(4, 4);
		var body = slab(world, 0, 0, 500);
		var water = new Water(world, {current: [1, 0, 0.5], linearDrag: 3, angularDrag: 3});
		var b = world.bodySlot(body);
		world.angVelY[b] = 5;
		simulate(world, water, 15);
		near(world.velX[b], 1, "drift along the current", 0.01);
		near(world.velZ[b], 0.5, "drift across with the current", 0.01);
		if (Math.abs(world.angVelY[b]) > 0.01) throw 'spin was not damped: ${world.angVelY[b]}';
		Sys.println("water: a float drifts with the current and its spin dies away");
	}

	/**
	 * A wheel of eight paddles on a hinge, its axle 0.9 above the surface and
	 * its paddles reaching 1.3 from it, in a current along x; its average turn
	 * rate over the last of `seconds`.
	 */
	static function wheel(current:Float, drag:Float, seconds:Float, planar:Bool = false):Float {
		var world = new World(4, 16);
		var axle = world.createBody(Static, 0, 0.9);
		var wheel = world.createBody(Dynamic, 0, 0.9);
		for (i in 0...8) {
			var a = Math.PI * i / 4 - Math.PI / 2, cx = Math.cos(a), cy = Math.sin(a);
			world.attachShape(wheel, ShapeBuilder.makePolygon(world.verts, [new Vec3(cx * 0.3 + cy * 0.05, cy * 0.3 - cx * 0.05), new Vec3(cx * 1.3 + cy * 0.05, cy * 1.3 - cx * 0.05),
				new Vec3(cx * 1.3 - cy * 0.05, cy * 1.3 + cx * 0.05), new Vec3(cx * 0.3 - cy * 0.05, cy * 0.3 + cx * 0.05)], planar ? 0 : 1, 0.01, 0, 600));
		}
		world.createHingeJoint(axle, wheel, new Vec3(0, 0.9, 0), new Vec3(0, 0, 1));
		var water = new Water(world, {current: [current, 0, 0], linearDrag: drag, angularDrag: 0});
		var b = world.bodySlot(wheel), steps = Math.round(seconds / DT), last = Math.round(4 / DT), sum = 0.0;
		for (k in 0...steps) {
			water.apply(DT); world.step(DT);
			if (k >= steps - last) sum += world.angVelZ[b];
			if (!Math.isFinite(world.angVelZ[b])) throw 'a wheel at drag $drag spun up to ${world.angVelZ[b]}';
		}
		return sum / last;
	}

	/**
	 * One step of drag on a turned, spinning body with a shape under water
	 * off its centre of mass and one clear of it, gravity off: the impulse it
	 * took must be the drag at the end of the step, linearDrag times the water
	 * displaced times the current less that shape centre's velocity then.
	 */
	static function implicitDrag():Void {
		var world = new World(4, 4);
		world.gravity = new Vec3(0, 0, 0);
		var body = world.createBody(Dynamic, 0, -3, 0);
		function box(x:Float, y:Float, z:Float, h:Float) return ShapeBuilder.makePolygon(world.verts, [new Vec3(x - h, y - h), new Vec3(x + h, y - h), new Vec3(x + h, y + h), new Vec3(x - h, y + h)], 2 * h, 0.01, z, 700);
		world.attachShape(body, box(0.5, -0.2, 0.3, 0.3));
		world.attachShape(body, box(-0.6, 4.5, -0.2, 0.3));
		var s = Math.sin(0.25) / Math.sqrt(14);
		world.teleportBody(body, new Vec3(0, -3, 0), new Quat(s, 2 * s, 3 * s, Math.cos(0.25)));
		var b = world.bodySlot(body);
		world.velX[b] = 0.4; world.velY[b] = -0.3; world.velZ[b] = 0.2;
		world.angVelX[b] = 1.5; world.angVelY[b] = -0.7; world.angVelZ[b] = 2.2;
		var water = new Water(world, {current: [1.2, 0, -0.5], linearDrag: 40, angularDrag: 0});
		var v0 = [world.velX[b], world.velY[b], world.velZ[b]], w0 = [world.angVelX[b], world.angVelY[b], world.angVelZ[b]];
		water.apply(DT);
		// The submerged shape's centre, (0.5, -0.2, 0.3) in the body, from the centre of mass.
		var q = new Quat(world.rotX[b], world.rotY[b], world.rotZ[b], world.rotW[b]);
		var c = Quat.rotate(q, new Vec3(0.5, -0.2, 0.3));
		var rx = c.x + world.posX[b] - world.worldCenterX[b], ry = c.y + world.posY[b] - world.worldCenterY[b], rz = c.z + world.posZ[b] - world.worldCenterZ[b];
		var ox:Float = world.angVelX[b], oy:Float = world.angVelY[b], oz:Float = world.angVelZ[b];
		var px = world.velX[b] + oy * rz - oz * ry, py = world.velY[b] + oz * rx - ox * rz, pz = world.velZ[b] + ox * ry - oy * rx;
		var strength = 40 * 1000 * 0.6 * 0.6 * 0.6 * DT, mass = 1 / world.invMassX[b];
		var taken = [for (i in 0...3) mass * ([world.velX[b], world.velY[b], world.velZ[b]][i] - v0[i])];
		var wanted = [strength * (1.2 - px), strength * (0 - py), strength * (-0.5 - pz)];
		if (Math.abs(water.submerged(body) - 0.5) > 1e-6) throw 'one of two equal shapes under, but the share is ${water.submerged(body)}';
		for (i in 0...3) near(taken[i], wanted[i], 'drag impulse component $i', 1e-4 * Math.abs(wanted[i]) + 1e-6);
		// And it turned the body as that impulse at that point would: the spin's change is the inverse inertia times r x J.
		var tx = ry * taken[2] - rz * taken[1], ty = rz * taken[0] - rx * taken[2], tz = rx * taken[1] - ry * taken[0];
		var turned = [world.invIxx[b] * tx + world.invIxy[b] * ty + world.invIxz[b] * tz, world.invIxy[b] * tx + world.invIyy[b] * ty + world.invIyz[b] * tz,
			world.invIxz[b] * tx + world.invIyz[b] * ty + world.invIzz[b] * tz];
		var spun = [ox - w0[0], oy - w0[1], oz - w0[2]];
		for (i in 0...3) near(spun[i], turned[i], 'drag spin component $i', 1e-4 * Math.abs(turned[i]) + 1e-6);
		Sys.println("water: drag on a turned, spinning body is the drag at the end of the step, at the centre of its part under water");
	}

	static function waterWheel():Void {
		for (planar in [false, true]) {
			var label = planar ? "planar" : "spatial";
			var still = wheel(0, 4, 4, planar), slow = wheel(1, 4, 20, planar), fast = wheel(2, 4, 20, planar);
			if (Math.abs(still) > 1e-4) throw '$label wheel turned in still water at $still';
			// The bottom paddles move with the current: a turn about +z for a current along +x.
			if (!(slow > 0.1)) throw '$label wheel did not turn with the current: $slow';
			// With no load and drag in proportion to speed, twice the current turns it twice as fast.
			near(fast / slow, 2, '$label wheel speed against current', 0.03);
			// Drag far stronger than the step can follow is still stable: the paddles never outrun the water.
			var stiff = wheel(1, 10000, 6, planar);
			if (!(stiff > 0 && stiff * 0.9 < 1)) throw '$label wheel under strong drag turned at $stiff';
		}
		Sys.println("water: a current turns a paddle wheel the way it runs, twice as fast in twice the current, and stays stable under any drag");
	}

	/**
	 * The impulse one apply gives a still, heavy plate under water in a
	 * current of 2 along x, gravity off and only face drag on: the plate's
	 * faces span (w, h, d), turned by `rotation`.
	 */
	static function plateImpulse(w:Float, h:Float, d:Float, rotation:Quat, planar:Bool, y:Float = -3):Vec3 {
		var world = new World(2, 2);
		world.gravity = new Vec3(0, 0, 0);
		var body = world.createBody(Dynamic, 0, y, 0);
		// Heavy enough that its own motion over the step changes the drag by under a ten thousandth.
		world.attachShape(body, ShapeBuilder.makeBox(world.verts, w / 2, h / 2, planar ? 0 : d, 0.01, 0, 1e7));
		world.teleportBody(body, new Vec3(0, y, 0), rotation);
		var water = new Water(world, {current: [2, 0, 0], linearDrag: 0, angularDrag: 0, faceDrag: 1.2});
		water.apply(DT);
		var b = world.bodySlot(body), m = 1 / world.invMassX[b];
		return new Vec3(m * world.velX[b], m * world.velY[b], m * world.velZ[b]);
	}

	/**
	 * The angular impulse about y one apply gives a heavy plate, 1 square and
	 * 0.02 thick facing x, spinning at `spin` about y in still water, with
	 * only face drag on.
	 */
	static function spinningPlate(spin:Float, planar:Bool):Float {
		var world = new World(2, 2);
		world.gravity = new Vec3(0, 0, 0);
		var body = world.createBody(Dynamic, 0, -3, 0);
		world.attachShape(body, ShapeBuilder.makeBox(world.verts, 0.01, 0.5, planar ? 0 : 1, 0.01, 0, 1e7));
		var b = world.bodySlot(body);
		world.angVelY[b] = spin;
		var water = new Water(world, {linearDrag: 0, angularDrag: 0, faceDrag: 1.2});
		water.apply(DT);
		return (world.angVelY[b] - spin) / world.invIyy[b];
	}

	static function facePressure():Void {
		// Half the water's density, times the coefficient, the area and the speed squared, over the step.
		var perArea = 0.5 * 1000 * 1.2 * 2 * 2 * DT;
		for (planar in [false, true]) {
			var label = planar ? "planar" : "spatial";
			var broadside = plateImpulse(0.02, 1, 1, new Quat(), planar);
			near(broadside.x, perArea, '$label plate broadside', 2e-4 * perArea);
			if (Math.abs(broadside.y) + Math.abs(broadside.z) > 1e-6 * perArea) throw '$label plate broadside pushed sideways: $broadside';
			// A wedge with one flat face upstream and its slope downstream is pushed straight along the current, by that face alone.
			var wedge = new World(2, 2);
			wedge.gravity = new Vec3(0, 0, 0);
			var body = wedge.createBody(Dynamic, 0, -3, 0);
			wedge.attachShape(body, ShapeBuilder.makePolygon(wedge.verts, [new Vec3(0, -0.5), new Vec3(1, -0.5), new Vec3(0, 0.5)], planar ? 0 : 1, 0.01, 0, 1e7));
			new Water(wedge, {current: [2, 0, 0], linearDrag: 0, angularDrag: 0, faceDrag: 1.2}).apply(DT);
			var wb = wedge.bodySlot(body), m = 1 / wedge.invMassX[wb];
			near(m * wedge.velX[wb], perArea, '$label wedge along the current', 2e-4 * perArea);
			near(m * wedge.velY[wb], 0, '$label wedge across the current', 2e-4 * perArea);
			if (!planar) {
				// Spinning broadside in still water, one half of each face runs into the water and the other half away: the braking
				// torque is the integral of half the density times the coefficient times (spin z)^2 z over both halves, rho C w^2 H L^4 / 64.
				var expected = -1000 * 1.2 * 4 * 1 / 64 * DT;
				near(spinningPlate(2, false), expected, "a spinning plate's braking", 2e-4 * Math.abs(expected));
			}
			// Half out of the water: half the face, so half the push.
			near(plateImpulse(0.02, 1, 1, new Quat(), planar, 0).x, perArea / 2, '$label plate half out of the water', 2e-4 * perArea);
			// Edge on: only its edge, 0.02 high, meets the water.
			var edge = plateImpulse(1, 0.02, 1, new Quat(), planar);
			near(edge.x, perArea * 0.02, '$label plate edge on', 2e-4 * perArea * 0.02);
			// Turned 30 degrees about z: each face is pushed along its normal by the speed into it squared, so the broad face partly
			// sideways, and the end face, 0.02 across, now meets the water too.
			var a = Math.PI / 6, c = Math.cos(a), n = Math.sin(a), turned = plateImpulse(0.02, 1, 1, new Quat(0, 0, Math.sin(a / 2), Math.cos(a / 2)), planar);
			var broad = perArea * c * c, end = perArea * 0.02 * n * n;
			near(turned.x, broad * c + end * n, '$label turned plate along the current', 2e-4 * broad);
			near(turned.y, broad * n - end * c, '$label turned plate across the current', 2e-4 * broad);
		}
		Sys.println("water: a plate takes half the density times the area times the speed squared broadside, half that half out of the water, a fiftieth edge on, and along its normal when turned");
	}

	/**
	 * A rotor of three flat blades pitched by `pitch` radians, wholly under
	 * water on a hinge along x, in a current along x; its average turn rate
	 * about x over the last of `seconds`.
	 */
	static function rotor(current:Float, pitch:Float, faceDrag:Float, seconds:Float, density:Float = 1000):Float {
		var world = new World(4, 8);
		world.gravity = new Vec3(0, 0, 0);
		var axle = world.createBody(Static, 0, -3, 0);
		var rotor = world.createBody(Dynamic, 0, -3, 0);
		for (i in 0...3) {
			var t = 2 * Math.PI * i / 3, rc = Math.cos(t), rs = Math.sin(t);
			// Span along the radius, chord turned from the plane of turning by the pitch, thickness across.
			var span = new Vec3(0, rc, rs), chord = new Vec3(Math.sin(pitch), -rs * Math.cos(pitch), rc * Math.cos(pitch));
			var across = new Vec3(Math.cos(pitch), rs * Math.sin(pitch), -rc * Math.sin(pitch));
			world.attachShape(rotor, ShapeBuilder.makeHull(world.verts, [for (r in [0.25, 1.2]) for (c in [-0.15, 0.15]) for (h in [-0.004, 0.004])
				new Vec3(span.x * r + chord.x * c + across.x * h, span.y * r + chord.y * c + across.y * h, span.z * r + chord.z * c + across.z * h)], 0.01, 0, density));
		}
		world.createHingeJoint(axle, rotor, new Vec3(0, -3, 0), new Vec3(1, 0, 0));
		var water = new Water(world, {current: [current, 0, 0], linearDrag: 0, angularDrag: 0, faceDrag: faceDrag});
		var b = world.bodySlot(rotor), steps = Math.round(seconds / DT), last = Math.round(2 / DT), sum = 0.0;
		for (k in 0...steps) {
			water.apply(DT); world.step(DT);
			if (k >= steps - last) sum += world.angVelX[b];
		}
		return sum / last;
	}

	static function submergedRotor():Void {
		var pitch = Math.PI / 6;
		var turning = rotor(1, pitch, 1, 12);
		// A blade pitched this way is pushed toward -x turning: its face toward the water leans that way.
		if (!(turning < -0.5)) throw 'a rotor under water did not turn with its blades: $turning';
		near(rotor(1, -pitch, 1, 12), -turning, "a rotor pitched the other way turns the other way", 1e-3 * Math.abs(turning));
		near(rotor(-1, pitch, 1, 12), -turning, "a rotor in the reversed current turns back", 1e-3 * Math.abs(turning));
		// Free, it settles where the pushes on its blades turn it neither way. Across a flat blade the water's speed into each face
		// depends only on the radius: into the broad faces q = u cos(pitch) + w r sin(pitch), into the edges p = u sin(pitch) - w r cos(pitch).
		// Their torques about the axle, integrated along the span, cancel at the free speed.
		function torque(w:Float):Float {
			var sum = 0.0, steps = 4000, dr = 0.95 / steps;
			for (k in 0...steps) {
				var r = 0.25 + (k + 0.5) * dr;
				var q = Math.cos(pitch) + w * r * Math.sin(pitch), p = Math.sin(pitch) - w * r * Math.cos(pitch);
				sum += (-(q < 0 ? -1 : 1) * q * q * r * Math.sin(pitch) * 0.3 + (p < 0 ? -1 : 1) * p * p * r * Math.cos(pitch) * 0.008) * dr;
			}
			return sum;
		}
		var low = -10.0, high = 0.0;
		for (_ in 0...60) { var mid = (low + high) / 2; if (torque(mid) < 0) high = mid else low = mid; }
		// Drag is solved before the joints, for a free body: the speed it expects the hinge's thrust to give the rotor in a step eases
		// the push it finds, and the hinge then takes that speed away. So a light rotor turns slow, by a share that falls with the
		// rotor's mass as the step's drag on it does.
		var free = (low + high) / 2;
		near(rotor(1, pitch, 1, 20, 4000), free, "a free rotor of density 4000 against its blades' torques", 0.03 * Math.abs(free));
		near(rotor(1, pitch, 1, 20, 16000), free, "a free rotor of density 16000 against its blades' torques", 0.0075 * Math.abs(free));
		// Drag that does not see which way a face points pushes every blade alike and turns nothing.
		var still = rotor(1, pitch, 0, 6);
		if (Math.abs(still) > 1e-6) throw 'a rotor turned without face drag: $still';
		Sys.println('water: a rotor under water turns by its angled blades, the other way for the other pitch or current, nearing the speed its faces\' torques balance at, ${Math.round(free * 1000) / 1000} rad/s, as it gets heavier');
	}

	static function events():Void {
		var world = new World(4, 4);
		// Dropped from low enough that it does not bounce back out.
		var body = cube(world, 0, 1, 500);
		var water = new Water(world);
		var came = 0, went = 0;
		for (_ in 0...180) {
			water.apply(DT); world.step(DT);
			came += water.entered.length; went += water.left.length;
		}
		world.teleportBody(body, new Vec3(0, 5, 0), new Quat());
		water.apply(DT);
		went += water.left.length;
		if (came != 1 || went != 1) throw 'expected one enter and one leave, got $came and $went';
		near(water.depthAt(0, -2, 0), 2, "depth at a point", 1e-9);
		var bounded = new Water(world, {bounds: [-1, 1, -1, 1]});
		if (bounded.depthAt(5, -2, 0) != Math.NEGATIVE_INFINITY) throw "a point outside the bounds counted as in the water";
		Sys.println("water: enter and leave events; depth at a point, and nothing outside the bounds");
	}

	static function waves():Void {
		// A light float on a long wave rides it: its height swings with the wave's period.
		var world = new World(4, 4);
		var body = slab(world, 0, 0, 300);
		var water = new Water(world, {linearDrag: 2, angularDrag: 2});
		water.addWave(0.2, 30, 1, 0);
		var period = 2 * Math.PI / (Math.sqrt(9.81 * 2 * Math.PI / 30) * 1);
		simulate(world, water, 10);
		var b = world.bodySlot(body), last = 0.0, ups = [], t = 0.0;
		for (_ in 0...Math.round(30 / DT)) {
			water.apply(DT); world.step(DT); t += DT;
			var y:Float = world.posY[b];
			if (last < 0.2 && y >= 0.2) ups.push(t);
			last = y;
		}
		var measured = (ups[ups.length - 1] - ups[0]) / (ups.length - 1);
		near(measured, period, "a float rides the wave's period", period * 0.03);
		// On a wave running diagonally a float leans with the slope, about both level axes: the surface under it is cut as tilted.
		var tilting = new World(4, 4);
		var raft = slab(tilting, 0, 0, 300);
		var sea = new Water(tilting, {linearDrag: 1, angularDrag: 1});
		sea.addWave(0.3, 12, 1, 1);
		var r = tilting.bodySlot(raft), leanX = 0.0, leanZ = 0.0, yaw = 0.0;
		for (_ in 0...Math.round(12 / DT)) {
			sea.apply(DT); tilting.step(DT);
			leanX = Math.max(leanX, Math.abs(tilting.rotX[r])); leanZ = Math.max(leanZ, Math.abs(tilting.rotZ[r]));
			yaw = Math.max(yaw, Math.abs(tilting.rotY[r]));
		}
		// Waves lean a float; nothing turns it about the vertical.
		if (yaw > 1e-3) throw 'a raft on a diagonal wave turned about the vertical ($yaw)';
		// The steepest slope is 0.3 * 2 pi / 12, about 9 degrees, split between the two axes.
		if (leanX < 0.02 || leanZ < 0.02) throw 'a raft on a diagonal wave leaned only $leanX and $leanZ (quaternion parts)';
		Sys.println('water: a float on a 30 m wave rises every ${Math.round(measured * 100) / 100} s, the wave\'s period being ${Math.round(period * 100) / 100} s; a raft leans with a diagonal wave');
	}

	static function replays():Void {
		function go():World {
			var world = new World(8, 8);
			for (i in 0...6) {
				var body = cube(world, i * 1.5 - 4, 1 + i, 300 + i * 100);
				world.teleportBody(body, new Vec3(i * 1.5 - 4, 1 + i, 0), new Quat(0.2 * i, 0.1, 0, 1));
			}
			var water = new Water(world, {current: [0.3, 0, 0], faceDrag: 1});
			water.addWave(0.15, 8, 1, 0.3);
			simulate(world, water, 6);
			return world;
		}
		var a = go(), b = go();
		for (i in 0...a.bodyCount) if (a.posX[i] != b.posX[i] || a.posY[i] != b.posY[i] || a.rotW[i] != b.rotW[i]) throw 'replay differs at body $i';
		Sys.println("water: six floats on waves and a current replay bit for bit");
	}

	static function sleeping():Void {
		var world = new World(4, 4);
		var body = slab(world, 0, 0.5, 500);
		var water = new Water(world, {linearDrag: 4, angularDrag: 4, faceDrag: 1});
		simulate(world, water, 30);
		var b = world.bodySlot(body);
		if (world.islands.isAwake[b] != 0) throw "a float at rest on still water did not sleep";
		near(water.submerged(body), 0.5, "a sleeping float keeps its share under", 2e-3);
		var y:Float = world.posY[b];
		simulate(world, water, 2);
		if (world.posY[b] != y) throw "a sleeping float moved";
		Sys.println("water: a float at rest on still water sleeps and keeps its place");
	}

	/** Strong face drag on a float at rest changes neither where it floats nor how far under. */
	static function faceDragAtRest():Void {
		var world = new World(4, 4);
		var body = slab(world, 0, 0.3, 500);
		var water = new Water(world, {linearDrag: 4, angularDrag: 4, faceDrag: 50});
		simulate(world, water, 30);
		near(water.submerged(body), 0.5, "a float under strong face drag floats at its draft", 2e-3);
		// A body as dense as the water, wholly under, stays where it is: at rest its top face meets no water either.
		// Let go from rest between steps, it first settles into the motion it keeps within a step.
		var neutral = slab(world, 5, -2, 1000), n = world.bodySlot(neutral);
		simulate(world, water, 2);
		var settled:Float = world.posY[n];
		simulate(world, water, 10);
		near(world.posY[n], settled, "a body as dense as the water under strong face drag", 1e-4);
		Sys.println("water: strong face drag leaves a float at rest at its draft, and a body as dense as the water where it is");
	}

	static function noAllocation():Void {
		var world = new World(8, 8);
		for (i in 0...5) cube(world, i * 1.5, 0.3, 400 + i * 50);
		var pill = world.createBody(Dynamic, -3, 0, 0);
		world.attachShape(pill, ShapeBuilder.makeCircle(0.4, 1, 0, 500));
		var water = new Water(world, {faceDrag: 1, current: [0.5, 0, 0]});
		water.addWave(0.1, 6, 1, 0);
		simulate(world, water, 1);
		var allocated = Allocation.least(() -> for (_ in 0...60) water.apply(DT));
		if (allocated != 0) throw 'applying water allocated $allocated bytes';
	}

	static function findings():Void {
		var water = new Water(new World(2, 2), {density: -1, linearDrag: -1, bounds: [1, 0, 0, 1]});
		water.addWave(0.1, -2);
		var codes = [for (i in water.validate().items) i.code];
		for (c in ["WATER_DENSITY", "WATER_DRAG", "WATER_BOUNDS", "WATER_WAVE"]) if (codes.indexOf(c) < 0) throw 'expected $c, got $codes';
		if (water.describe().indexOf('"waves":[{') < 0) throw "describe lacks the wave";
	}

	public static function run():Void {
		cutting();
		floating();
		currentAndSpin();
		implicitDrag();
		waterWheel();
		facePressure();
		submergedRotor();
		events();
		waves();
		replays();
		sleeping();
		faceDragAtRest();
		noAllocation();
		findings();
		Sys.println("water checks passed");
	}

	static function main():Void {
		run();
	}
}
