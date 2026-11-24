import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Vec3;
import hxn.me.physics.core.Handles.BodyId;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.core.World;
import hxn.me.physics.core.WorldSnapshot;

/** `WorldGrowthChecks` checks that each world given more room as it runs continues exactly as a world made that large from the start: every body, contact and joint, bit for bit. */
class WorldGrowthChecks {
	static function check(ok:Bool, what:String):Void
		if (!ok)
			throw what;

	static function box(w:World, half:Float) {
		var corners = [for (k in 0...8) new Vec3(k & 1 != 0 ? half : -half, k & 2 != 0 ? half : -half, k & 4 != 0 ? half : -half)];
		return ShapeBuilder.makeHull(w.verts, corners, 0.0);
	}

	/** Adds boxes in a leaning grid, a hinge chain, and one joint of each other kind, with the same calls in every world. */
	static function populate(w:World, boxes:Int, links:Int, tag:Int, handles:Array<BodyId>):Void {
		if (tag == 0) {
			var floor = w.createBody(BodyType.Static, 0, -0.5, 0);
			w.attachShape(floor, box(w, 30), 1, -1, 0, 0.8);
			handles.push(floor);
		}
		for (i in 0...boxes) {
			var b = w.createBody(BodyType.Dynamic, (i % 7) * 1.05 + tag * 0.01, 0.6 + (Std.int(i / 7) % 6) * 1.1, Std.int(i / 42) * 1.1 + tag);
			w.attachShape(b, box(w, 0.5), 1, -1, 0, 0.5);
			handles.push(b);
		}
		var anchor = w.createBody(BodyType.Static, -12 + tag * 3, 9, 0);
		w.attachShape(anchor, box(w, 0.2), 1, -1, 0, 0.5);
		var previous = anchor;
		for (i in 0...links) {
			var link = w.createBody(BodyType.Dynamic, -12 + tag * 3 + (i + 1) * 0.6, 9, 0);
			w.attachShape(link, box(w, 0.25), 1, -1, 0, 0.5);
			w.joints.createHinge(previous, link, new Vec3(-12 + tag * 3 + i * 0.6 + 0.3, 9, 0), new Vec3(0, 0, 1));
			handles.push(link);
			previous = link;
		}
		var a = w.createBody(BodyType.Dynamic, 14 + tag, 4, 0), b = w.createBody(BodyType.Dynamic, 15 + tag, 4, 0), c = w.createBody(BodyType.Dynamic, 16 + tag, 4, 0);
		for (body in [a, b, c]) {
			w.attachShape(body, box(w, 0.3), 1, -1, 0, 0.5);
			handles.push(body);
		}
		w.joints.createDistance(a, b, 1.0);
		w.joints.createWeld(b, c, new Vec3(15.5 + tag, 4, 0));
		w.joints.createPrismatic(a, anchor, new Vec3(14 + tag, 5, 0), new Vec3(0, 1, 0), -1, 1);
		w.joints.createSpherical(c, anchor, new Vec3(16 + tag, 5, 0), new Vec3(0, 1, 0), 0.8, -0.5, 0.5);
	}

	static function same(a:World, b:World, handlesA:Array<BodyId>, handlesB:Array<BodyId>, what:String):Void {
		check(a.activeBodyCount == b.activeBodyCount && a.bodyCount == b.bodyCount, '$what: body counts differ');
		check(a.contacts.count == b.contacts.count && a.joints.count == b.joints.count, '$what: contact or joint counts differ');
		check(a.islands.islandCount == b.islands.islandCount, '$what: island counts differ');
		for (k in 0...handlesA.length) {
			var i = a.bodySlot(handlesA[k]), j = b.bodySlot(handlesB[k]);
			check(i == j, '$what: body $k sits in slot $i, not $j');
			check(a.posX[i] == b.posX[j] && a.posY[i] == b.posY[j] && a.posZ[i] == b.posZ[j], '$what: body $k is somewhere else');
			check(a.rotX[i] == b.rotX[j] && a.rotY[i] == b.rotY[j] && a.rotZ[i] == b.rotZ[j] && a.rotW[i] == b.rotW[j], '$what: body $k is turned differently');
			check(a.velX[i] == b.velX[j] && a.velY[i] == b.velY[j] && a.velZ[i] == b.velZ[j], '$what: body $k moves differently');
			check(a.angVelX[i] == b.angVelX[j] && a.angVelY[i] == b.angVelY[j] && a.angVelZ[i] == b.angVelZ[j], '$what: body $k spins differently');
		}
	}

	/** Checks that each saved state restores into a world of a different size. Larger worlds keep their room and reset the extra room as new. Smaller worlds get the room. */
	static function snapshotsAcrossCapacities():Void {
		var small = new World(4, 4, 1), large = new World(4096, 8192, 256);
		var hs:Array<BodyId> = [], hl:Array<BodyId> = [];
		populate(small, 40, 8, 0, hs);
		populate(large, 40, 8, 0, hl);
		for (_ in 0...60) {
			small.step(1 / 60);
			large.step(1 / 60);
		}
		// The snapshot is taken at the world's own size. Then the world gets more room and runs on. The
		// restore puts it back, and it continues as the large world does.
		var saved = new WorldSnapshot();
		saved.save(small);
		small.reserve(900, 900, 90);
		for (_ in 0...40)
			small.step(1 / 60);
		saved.restore(small);
		same(small, large, hs, hl, "after restoring into a world given more room");
		for (_ in 0...80) {
			small.step(1 / 60);
			large.step(1 / 60);
		}
		same(small, large, hs, hl, "after stepping on from the restore");
		// The room the snapshot did not cover is usable: more bodies and shapes go into the tree's new nodes.
		var moreSmall:Array<BodyId> = [], moreLarge:Array<BodyId> = [];
		populate(small, 70, 6, 1, moreSmall);
		populate(large, 70, 6, 1, moreLarge);
		for (_ in 0...60) {
			small.step(1 / 60);
			large.step(1 / 60);
		}
		same(small, large, moreSmall, moreLarge, "the bodies made after a restore into a world with more room");
		// This snapshot is taken from a large world and restored into a small world, which gets the room.
		var big = new World(4096, 8192, 256), hb:Array<BodyId> = [];
		populate(big, 40, 8, 0, hb);
		for (_ in 0...140)
			big.step(1 / 60);
		var fromLarge = new WorldSnapshot();
		fromLarge.save(big);
		var twin = new World(4, 4, 1), ht:Array<BodyId> = [];
		populate(twin, 40, 8, 0, ht);
		for (_ in 0...140)
			twin.step(1 / 60);
		same(twin, big, ht, hb, "a world made the same way and stepped as far");
		var before = twin.bodyCapacity;
		fromLarge.restore(twin);
		check(twin.bodyCapacity >= big.bodyCapacity && twin.shapeCapacity >= big.shapeCapacity && twin.bodyCapacity >= before,
			"a restore did not give the world the room it was saved with");
		same(twin, big, ht, hb, "after restoring a large world's state into a small one");
		for (_ in 0...60) {
			twin.step(1 / 60);
			big.step(1 / 60);
		}
		same(twin, big, ht, hb, "after stepping on from the larger world's state");
	}

	static function main():Void {
		var small = new World(4, 4, 1), large = new World(4096, 8192, 256);
		var hs:Array<BodyId> = [], hl:Array<BodyId> = [];
		populate(small, 60, 10, 0, hs);
		populate(large, 60, 10, 0, hl);
		check(small.bodyCapacity >= 72 && small.shapeCapacity >= 72 && small.joints.capacity >= 14, "the small world did not grow to hold what was made");
		check(small.capacityRevision > 0, "growth was not reported");
		for (_ in 0...90) {
			small.step(1 / 60);
			large.step(1 / 60);
		}
		same(small, large, hs, hl, "after the first run");
		// Growth in the middle of a run, with bodies asleep or moving, and an explicit reserve with freed bodies on the free lists.
		var before = small.capacityRevision;
		for (k in 0...5) {
			small.destroyBody(hs[10 + k]);
			large.destroyBody(hl[10 + k]);
		}
		small.reserve(300, 400, 40);
		check(small.capacityRevision > before && small.bodyCapacity >= 300 && small.shapeCapacity >= 400 && small.joints.capacity >= 40, "reserve did not take");
		var more:Array<BodyId> = [], moreLarge:Array<BodyId> = [];
		populate(small, 80, 12, 1, more);
		populate(large, 80, 12, 1, moreLarge);
		for (_ in 0...120) {
			small.step(1 / 60);
			large.step(1 / 60);
		}
		var kept = [for (k in 0...hs.length) if (k < 10 || k >= 15) k];
		same(small, large, [for (k in kept) hs[k]], [for (k in kept) hl[k]], "after growing mid-run");
		same(small, large, more, moreLarge, "the bodies made after growth");
		// Growth past a million is refused, and a handle from before growth is still good.
		var threw = false;
		try
			small.reserve((1 << 20) + 1, 0)
		catch (_:Dynamic)
			threw = true;
		check(threw, "a capacity past the handle limit was accepted");
		check(small.bodySlot(hs[0]) == large.bodySlot(hl[0]), "a handle from before growth stopped working");
		snapshotsAcrossCapacities();
		Sys.println("world growth: bodies, shapes, joints of every kind and vertices grow on demand, mid-run and by reserve, and the run matches a world made large");
	}
}
