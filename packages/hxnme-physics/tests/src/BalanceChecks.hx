import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.Balance;
import hxn.me.physics.core.Handles;
import hxn.me.physics.core.World;

/** `BalanceChecks` tests the balance measures on simple stances whose answers can be worked out by hand. */
class BalanceChecks {
	static function near(actual:Float, expected:Float, label:String, tolerance:Float):Void {
		if (!(Math.abs(actual - expected) <= tolerance)) throw '$label: expected $expected, got $actual';
	}

	static function box(hx:Float, hy:Float, hz:Float):Array<Vec3> {
		return [for (k in 0...8) new Vec3(k & 1 != 0 ? hx : -hx, k & 2 != 0 ? hy : -hy, k & 4 != 0 ? hz : -hz)];
	}

	/**
	 * Builds two feet 0.2 m either side of the middle, each 0.2 long, 0.08
	 * high and 0.12 wide, standing on a floor, and a kinematic torso held
	 * above them.
	 */
	static function stance(torsoX:Float):{world:World, feet:Array<BodyId>, torso:BodyId} {
		var w = new World(16, 64, 4);
		var floor = w.createBody(BodyType.Static, 0, -0.5, 0);
		w.attachShape(floor, ShapeBuilder.makeHull(w.verts, box(5, 0.5, 5), 0.0));
		var feet = [for (x in [-0.2, 0.2]) {
			var foot = w.createBody(BodyType.Dynamic, x, 0.04, 0);
			w.attachShape(foot, ShapeBuilder.makeHull(w.verts, box(0.1, 0.04, 0.06), 0.0, 0.0, 1000));
			foot;
		}];
		var torso = w.createBody(BodyType.Kinematic, torsoX, 1, 0);
		w.attachShape(torso, ShapeBuilder.makeHull(w.verts, box(0.15, 0.3, 0.1), 0.0, 0.0, 1000));
		for (_ in 0...60) w.step(1.0 / 60.0);
		return {world: w, feet: feet, torso: torso};
	}

	/** Returns a balance measure of bodies that are already asleep. The first update wakes them, so the next step finds their support. */
	static function measured(world:World, bodies:Array<BodyId>, planar:Bool = false):Balance {
		var b = new Balance(world, bodies, planar);
		b.update();
		world.step(1.0 / 60.0);
		b.update();
		return b;
	}

	static function checkStance():Void {
		var s = stance(0);
		var b = measured(s.world, s.feet.concat([s.torso]));
		// Each foot has a mass of 0.2 × 0.08 × 0.12 × 1000, and the torso 0.3 × 0.6 × 0.2 × 1000.
		var foot = 0.2 * 0.08 * 0.12 * 1000, torso = 0.3 * 0.6 * 0.2 * 1000;
		near(b.totalMass, 2 * foot + torso, "total mass", 1e-4);
		near(b.comX, 0, "centre of mass x", 1e-6);
		near(b.comY, (2 * foot * 0.04 + torso * 1.0) / (2 * foot + torso), "centre of mass y", 2e-3);
		if (!b.grounded) throw 'the feet stand on the floor';
		// The support is the rectangle around both feet: x from -0.3 to 0.3, z from -0.06 to 0.06. The nearest edge is 0.06 away.
		near(b.margin, 0.06, "margin with both feet", 2e-3);
		var minX = 9.0, maxX = -9.0;
		for (i in 0...b.supportCount) { minX = Math.min(minX, b.supportX[i]); maxX = Math.max(maxX, b.supportX[i]); }
		near(minX, -0.3, "support left edge", 2e-3); near(maxX, 0.3, "support right edge", 2e-3);
		near(b.height, b.comY, "height above the floor at 0", 2e-3);

		// When the torso leans out past the right foot, the center of mass leaves the support.
		var leaning = stance(0.5);
		var lb = measured(leaning.world, leaning.feet.concat([leaning.torso]));
		var comX = torso * 0.5 / (2 * foot + torso);
		near(lb.comX, comX, "leaning centre of mass", 1e-5);
		near(lb.margin, 0.3 - comX, "margin outside the support", 2e-3);
		if (!(lb.margin < 0)) throw 'leaning out should give a negative margin';

		// In mid-step, the right foot is clear of the floor, so the left foot alone holds the body up.
		var step = stance(0);
		var w = step.world;
		w.setBodyType(step.feet[1], BodyType.Kinematic);
		w.teleportBody(step.feet[1], new Vec3(0.2, 0.3, 0), new Quat());
		for (_ in 0...2) w.step(1.0 / 60.0);
		var sb = measured(w, step.feet.concat([step.torso]));
		var maxStep = -9.0;
		for (i in 0...sb.supportCount) maxStep = Math.max(maxStep, sb.supportX[i]);
		near(maxStep, -0.1, "one foot's right edge", 2e-3);
		near(sb.margin, -0.1 - sb.comX, "margin over one foot", 2e-3);

		// For the capture point, the torso moves sideways and carries the center of mass on by its
		// velocity × √(height / g).
		var moving = stance(0);
		var mb = measured(moving.world, moving.feet.concat([moving.torso]));
		moving.world.velX[moving.world.bodySlot(moving.torso)] = 1.0;
		mb.update();
		var vcom = torso * 1.0 / (2 * foot + torso);
		near(mb.velX, vcom, "centre of mass velocity", 1e-5);
		near(mb.captureX, mb.comX + vcom * Math.sqrt(mb.height / 9.81), "capture point", 1e-6);
		near(mb.captureMargin, 0.3 - mb.captureX, "capture margin", 2e-3);
		if (mb.describe().indexOf('"grounded":true') < 0) throw 'describe: ${mb.describe()}';
		// Next, a kinematic target moves the torso. The measures see the motion that the target gave it,
		// which the world clears after the step.
		var driven = stance(0);
		var db = measured(driven.world, driven.feet.concat([driven.torso]));
		var ts = driven.world.bodySlot(driven.torso);
		driven.world.targetX[ts] = 0.01; driven.world.targetY[ts] = 1; driven.world.targetZ[ts] = 0;
		driven.world.targetQx[ts] = 0; driven.world.targetQy[ts] = 0; driven.world.targetQz[ts] = 0; driven.world.targetQw[ts] = 1;
		driven.world.commitKinematicTarget(ts);
		driven.world.step(1.0 / 60.0);
		db.update();
		near(db.velX, torso * 0.6 / (2 * foot + torso), "centre of mass velocity from a kinematic target", 1e-4);

		// In the air there is no support.
		var w2 = new World(4, 4, 1);
		var floating = w2.createBody(BodyType.Dynamic, 0, 3, 0);
		w2.attachShape(floating, ShapeBuilder.makeHull(w2.verts, box(0.1, 0.1, 0.1), 0.0));
		w2.step(1.0 / 60.0);
		var fb = new Balance(w2, [floating]);
		fb.update();
		if (fb.grounded || fb.margin != Math.NEGATIVE_INFINITY) throw 'a falling body has no support';
	}

	static function checkPlanar():Void {
		var w = new World(8, 64, 4);
		var floor = w.createBody(BodyType.Static, 0, -0.5);
		w.attachShape(floor, ShapeBuilder.makeBox(w.verts, 5, 0.5));
		var feet = [for (x in [-0.2, 0.2]) {
			var foot = w.createBody(BodyType.Dynamic, x, 0.04);
			w.attachShape(foot, ShapeBuilder.makeBox(w.verts, 0.1, 0.04, 0.0, 0.0));
			foot;
		}];
		for (_ in 0...60) w.step(1.0 / 60.0);
		var b = measured(w, feet, true);
		// The planar support is the interval from -0.3 to 0.3. The center of mass at 0 is 0.3 from either end.
		if (b.supportCount != 2) throw 'a planar support is two ends';
		near(b.margin, 0.3, "planar margin", 2e-3);
		// Asleep again, the feet keep the support they had.
		for (_ in 0...120) w.step(1.0 / 60.0);
		if (w.islands.isAwake[w.bodySlot(feet[0])] != 0) throw 'the feet should be asleep again';
		b.update();
		near(b.margin, 0.3, "planar margin while asleep", 2e-3);
	}

	static function checkNoAllocation():Void {
		var s = stance(0);
		var b = measured(s.world, s.feet.concat([s.torso]));
		for (_ in 0...10) b.update();
		var allocated = Allocation.least(() -> for (_ in 0...1000) b.update());
		if (allocated > 256) throw 'balance measures allocated $allocated bytes';
	}

	public static function run():Void {
		checkStance();
		checkPlanar();
		checkNoAllocation();
	}

	public static function bench():Void {
		var s = stance(0);
		var b = new Balance(s.world, s.feet.concat([s.torso]));
		for (_ in 0...1000) b.update();
		var best = Math.POSITIVE_INFINITY;
		for (_ in 0...7) {
			var start = haxe.Timer.stamp();
			for (_ in 0...10000) b.update();
			best = Math.min(best, (haxe.Timer.stamp() - start) / 10000);
		}
		Sys.println('balance measures: ${Math.round(best * 1e9)} ns for 3 bodies and ${s.world.contacts.count} contacts');
	}
}
