import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyType;

class IslandParallelChecks {
	static inline var DEFAULT_STACKS = 16;
	static inline var DEFAULT_HEIGHT = 8;
	static inline var DEFAULT_FRAMES = 20;

	static function makeScene(stacks:Int, height:Int, mode:String):World {
		var world = new World(1 + stacks * height, 1 + stacks * height,
			mode == 'loose' ? 0 : stacks * (height - 1));
		var floor = world.createBody(BodyType.Static, 0, -0.25);
		world.attachShape(floor, ShapeBuilder.makeBox(world.verts, stacks * 2 + 2, 0.25, 0, 0));
		for (stack in 0...stacks) {
			var x = (stack - (stacks - 1) * 0.5) * 4.0;
			var previous = -1;
			for (row in 0...height) {
				var body = world.createBody(BodyType.Dynamic, x, 0.49 + row * 0.98);
				world.attachShape(body, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 0, 0));
				if (mode != 'loose' && previous >= 0) {
					var anchor = new Vec3(x, 0.49 + (row - 0.5) * 0.98);
					if (mode == 'mixed') {
						switch (stack % 4) {
							case 1: world.createHingeJoint(previous, body, anchor);
							case 2: world.createPrismaticJoint(previous, body, anchor, new Vec3(0, 1));
							case 3: world.createWeldJoint(previous, body, anchor);
							default: world.createDistanceJoint(previous, body, 0.98);
						}
					} else world.createDistanceJoint(previous, body, 0.98);
				}
				previous = body;
			}
		}
		return world;
	}

	/** Throws unless the serial and parallel values are the same bits. Serial and parallel solves give the same bits, because every row of a color takes the same arithmetic however the rows are grouped. */
	static function checkNear(a:Float, b:Float, name:String):Void {
		if (!Math.isFinite(a) || !Math.isFinite(b) || a != b)
			throw '$name: serial=$a parallel=$b';
	}

	static function checkBodies(serial:World, parallel:World):Void {
		for (body in 0...serial.bodyCount) {
			checkNear(serial.posX[body], parallel.posX[body], 'body $body posX');
			checkNear(serial.posY[body], parallel.posY[body], 'body $body posY');
			checkNear(serial.posZ[body], parallel.posZ[body], 'body $body posZ');
			checkNear(serial.rotX[body], parallel.rotX[body], 'body $body rotX');
			checkNear(serial.rotY[body], parallel.rotY[body], 'body $body rotY');
			checkNear(serial.rotZ[body], parallel.rotZ[body], 'body $body rotZ');
			checkNear(serial.rotW[body], parallel.rotW[body], 'body $body rotW');
			checkNear(serial.velX[body], parallel.velX[body], 'body $body velX');
			checkNear(serial.velY[body], parallel.velY[body], 'body $body velY');
			checkNear(serial.velZ[body], parallel.velZ[body], 'body $body velZ');
			checkNear(serial.angVelX[body], parallel.angVelX[body], 'body $body angVelX');
			checkNear(serial.angVelY[body], parallel.angVelY[body], 'body $body angVelY');
			checkNear(serial.angVelZ[body], parallel.angVelZ[body], 'body $body angVelZ');
		}
	}

	static function makeSphericalScene():World {
		var world = new World(6, 4, 4);
		for (arm in 0...2) {
			var x = arm == 0 ? -2.0 : 2.0;
			var support = world.createBody(BodyType.Static, x, 0);
			var upper = world.createBody(BodyType.Dynamic, x, -0.3);
			var lower = world.createBody(BodyType.Dynamic, x, -0.9);
			world.attachShape(upper, ShapeBuilder.makeCapsule(world.verts,
				0, -0.3, 0, 0.3, 0.15, 0.08, 0, 3));
			world.attachShape(lower, ShapeBuilder.makeCapsule(world.verts,
				0, -0.3, 0, 0.3, 0.15, 0.08));
			world.createSphericalJoint(support, upper, new Vec3(x, 0));
			world.createSphericalJoint(upper, lower, new Vec3(x, -0.6));
			world.velX[world.bodySlot(lower)] = 1.5;
			world.velZ[world.bodySlot(lower)] = 0.8;
		}
		return world;
	}

	static function checkSpherical():Void {
		var serial = makeSphericalScene();
		var parallel = makeSphericalScene();
		parallel.enableParallelIslands(2, 1, 1);
		for (_ in 0...60) {
			serial.step(1.0 / 60.0);
			parallel.step(1.0 / 60.0);
			checkBodies(serial, parallel);
		}
		parallel.disableParallelIslands();
	}

	static function makeEventScene():World {
		var world = new World(64, 64);
		var floor = world.createBody(BodyType.Static, 0, -0.25);
		world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 20, 0.25, 0, 0));
		var gate = world.createBody(BodyType.Static, 0, 1.5);
		world.setShapeSensor(world.attachShape(gate, ShapeBuilder.makeBox(world.verts, 20, 0.25, 0, 0)), true);
		for (stack in 0...6) {
			for (row in 0...4) {
				var body = world.createBody(BodyType.Dynamic, stack * 3.0 - 7.5, 2.5 + row * 1.5);
				world.attachShape(body, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 0, 0));
			}
		}
		return world;
	}

	static function samePairs(name:String, a:hxn.me.physics.core.WorldEvents.ShapePairEvents,
		b:hxn.me.physics.core.WorldEvents.ShapePairEvents):Int {
		if (a.count != b.count) throw '$name count: serial=${a.count} parallel=${b.count}';
		for (i in 0...a.count) {
			if (a.shapeA(i) != b.shapeA(i) || a.shapeB(i) != b.shapeB(i))
				throw '$name $i: serial=${a.shapeA(i)}:${a.shapeB(i)} parallel=${b.shapeA(i)}:${b.shapeB(i)}';
		}
		return a.count;
	}

	/** Checks that serial and island-worker stepping report the same events in the same order. */
	static function checkEvents():Void {
		var serial = makeEventScene();
		var parallel = makeEventScene();
		parallel.enableParallelIslands(4, 1, 1);
		var total = 0;
		for (_ in 0...180) {
			serial.step(1.0 / 60.0);
			parallel.step(1.0 / 60.0);
			var s = serial.events, p = parallel.events;
			total += samePairs('sensor begins', s.sensorBegins, p.sensorBegins);
			total += samePairs('sensor ends', s.sensorEnds, p.sensorEnds);
			total += samePairs('contact begins', s.contactBegins, p.contactBegins);
			total += samePairs('contact ends', s.contactEnds, p.contactEnds);
			total += samePairs('impacts', s.impacts, p.impacts);
			for (i in 0...s.impacts.count) checkNear(s.impacts.speed(i), p.impacts.speed(i), 'impact $i speed');
		}
		parallel.disableParallelIslands();
		if (total < 24 * 3) throw 'event scene reported too few events: $total';
	}

	public static function main():Void {
		var args = Sys.args();
		var stacks = args.length > 0 ? Std.parseInt(args[0]) : DEFAULT_STACKS;
		var height = args.length > 1 ? Std.parseInt(args[1]) : DEFAULT_HEIGHT;
		var frames = args.length > 2 ? Std.parseInt(args[2]) : DEFAULT_FRAMES;
		var minConstraints = args.length > 3 ? Std.parseInt(args[3]) : 1;
		var workers = args.length > 4 ? Std.parseInt(args[4]) : 4;
		var mode = args.length > 5 ? args[5] : 'distance';
		var minPairs = args.length > 6 ? Std.parseInt(args[6]) : 1;
		if (mode != 'distance' && mode != 'mixed' && mode != 'loose') throw 'Invalid island scene mode';
		if (stacks < 2 || height < 1 || frames < 1) throw 'Invalid island check size';
		var serial = makeScene(stacks, height, mode);
		var parallel = makeScene(stacks, height, mode);
		parallel.enableParallelIslands(workers, minConstraints, minPairs);
		var dt = 1.0 / 60.0;
		var start = Sys.time();
		for (_ in 0...frames) serial.step(dt);
		var serialMs = (Sys.time() - start) * 1000.0;
		start = Sys.time();
		var peakIslands = 0;
		for (_ in 0...frames) {
			parallel.step(dt);
			if (parallel.islands.islandCount > peakIslands) peakIslands = parallel.islands.islandCount;
		}
		var parallelMs = (Sys.time() - start) * 1000.0;
		parallel.disableParallelIslands();
		if (peakIslands < stacks || peakIslands > stacks * height) throw 'Invalid independent island count';
		checkBodies(serial, parallel);
		// Other worker counts and the other scene kinds match the serial solve too.
		for (kind in ['distance', 'mixed', 'loose']) for (count in [2, 3, 8]) {
			var a = makeScene(stacks, height, kind), b = makeScene(stacks, height, kind);
			b.enableParallelIslands(count, minConstraints, minPairs);
			for (_ in 0...frames) { a.step(dt); b.step(dt); }
			b.disableParallelIslands();
			checkBodies(a, b);
		}
		checkSpherical();
		checkEvents();
		Sys.println('Island parallel checks passed: islands=${parallel.islands.islandCount}, serial=${serialMs}ms, parallel=${parallelMs}ms');
	}
}
