import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.physics.diagnostics.Diagnostics;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.Handles;
import hxn.me.physics.core.World;

/** World.validate: a sound world reports nothing, and each kind of fault is reported with its code and path. */
class ValidationChecks {
	static function box(hx:Float, hy:Float, hz:Float):Array<Vec3> {
		return [for (k in 0...8) new Vec3(k & 1 != 0 ? hx : -hx, k & 2 != 0 ? hy : -hy, k & 4 != 0 ? hz : -hz)];
	}

	static function sound():World {
		var w = new World(16, 16, 4);
		var floor = w.createBody(BodyType.Static, 0, -0.5, 0);
		w.attachShape(floor, ShapeBuilder.makeHull(w.verts, box(5, 0.5, 5), 0.0));
		var b = w.createBody(BodyType.Dynamic, 0, 1, 0);
		w.attachShape(b, ShapeBuilder.makeHull(w.verts, box(0.2, 0.2, 0.2), 0.01));
		var c = w.createBody(BodyType.Dynamic, 0, 2, 0);
		w.attachShape(c, ShapeBuilder.makeHull(w.verts, box(0.2, 0.2, 0.2), 0.01));
		w.createDistanceJoint(b, c, 1);
		for (_ in 0...10) w.step(1 / 60);
		return w;
	}

	static function expect(w:World, code:String, path:String):Void {
		var d = w.validate();
		for (item in d.items) if (item.code == code && item.path == path) return;
		throw 'expected $code at $path, got ${d.toJson()}';
	}

	public static function check():Void {
		var w = sound();
		var d = w.validate();
		if (d.items.length != 0) throw 'a sound world reported ${d.toJson()}';
		if (w.validate() == d) throw "Validation reused a report without being asked";
		// Span allocator refill regions so even one small allocation per call is visible.
		var report = new Diagnostics(), batch = 8192;
		var planar = new World(16,16,4), flatReport = new Diagnostics();
		planar.attachShape(planar.createBody(BodyType.Dynamic,0,1),ShapeBuilder.makeBox(planar.verts,0.1,0.1,0,0));
		var validate = () -> { for (_ in 0...batch) {
			if (w.validate(report) != report || planar.validate(flatReport) != flatReport) throw "Validation did not reuse its report";
		} };
		validate();
		Allocation.least(() -> {},128);
		var allocated = Allocation.least(validate,9);
		if (allocated != 0) throw 'validating sound worlds into a reused report allocated $allocated bytes';
		if (report.items.length != 0 || flatReport.items.length != 0) throw "Sound-world allocation check produced a finding";
		var savedX = w.posX[1]; w.posX[1] = Math.NaN;
		if (w.validate(report) != report || report.items.length != 1 || report.items[0].code != "WORLD_NONFINITE")
			throw "Reused report lost the non-finite pose diagnostic";
		w.posX[1] = savedX;
		if (w.validate(report) != report || report.items.length != 0) throw "Reused report kept stale findings";
		// The joints of an animated rig, between kinematic bodies, are not a fault.
		w = sound();
		w.setBodyType(w.bodyHandleAt(1), BodyType.Kinematic);
		w.setBodyType(w.bodyHandleAt(2), BodyType.Kinematic);
		if (w.validate().items.length != 0) throw 'a joint between kinematic bodies reported ${w.validate().toJson()}';

		w = sound();
		w.posX[1] = Math.NaN;
		expect(w, "WORLD_NONFINITE", "world/bodies/1/pose");

		w = sound();
		w.velY[1] = Math.POSITIVE_INFINITY;
		expect(w, "WORLD_NONFINITE", "world/bodies/1/velocity");

		w = sound();
		w.rotW[1] = 2;
		expect(w, "WORLD_ROTATION", "world/bodies/1/rotation");

		w = sound();
		var empty = w.createBody(BodyType.Dynamic, 1, 1, 0);
		expect(w, "WORLD_NO_MASS", 'world/bodies/${w.bodySlot(empty)}/shapes');

		w = sound();
		var ghost = w.createBody(BodyType.Dynamic, 1, 1, 0);
		w.setShapeSensor(w.attachShape(ghost, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01)), true);
		expect(w, "WORLD_SENSOR_ONLY", 'world/bodies/${w.bodySlot(ghost)}/shapes');

		w = sound();
		w.teleportBody(cast w.bodyHandleAt(2), new Vec3(20000, 1, 0), new Quat());
		expect(w, "WORLD_FAR", 'world/bodies/${w.bodySlot(w.bodyHandleAt(2))}/position');

		w = sound();
		var lost = w.createBody(BodyType.Dynamic, 0, -300, 0);
		w.attachShape(lost, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01));
		expect(w, "WORLD_FELL_OUT", 'world/bodies/${w.bodySlot(lost)}/position');

		w = sound();
		// Each joint needs a body that can move when it is made; both are made static after.
		var a = w.createBody(BodyType.Dynamic, 3, 0, 0), b = w.createBody(BodyType.Dynamic, 4, 0, 0);
		w.attachShape(a, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01));
		w.attachShape(b, ShapeBuilder.makeHull(w.verts, box(0.1, 0.1, 0.1), 0.01));
		var joint = w.createDistanceJoint(a, b, 1);
		w.setBodyType(a, BodyType.Static);
		w.setBodyType(b, BodyType.Static);
		expect(w, "WORLD_JOINT_STATIC", 'world/joints/${w.joints.slotOf(joint)}');

		w = sound();
		var flat = w.createBody(BodyType.Static, -3, 0, 0);
		// The builders refuse a flat polygon, but the vertex buffers are public: flatten a triangle through them.
		var line = w.attachShape(flat, ShapeBuilder.makePolygon(w.verts, [new Vec3(0, 0), new Vec3(1, 0), new Vec3(0, 1)], 0.0, 0.0));
		var o = w.shapeVertOffset[w.shapeSlot(line)];
		w.verts.vx[o + 2] = 2; w.verts.vy[o + 2] = 0;
		expect(w, "WORLD_SHAPE_EMPTY", 'world/shapes/${w.shapeSlot(line)}');

		var full = new World(4, 4, 4);
		for (i in 0...4) full.createBody(BodyType.Static, i, 0, 0);
		expect(full, "WORLD_CAPACITY", "world/capacity/bodies");

		Sys.println('world validation: sound worlds report nothing; $batch validations in each dimension reuse reports with zero allocation; findings clear on reuse; each of 10 faults is reported with its code and path');
	}

	static function main():Void check();
}
