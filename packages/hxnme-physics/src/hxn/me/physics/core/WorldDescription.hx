package hxn.me.physics.core;

import hxn.me.physics.diagnostics.Diagnostics;
import hxn.me.physics.collision.BroadPhase;
import hxn.me.physics.core.Handles.BodyType;

/** `WorldDescription` builds `World.describe` from the world's public buffers. */
class WorldDescription {
	static inline function num(v:Float):String
		return Diagnostics.number(v);

	public static function world(w:World):String {
		var out = new StringBuf();
		out.add('{"steps":${w.steps},"jointSweeps":${w.jointSweeps},"bodies":[');
		var slots = [for (p in 0...w.activeBodyCount) w.bodySlot(w.bodyHandleAt(p))];
		slots.sort((a, b) -> a - b);
		for (i in 0...slots.length) {
			if (i > 0)
				out.add(",");
			out.add(body(w, slots[i]));
		}
		out.add('],"joints":[');
		var j = w.joints;
		var ids = [for (i in 0...j.count) j.activeIds[i]];
		ids.sort((a, b) -> a - b);
		for (i in 0...ids.length) {
			var id = ids[i];
			if (i > 0)
				out.add(",");
			out.add('{"slot":$id,"kind":"${j.kindName(id)}","bodyA":${j.bodyA[id]},"bodyB":${j.bodyB[id]}}');
		}
		out.add('],"contacts":${w.contacts.count}}');
		return out.toString();
	}

	public static function body(w:World, slot:Int):String {
		var type = w.bodyType[slot];
		var out = new StringBuf();
		out.add('{"slot":$slot,"type":"${type == BodyType.Static ? "static" : type == BodyType.Kinematic ? "kinematic" : "dynamic"}"');
		out.add(',"awake":${type != BodyType.Static && w.islands.isAwake[slot] != 0}');
		out.add(',"position":[${num(w.posX[slot])},${num(w.posY[slot])},${num(w.posZ[slot])}]');
		out.add(',"rotation":[${num(w.rotX[slot])},${num(w.rotY[slot])},${num(w.rotZ[slot])},${num(w.rotW[slot])}]');
		out.add(',"velocity":[${num(w.velX[slot])},${num(w.velY[slot])},${num(w.velZ[slot])}]');
		out.add(',"angularVelocity":[${num(w.angVelX[slot])},${num(w.angVelY[slot])},${num(w.angVelZ[slot])}]');
		out.add(',"shapes":[');
		var s = w.firstShape[slot], first = true;
		while (s != -1) {
			if (!first)
				out.add(",");
			first = false;
			var kind = ["circle", "capsule", "polygon", "hull"][w.shapeKind[s]];
			out.add('{"slot":$s,"kind":"$kind","radius":${num(w.shapeRadius[s])},"depth":${num(w.shapeDepth[s])}');
			out.add(',"sensor":${w.shapeSensor[s] != 0},"enabled":${w.shapeProxy[s] != BroadPhase.NULL_NODE},"vertices":${w.shapeVertCount[s]}}');
			s = w.shapeNext[s];
		}
		out.add("]}");
		return out.toString();
	}
}
