import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.Handles;
import hxn.me.physics.core.World;
import hxn.me.physics.core.WorldBatch;
import hxn.me.physics.core.WorldSnapshot;

/**
 * Snapshots: a busy world saved partway, run on, restored and run again
 * gives the same bits; so does a second world built the same way; a body or
 * joint made after the snapshot disappears with it; saving and restoring
 * again allocates nothing. Worlds stepped together in a batch, on several
 * workers, step exactly as they would alone.
 */
class SnapshotChecks {
	static function box(hx:Float, hy:Float, hz:Float):Array<Vec3> {
		return [for (k in 0...8) new Vec3(k & 1 != 0 ? hx : -hx, k & 2 != 0 ? hy : -hy, k & 4 != 0 ? hz : -hz)];
	}

	static function turn(x:Float, y:Float, z:Float, angle:Float):Quat {
		var s = Math.sin(angle * 0.5);
		return new Quat(x * s, y * s, z * s, Math.cos(angle * 0.5));
	}

	/**
	 * A floor; a stack of boxes, one of them bouncy; a box off to one side
	 * that falls asleep before a sweeping kinematic paddle wakes it; a sensor;
	 * a chain of driven spherical joints; a hinge with limits and a drive; a
	 * prismatic slider with a motor; a weld; a spring and a rigid rod.
	 */
	static function build(parallel:Bool):{world:World, paddle:BodyId, spherical:Array<JointId>, hinge:JointId, marker:BodyId, rail:BodyId, hook:BodyId} {
		var w = new World(64, 64, 32);
		if (parallel) w.enableParallelIslands(2, 1, 1);
		// A body with no shape, destroyed after the snapshot to reorder the world's list of live bodies.
		var marker = w.createBody(BodyType.Dynamic, 0, 10, 0);
		var floor = w.createBody(BodyType.Static, 0, -0.5, 0);
		w.attachShape(floor, ShapeBuilder.makeHull(w.verts, box(6, 0.5, 6), 0.0), 1, -1, 0, 0.8);
		for (i in 0...6) {
			var b = w.createBody(BodyType.Dynamic, 0.03 * i, 0.25 + i * 0.52, 0.02 * i);
			w.attachShape(b, ShapeBuilder.makeHull(w.verts, box(0.25, 0.25, 0.25), 0.01, 0, 500), 1, -1, 0, 0.6, i == 3 ? 0.6 : 0.0);
		}
		var lone = w.createBody(BodyType.Dynamic, 2.5, 0.2, 0);
		w.attachShape(lone, ShapeBuilder.makeHull(w.verts, box(0.2, 0.2, 0.2), 0.01, 0, 400));
		var paddle = w.createBody(BodyType.Kinematic, 2.5, 0.3, -2);
		w.attachShape(paddle, ShapeBuilder.makeHull(w.verts, box(0.6, 0.15, 0.1), 0.0));
		var gate = w.createBody(BodyType.Static, -2, 0.5, 0);
		var sensor = w.attachShape(gate, ShapeBuilder.makeHull(w.verts, box(0.5, 0.5, 0.5), 0.0));
		w.setShapeSensor(sensor, true);

		// A hanging chain of three links on driven spherical joints.
		var anchor = w.createBody(BodyType.Static, -2, 3, 0);
		var previous = anchor, top = 3.0, spherical = [];
		for (i in 0...3) {
			var link = w.createBody(BodyType.Dynamic, -2, top - 0.3, 0);
			w.attachShape(link, ShapeBuilder.makeHull(w.verts, box(0.06, 0.28, 0.06), 0.01, 0, 800), 1, -1, -1);
			var j = w.createSphericalJoint(previous, link, new Vec3(-2, top, 0), new Vec3(0, -1, 0), 1.2, -0.6, 0.6);
			w.setSphericalDrive(j, new Quat(), 15, 1, 40);
			spherical.push(j);
			previous = link;
			top -= 0.6;
		}
		// A door on a limited, driven hinge.
		var post = w.createBody(BodyType.Static, 0, 2, 3);
		var door = w.createBody(BodyType.Dynamic, 0.5, 2, 3);
		w.attachShape(door, ShapeBuilder.makeHull(w.verts, box(0.45, 0.4, 0.04), 0.01, 0, 300), 1, -1, -2);
		var hinge = w.createHingeJoint(post, door, new Vec3(0, 2, 3), new Vec3(0, 1, 0), -1.2, 1.2);
		w.setHingeDrive(hinge, 0.8, 10, 1, 60);
		// A slider pushed along X by a motor against its limits, on a rail that tilts back and forth.
		var rail = w.createBody(BodyType.Kinematic, 3, 2, 3);
		var slider = w.createBody(BodyType.Dynamic, 3, 2, 3);
		w.attachShape(slider, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01, 0, 300), 1, -1, -3);
		w.createPrismaticJoint(rail, slider, new Vec3(3, 2, 3), new Vec3(1, 0, 0), -2, 2, 0.4, 3);
		// A soft weld, a spring and a rigid rod, hanging from a hook that sways.
		var a = w.createBody(BodyType.Dynamic, -4, 2, 3), b = w.createBody(BodyType.Dynamic, -4, 1.5, 3);
		w.attachShape(a, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01, 0, 300), 1, -1, -4);
		w.attachShape(b, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01, 0, 300), 1, -1, -4);
		var hook = w.createBody(BodyType.Kinematic, -4, 2.6, 3);
		w.createDistanceJoint(hook, a, 0.6, 3, 0.2);
		w.createDistanceJoint(a, b, 0.5);
		var c = w.createBody(BodyType.Dynamic, -4, 1.0, 3);
		w.attachShape(c, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01, 0, 300), 1, -1, -4);
		w.createWeldJoint(b, c, new Vec3(-4, 1.25, 3), 8, 0.5);
		return {world: w, paddle: paddle, spherical: spherical, hinge: hinge, marker: marker, rail: rail, hook: hook};
	}

	/** Everything the scene does at a step depends only on the step's number, so a replay gets the same inputs. */
	static function drive(s:{world:World, paddle:BodyId, spherical:Array<JointId>, hinge:JointId, marker:BodyId, rail:BodyId, hook:BodyId}, step:Int):Void {
		var w = s.world, t = step / 60.0;
		// The paddle waits, then sweeps across where the lone box sleeps.
		var x = step < 150 ? 2.5 : 2.5 + 0.02 * (step - 150);
		w.setKinematicTarget(s.paddle, new Vec3(x > 3.2 ? 3.2 : x, 0.3, step < 150 ? -2.0 : Math.min(0.0, -2.0 + 0.04 * (step - 150))), turn(0, 1, 0, 0.3 * Math.sin(t)));
		for (i in 0...s.spherical.length) w.setSphericalDrive(s.spherical[i], turn(0, 0, 1, 0.5 * Math.sin(t * 2 + i)), 15, 1, 40);
		w.setHingeDrive(s.hinge, Math.sin(t * 1.5), 10, 1, 60);
		w.setKinematicTarget(s.rail, new Vec3(3, 2, 3), turn(0, 0, 1, 0.6 * Math.sin(t * 1.3)));
		w.setKinematicTarget(s.hook, new Vec3(-4 + 0.3 * Math.sin(t * 2.1), 2.6, 3 + 0.2 * Math.sin(t * 1.7)), turn(1, 0, 0, 0.2 * Math.sin(t)));
	}

	/** Every body's pose and velocities, every contact's impulses, and the step's events, bit for bit. */
	static function fingerprint(w:World):String {
		var out = new StringBuf();
		inline function bits(v:Float) out.add(haxe.io.FPHelper.floatToI32(v) + ",");
		for (i in 0...w.bodyCount) {
			for (v in [w.posX[i], w.posY[i], w.posZ[i], w.rotX[i], w.rotY[i], w.rotZ[i], w.rotW[i],
				w.velX[i], w.velY[i], w.velZ[i], w.angVelX[i], w.angVelY[i], w.angVelZ[i]]) bits(v);
			out.add(w.islands.isAwake[i] + ";");
		}
		var c = w.contacts;
		out.add('contacts ${c.count}:');
		for (k in 0...c.count) { bits(c.normalImpulse[k]); bits(c.tangentImpulse1[k]); }
		var e = w.events;
		out.add('events ${e.contactBegins.count} ${e.contactEnds.count} ${e.sensorBegins.count} ${e.sensorEnds.count} ${e.impacts.count}');
		return out.toString();
	}

	static function run(s:{world:World, paddle:BodyId, spherical:Array<JointId>, hinge:JointId, marker:BodyId, rail:BodyId, hook:BodyId}, from:Int, to:Int, trace:Array<String>):Void {
		for (step in from...to) {
			drive(s, step);
			s.world.step(1 / 60);
			if (trace != null && step % 10 == 0) trace.push(fingerprint(s.world));
		}
	}

	static function compare(expected:Array<String>, actual:Array<String>, label:String):Void {
		if (expected.length != actual.length) throw '$label: ${actual.length} samples, expected ${expected.length}';
		for (i in 0...expected.length) if (expected[i] != actual[i]) throw '$label: diverged at sample $i';
	}

	static function checkWorld(parallel:Bool):Void {
		var label = parallel ? "with island workers" : "on one thread";
		var scene = build(parallel);
		var w = scene.world;
		run(scene, 0, 90, null);
		var snapshot = new WorldSnapshot();
		snapshot.save(w);
		var straight = [];
		run(scene, 90, 300, straight);
		if (straight[0] == straight[straight.length - 1]) throw 'the scene did not move';

		snapshot.restore(w);
		var again = [];
		run(scene, 90, 300, again);
		compare(straight, again, 'restoring $label');

		// A body and joints made after the snapshot go with it, and one destroyed comes back; the replay is unchanged.
		snapshot.restore(w);
		var bodies = w.bodyCount, live = w.activeBodyCount;
		w.destroyBody(scene.marker);
		var extra = w.createBody(BodyType.Dynamic, 1, 5, 1);
		w.createBody(BodyType.Dynamic, 1, 6, 1);
		w.createDistanceJoint(extra, scene.paddle, 2);
		run(scene, 90, 120, null);
		snapshot.restore(w);
		if (w.bodyCount != bodies || w.activeBodyCount != live) throw 'the bodies are not as they were at the snapshot';
		w.bodySlot(scene.marker);
		var third = [];
		run(scene, 90, 300, third);
		compare(straight, third, 'restoring $label after making a body and joint');

		// A second world built by the same calls takes the snapshot and runs on the same.
		var copy = build(parallel);
		snapshot.restore(copy.world);
		var copied = [];
		run(copy, 90, 300, copied);
		compare(straight, copied, 'restoring $label into another world');

		// A new shape changes the world's structure; restoring then is refused.
		var refused = false;
		var b = w.createBody(BodyType.Dynamic, 0, 9, 0);
		w.attachShape(b, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01));
		try snapshot.restore(w) catch (_:Dynamic) refused = true;
		if (!refused) throw 'a snapshot restored over a changed structure';
		if (parallel) w.disableParallelIslands();
		if (parallel) copy.world.disableParallelIslands();
		Sys.println('$label: ${straight.length} samples over 210 steps match after restoring, after making and discarding a body, and in a second world');
	}

	static function checkAllocation():Void {
		var scene = build(false);
		run(scene, 0, 120, null);
		var snapshot = new WorldSnapshot();
		snapshot.save(scene.world);
		snapshot.restore(scene.world);
		var allocated = Allocation.least(() -> for (i in 0...20) {
			snapshot.save(scene.world);
			snapshot.restore(scene.world);
		});
		if (allocated > 256) throw 'saving and restoring allocated $allocated bytes';
		Sys.println('saving and restoring again allocated $allocated bytes');
		Sys.println(snapshot.describe());
	}

	static function checkBatch():Void {
		var alone = build(false);
		var expected = [];
		for (step in 0...200) {
			drive(alone, step);
			alone.world.step(1 / 60);
			if (step % 20 == 0) expected.push(fingerprint(alone.world));
		}
		var scenes = [for (i in 0...12) build(false)];
		var batch = new WorldBatch(4);
		for (sc in scenes) batch.add(sc.world);
		batch.beforeStep = (i, w) -> drive(scenes[i], w.steps);
		var traces = [for (i in 0...12) []];
		for (step in 0...200) {
			batch.step(1 / 60);
			if (step % 20 == 0) for (i in 0...12) traces[i].push(fingerprint(scenes[i].world));
		}
		for (i in 0...12) compare(expected, traces[i], 'world $i of a batch of twelve on four workers');
		// Without per-world work, stepping the batch allocates nothing once its worlds have warmed up.
		batch.beforeStep = null;
		for (_ in 0...5) batch.step(1 / 60);
		var allocated = Allocation.least(() -> for (_ in 0...20) batch.step(1 / 60));
		batch.shutdown();
		if (allocated > 1024) throw 'stepping a batch allocated $allocated bytes';
		Sys.println('twelve worlds on four workers step exactly as one alone; twenty batch steps allocated $allocated bytes');
	}

	public static function check():Void {
		checkWorld(false);
		checkWorld(true);
		checkAllocation();
		checkBatch();
		Sys.println("snapshot checks passed");
	}

	static function main():Void {
		check();
	}
}
