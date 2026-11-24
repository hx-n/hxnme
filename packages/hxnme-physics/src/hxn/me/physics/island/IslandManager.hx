package hxn.me.physics.island;

import hxn.me.math.Grow;
import hxn.Float32Buffer;
import hxn.me.physics.collision.NarrowPhase.ContactManifoldPool;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.joints.JointPool;
import hxn.Int32Buffer;

class IslandManager {
	public static inline var LINEAR_TOLERANCE:Float = 0.01;
	public static inline var ANGULAR_TOLERANCE:Float = 0.02;
	public static inline var SLEEP_DELAY:Float = 0.5;
	static inline var POSITION_TOLERANCE:Float = 0.01;
	static inline var ROTATION_DOT_TOLERANCE:Float = 0.9998875;

	public var isAwake:Int32Buffer;
	public var integrationMask:Float32Buffer;
	public var sleepTimer:Float32Buffer;
	public var parent:Int32Buffer;
	public var islandCount(default, null):Int = 0;

	var sleepGroup:Int32Buffer;
	var eligible:Int32Buffer;
	var minimumTime:Float32Buffer;
	var referenceValid:Int32Buffer;
	var referenceX:Float32Buffer;
	var referenceY:Float32Buffer;
	var referenceZ:Float32Buffer;
	var referenceQX:Float32Buffer;
	var referenceQY:Float32Buffer;
	var referenceQZ:Float32Buffer;
	var referenceQW:Float32Buffer;

	public function new(capacity:Int) {
		isAwake = new Int32Buffer(capacity);
		integrationMask = new Float32Buffer(capacity);
		sleepTimer = new Float32Buffer(capacity);
		parent = new Int32Buffer(capacity);
		sleepGroup = new Int32Buffer(capacity);
		eligible = new Int32Buffer(capacity);
		minimumTime = new Float32Buffer(capacity);
		referenceValid = new Int32Buffer(capacity);
		referenceX = new Float32Buffer(capacity);
		referenceY = new Float32Buffer(capacity);
		referenceZ = new Float32Buffer(capacity);
		referenceQX = new Float32Buffer(capacity);
		referenceQY = new Float32Buffer(capacity);
		referenceQZ = new Float32Buffer(capacity);
		referenceQW = new Float32Buffer(capacity);
		for (i in 0...capacity)
			sleepGroup[i] = -1;
	}

	/** Marks the bodies from `from` as in no sleep group, as in a new world. */
	public function clearTail(from:Int):Void
		for (i in from...sleepGroup.length)
			sleepGroup[i] = -1;

	/** Makes room for `to` bodies, and keeps the first `from`. */
	public function grow(from:Int, to:Int):Void {
		isAwake = Grow.ints(isAwake, from, to);
		integrationMask = Grow.floats(integrationMask, from, to);
		sleepTimer = Grow.floats(sleepTimer, from, to);
		parent = Grow.ints(parent, from, to);
		sleepGroup = Grow.ints(sleepGroup, from, to, -1);
		eligible = Grow.ints(eligible, from, to);
		minimumTime = Grow.floats(minimumTime, from, to);
		referenceValid = Grow.ints(referenceValid, from, to);
		referenceX = Grow.floats(referenceX, from, to);
		referenceY = Grow.floats(referenceY, from, to);
		referenceZ = Grow.floats(referenceZ, from, to);
		referenceQX = Grow.floats(referenceQX, from, to);
		referenceQY = Grow.floats(referenceQY, from, to);
		referenceQZ = Grow.floats(referenceQZ, from, to);
		referenceQW = Grow.floats(referenceQW, from, to);
	}


	public function addBody(body:Int, type:BodyType):Void {
		parent[body] = body;
		sleepGroup[body] = -1;
		sleepTimer[body] = 0.0;
		referenceValid[body] = 0;
		isAwake[body] = type == BodyType.Static ? 0 : 1;
		integrationMask[body] = type == BodyType.Static ? 0.0 : 1.0;
	}

	public function wakeBody(body:Int, bodyType:Int32Buffer, bodyCount:Int):Void {
		if (body < 0 || body >= bodyCount || bodyType[body] != BodyType.Dynamic)
			return;
		var group = sleepGroup[body];
		if (group < 0) {
			isAwake[body] = 1;
			integrationMask[body] = 1.0;
			sleepTimer[body] = 0.0;
			referenceValid[body] = 0;
			return;
		}
		for (i in 0...bodyCount) {
			if (sleepGroup[i] == group && bodyType[i] == BodyType.Dynamic) {
				sleepGroup[i] = -1;
				isAwake[i] = 1;
				integrationMask[i] = 1.0;
				sleepTimer[i] = 0.0;
				referenceValid[i] = 0;
			}
		}
	}

	public function build(contacts:ContactManifoldPool, bodyType:Int32Buffer, bodyCount:Int, joints:JointPool = null):Void {
		islandCount = 0;
		for (body in 0...bodyCount)
			parent[body] = body;
		for (c in 0...contacts.count) {
			var a = contacts.bodyA[c], b = contacts.bodyB[c];
			if (bodyType[a] == BodyType.Dynamic && bodyType[b] == BodyType.Dynamic && isAwake[a] != 0 && isAwake[b] != 0)
				merge(a, b);
		}
		if (joints != null) {
			for (position in 0...joints.count) {
				var id = joints.activeIds[position];
				var a = joints.bodyA[id], b = joints.bodyB[id];
				if (bodyType[a] == BodyType.Dynamic && bodyType[b] == BodyType.Dynamic && isAwake[a] != 0 && isAwake[b] != 0)
					merge(a, b);
			}
		}
		for (body in 0...bodyCount) {
			if (bodyType[body] == BodyType.Dynamic && isAwake[body] != 0 && root(body) == body)
				islandCount++;
		}
	}

	public function root(body:Int):Int {
		var result = body;
		while (parent[result] != result)
			result = parent[result];
		while (parent[body] != body) {
			var next = parent[body];
			parent[body] = result;
			body = next;
		}
		return result;
	}

	function merge(a:Int, b:Int):Void {
		var ra = root(a), rb = root(b);
		if (ra == rb)
			return;
		if (ra < rb)
			parent[rb] = ra;
		else
			parent[ra] = rb;
	}

	public function updateSleep(dt:Single, bodyType:Int32Buffer, bodyCount:Int, velX:Float32Buffer, velY:Float32Buffer, velZ:Float32Buffer,
			angVelX:Float32Buffer, angVelY:Float32Buffer, angVelZ:Float32Buffer, posX:Float32Buffer, posY:Float32Buffer, posZ:Float32Buffer, rotX:Float32Buffer,
			rotY:Float32Buffer, rotZ:Float32Buffer, rotW:Float32Buffer):Void {
		for (body in 0...bodyCount) {
			eligible[body] = 1;
			minimumTime[body] = 1.0e9;
		}
		for (body in 0...bodyCount) {
			if (bodyType[body] != BodyType.Dynamic || isAwake[body] == 0)
				continue;
			var island = root(body);
			var linear = velX[body] * velX[body] + velY[body] * velY[body] + velZ[body] * velZ[body];
			var angular = angVelX[body] * angVelX[body] + angVelY[body] * angVelY[body] + angVelZ[body] * angVelZ[body];
			if (referenceValid[body] == 0) {
				referenceX[body] = posX[body];
				referenceY[body] = posY[body];
				referenceZ[body] = posZ[body];
				referenceQX[body] = rotX[body];
				referenceQY[body] = rotY[body];
				referenceQZ[body] = rotZ[body];
				referenceQW[body] = rotW[body];
				referenceValid[body] = 1;
			}
			var dx = posX[body] - referenceX[body],
				dy = posY[body] - referenceY[body];
			var dz = posZ[body] - referenceZ[body];
			var rotationDot = Math.abs(rotX[body] * referenceQX[body]
				+ rotY[body] * referenceQY[body] + rotZ[body] * referenceQZ[body] + rotW[body] * referenceQW[body]);
			var stablePose = dx * dx + dy * dy + dz * dz < POSITION_TOLERANCE * POSITION_TOLERANCE && rotationDot > ROTATION_DOT_TOLERANCE;
			if (!stablePose) {
				referenceX[body] = posX[body];
				referenceY[body] = posY[body];
				referenceZ[body] = posZ[body];
				referenceQX[body] = rotX[body];
				referenceQY[body] = rotY[body];
				referenceQZ[body] = rotZ[body];
				referenceQW[body] = rotW[body];
			}
			// Constraint correction can leave velocity while the solved pose is stationary.
			if (!stablePose && (linear >= LINEAR_TOLERANCE * LINEAR_TOLERANCE || angular >= ANGULAR_TOLERANCE * ANGULAR_TOLERANCE)) {
				sleepTimer[body] = 0.0;
				eligible[island] = 0;
			} else {
				sleepTimer[body] += dt;
				if (sleepTimer[body] < minimumTime[island])
					minimumTime[island] = sleepTimer[body];
			}
		}
		for (body in 0...bodyCount) {
			if (bodyType[body] != BodyType.Dynamic || isAwake[body] == 0)
				continue;
			var island = root(body);
			if (eligible[island] == 0 || minimumTime[island] < SLEEP_DELAY)
				continue;
			isAwake[body] = 0;
			integrationMask[body] = 0.0;
			sleepGroup[body] = island;
			velX[body] = velY[body] = velZ[body] = 0.0;
			angVelX[body] = angVelY[body] = angVelZ[body] = 0.0;
		}
	}

	/** Visits sleep state for `WorldSnapshot`. */
	@:noCompletion public function visitState(s:hxn.me.physics.core.WorldSnapshot, bodies:Int):Void {
		islandCount = s.int(islandCount);
		s.ints(isAwake, bodies);
		s.ints(parent, bodies);
		s.ints(sleepGroup, bodies);
		s.ints(referenceValid, bodies);
		s.floats(integrationMask, bodies);
		s.floats(sleepTimer, bodies);
		s.floats(referenceX, bodies);
		s.floats(referenceY, bodies);
		s.floats(referenceZ, bodies);
		s.floats(referenceQX, bodies);
		s.floats(referenceQY, bodies);
		s.floats(referenceQZ, bodies);
		s.floats(referenceQW, bodies);
	}
}
