import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.WorldSnapshot;
import hxn.me.physics.core.Handles.BodyId;

class HingedChainChecks {
	static inline var DT = 1.0 / 60;

	static function bits(w:World):String {
		var out = new StringBuf();
		for (b in 0...w.bodyCount) {
			for (v in [w.posX[b],w.posY[b],w.posZ[b],w.rotX[b],w.rotY[b],w.rotZ[b],w.rotW[b],
				w.velX[b],w.velY[b],w.velZ[b],w.angVelX[b],w.angVelY[b],w.angVelZ[b]])
				out.add(haxe.io.FPHelper.floatToI32(v) + ",");
			out.add(w.islands.isAwake[b] + ":" + w.joints.splitVelocity[b] + ";");
		}
		for (c in 0...w.contacts.count) for (v in [w.contacts.normalImpulse[c],w.contacts.tangentImpulse1[c],w.contacts.tangentImpulse2[c]])
			out.add(haxe.io.FPHelper.floatToI32(v) + ",");
		return out.toString();
	}

	static function hanging(spatial:Bool, collide:Bool):Void {
		var chain = new HingeChain(spatial, collide), w = chain.world;
		var initial = chain.energy(), previous = initial, rise = 0.0, peak = initial;
		for (b in chain.bodies) if (Math.abs(1.0 / w.invMassY[b] - chain.mass) > 1e-7)
			throw "Chain mass does not match the cuboid oracle";
		for (frame in 0...3600) {
			w.step(DT);
			var energy = chain.energy();
			if (!Math.isFinite(energy) || energy > initial + chain.scale * 0.0001)
				throw 'Chain gained energy: spatial=$spatial collide=$collide frame=$frame energy=$energy';
			rise = Math.max(rise, energy - previous); peak = Math.max(peak, energy); previous = energy;
		}
		// Finite solver sweeps allow small stepwise energy errors; the release-energy bound is separate.
		if (rise > chain.scale * (collide ? 0.0001 : 0.002)) throw 'Chain energy rose by $rise in one step';
		for (b in chain.bodies) {
			if (w.posY[b] >= 10 || w.islands.isAwake[b] != 0 || w.velX[b] != 0 || w.velY[b] != 0
				|| w.velZ[b] != 0 || w.angVelX[b] != 0 || w.angVelY[b] != 0 || w.angVelZ[b] != 0)
				throw 'Chain did not settle below its anchor: spatial=$spatial collide=$collide body=$b';
		}
		if (w.validate().hasErrors) throw 'Chain validation failed: ${w.validate().toJson()}';
		if (haxe.Json.parse(w.describe()).bodies.length != w.activeBodyCount) throw "Chain describe lost a body";
		Sys.println('hinged chain spatial=$spatial collide=$collide: peak=$peak, step rise=$rise, final=$previous, asleep');
	}

	static function replay():Void {
		var chain = new HingeChain(), w = chain.world, snapshot = new WorldSnapshot();
		snapshot.save(w);
		for (_ in 0...180) w.step(DT);
		var expected = bits(w);
		snapshot.restore(w);
		for (_ in 0...180) w.step(DT);
		if (bits(w) != expected) throw "Loop replay changed after restoring release state";
		// A saved loop must keep its solve mode even when its contact edges are absent.
		for (s in 0...w.shapeCount) w.shapeMaskBits[s] = 0;
		w.contacts.clear(); w.step(DT);
		snapshot.save(w);
		for (_ in 0...90) w.step(DT);
		expected = bits(w);
		for (b in 0...w.bodyCount) w.joints.resetSplitVelocity(b);
		snapshot.restore(w);
		for (_ in 0...90) w.step(DT);
		if (bits(w) != expected) throw "Loop solve mode was not restored across a contact gap";
		var slot = chain.bodies[0];
		w.setBodyType(w.bodyHandleAt(slot),Kinematic);
		if (w.joints.splitVelocity[slot] != 0) throw "Changed body type retained the loop solve mode";
		w.destroyBody(w.bodyHandleAt(slot));
		var replacement = w.createBody(Dynamic, -20, 0);
		if (w.bodySlot(replacement) != slot || w.joints.splitVelocity[slot] != 0) throw "Recycled body inherited a loop";
	}

	static function correctionsAtRest():Void {
		var chain = new HingeChain(), w = chain.world;
		w.gravity = new Vec3();
		for (_ in 0...2) {
			w.step(DT);
			if (w.contacts.count == 0) throw "Resting correction check has no contacts";
			if (chain.energy(0) != 0) throw "Position correction created kinetic energy without a physical load";
			for (c in 0...w.contacts.count) if (w.contacts.normalImpulse[c] != 0
				|| w.contacts.tangentImpulse1[c] != 0 || w.contacts.tangentImpulse2[c] != 0)
				throw "Position correction was cached as a physical contact reaction at rest";
		}
	}

	static function neighboursAndIsolation():Void {
		var chain = new HingeChain(), w = chain.world;
		var neighbour = w.createBody(Dynamic, 0.5, 10.1);
		w.attachShape(neighbour, ShapeBuilder.makeBox(w.verts, 0.1, 0.05, 0.1, 0.01));
		w.step(DT);
		if (w.joints.splitVelocity[w.bodySlot(neighbour)] == 0) throw "Dynamic contact neighbour was not included";
		var reference = new World(8,8,8);
		function rotor(world:World, support:BodyId):Int {
			var a = support, b = world.createBody(Dynamic, -9.5, 10);
			world.attachShape(b, ShapeBuilder.makeBox(world.verts,0.1,0.1,0.2,0));
			world.createHingeJoint(a,b,new Vec3(0,10),new Vec3(0,0,1),-1e30,1e30,1.25,2);
			return world.bodySlot(b);
		}
		var a = rotor(w,w.bodyHandleAt(0)), b = rotor(reference,reference.createBody(Static,0,10));
		for (_ in 0...180) {
			w.step(DT); reference.step(DT);
			for (pair in [[w.posX[a],reference.posX[b]],[w.posY[a],reference.posY[b]],
				[w.rotZ[a],reference.rotZ[b]],[w.angVelZ[a],reference.angVelZ[b]]])
				if (haxe.io.FPHelper.floatToI32(pair[0]) != haxe.io.FPHelper.floatToI32(pair[1]))
					throw "A separate hinge changed when a contact loop was present";
		}
		if (w.joints.splitVelocity[a] != 0) throw "Loop selection leaked into a separate hinge";
	}

	static function branchesAtSupport():Void {
		var w = new World(4,4,4); w.gravity = new Vec3();
		var support = w.createBody(Static,0,0);
		var a = w.createBody(Dynamic,0.4,0), b = w.createBody(Dynamic,0.4,0.09);
		for (body in [a,b]) {
			w.attachShape(body,ShapeBuilder.makeBox(w.verts,0.1,0.05,0.1,0.01));
			w.createHingeJoint(support,body,new Vec3(0,0),new Vec3(0,0,1));
		}
		w.step(DT);
		if (w.contacts.count == 0 || w.joints.splitVelocity[w.bodySlot(a)] == 0
			|| w.joints.splitVelocity[w.bodySlot(b)] == 0 || w.joints.splitVelocity[w.bodySlot(support)] != 0)
			throw "Contact loop through a fixed support did not select both dynamic branches";
	}

	static function workersAndAllocation():Void {
		var serial = new HingeChain(true,true,4), parallel = new HingeChain(true,true,4);
		parallel.world.enableParallelIslands(4,1,0);
		for (_ in 0...240) {
			serial.world.step(DT); parallel.world.step(DT);
			if (bits(serial.world) != bits(parallel.world)) throw "Loop island worker solve changed state";
		}
		parallel.world.disableParallelIslands();
		var allocated = Allocation.least(() -> { for (_ in 0...8) serial.world.step(DT); },7);
		if (allocated != 0) throw 'Warm contact-loop steps allocated $allocated bytes';
		Sys.println("hinged chain: replay, snapshots across contact gaps, body reuse, neighbours, island isolation and workers agree; warm steps allocate nothing");
	}

	public static function run():Void {
		correctionsAtRest();
		for (spatial in [false,true]) for (collide in [false,true]) hanging(spatial,collide);
		replay(); neighboursAndIsolation(); branchesAtSupport(); workersAndAllocation();
	}
	static function main():Void run();
}
