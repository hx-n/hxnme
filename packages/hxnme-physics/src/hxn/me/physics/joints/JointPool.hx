package hxn.me.physics.joints;

import hxn.me.math.Grow;
import hxn.me.math.Vec3;
import hxn.me.math.Quat;
import hxn.Float32Buffer;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyId;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.core.Handles.DoFMask;
import hxn.me.physics.core.Handles.JointId;
import hxn.Int32Buffer;

@:allow(hxn.me.physics.joints.HingeSolver)
@:allow(hxn.me.physics.joints.PrismaticSolver)
@:allow(hxn.me.physics.joints.WeldSolver)
@:allow(hxn.me.physics.joints.SphericalSolver)
@:allow(hxn.me.physics.solver.SoftStepSolver)
class JointPool {
	static inline var INDEX_MASK:Int = (1 << 20) - 1;
	static inline var DISTANCE:Int = 0;
	static inline var HINGE:Int = 1;
	static inline var PRISMATIC:Int = 2;
	static inline var WELD:Int = 3;
	static inline var SPHERICAL:Int = 4;

	public var world:World;
	public var capacity:Int;
	public var count(default, null):Int = 0;
	public var activeIds:Int32Buffer;
	public var bodyA:Int32Buffer;
	public var bodyB:Int32Buffer;

	var kind:Int32Buffer;
	var rows:JointRows;
	var hinge:HingeSolver;
	var prismatic:PrismaticSolver;
	var weld:WeldSolver;
	var spherical:SphericalSolver;

	public var restLength:Float32Buffer;
	public var frequencyHz:Float32Buffer;
	public var dampingRatio:Float32Buffer;

	var activePosition:Int32Buffer;
	var generation:Int32Buffer;
	var nextFree:Int32Buffer;
	var collisionDisabled:Int32Buffer;
	var firstExcluded:Int32Buffer;
	var nextExcludedA:Int32Buffer;
	var nextExcludedB:Int32Buffer;
	var used:Int = 0;
	var freeHead:Int = -1;

	/** Holds each joint's anchor in the frames of body A and body B, by joint slot. */
	public var anchorAX(default, null):Float32Buffer;

	public var anchorAY(default, null):Float32Buffer;
	public var anchorAZ(default, null):Float32Buffer;
	public var anchorBX(default, null):Float32Buffer;
	public var anchorBY(default, null):Float32Buffer;
	public var anchorBZ(default, null):Float32Buffer;

	var axisX:Float32Buffer;
	var axisY:Float32Buffer;
	var axisZ:Float32Buffer;
	var rAX:Float32Buffer;
	var rAY:Float32Buffer;
	var rAZ:Float32Buffer;
	var rBX:Float32Buffer;
	var rBY:Float32Buffer;
	var rBZ:Float32Buffer;
	var impulse:Float32Buffer;
	var loopParent:Int32Buffer;
	var loopRank:Int32Buffer;
	var loopMarked:Int32Buffer;
	var jointParent:Int32Buffer;
	var jointRank:Int32Buffer;

	/** Marks the bodies in a contact loop through joints, including their dynamic contact neighbors. */
	@:noCompletion public var splitVelocity(default, null):Int32Buffer;

	public function new(world:World, capacity:Int) {
		if (capacity < 0 || capacity > (1 << 20))
			throw 'Invalid joint capacity';
		this.world = world;
		this.capacity = capacity;
		loopParent = new Int32Buffer(world.bodyCapacity);
		loopRank = new Int32Buffer(world.bodyCapacity);
		loopMarked = new Int32Buffer(world.bodyCapacity);
		jointParent = new Int32Buffer(world.bodyCapacity);
		jointRank = new Int32Buffer(world.bodyCapacity);
		splitVelocity = new Int32Buffer(world.bodyCapacity);
		for (b in 0...world.bodyCapacity)
			splitVelocity[b] = 0;
		activeIds = new Int32Buffer(capacity);
		bodyA = new Int32Buffer(capacity);
		bodyB = new Int32Buffer(capacity);
		kind = new Int32Buffer(capacity);
		activePosition = new Int32Buffer(capacity);
		generation = new Int32Buffer(capacity);
		nextFree = new Int32Buffer(capacity);
		collisionDisabled = new Int32Buffer(capacity);
		firstExcluded = new Int32Buffer(world.bodyCapacity);
		nextExcludedA = new Int32Buffer(capacity);
		nextExcludedB = new Int32Buffer(capacity);
		anchorAX = new Float32Buffer(capacity);
		anchorAY = new Float32Buffer(capacity);
		anchorAZ = new Float32Buffer(capacity);
		anchorBX = new Float32Buffer(capacity);
		anchorBY = new Float32Buffer(capacity);
		anchorBZ = new Float32Buffer(capacity);
		restLength = new Float32Buffer(capacity);
		frequencyHz = new Float32Buffer(capacity);
		dampingRatio = new Float32Buffer(capacity);
		axisX = new Float32Buffer(capacity);
		axisY = new Float32Buffer(capacity);
		axisZ = new Float32Buffer(capacity);
		rAX = new Float32Buffer(capacity);
		rAY = new Float32Buffer(capacity);
		rAZ = new Float32Buffer(capacity);
		rBX = new Float32Buffer(capacity);
		rBY = new Float32Buffer(capacity);
		rBZ = new Float32Buffer(capacity);
		impulse = new Float32Buffer(capacity);
		rows = new JointRows(world, capacity);
		for (i in 0...capacity) {
			activePosition[i] = -1;
			generation[i] = 0;
		}
		for (i in 0...world.bodyCapacity)
			firstExcluded[i] = -1;
	}
	/** Resets the joint slots from `joints` and the bodies from `bodies` to the state of a new pool, after a restore into a larger world. */
	public function clearTails(bodies:Int, joints:Int):Void {
		for (i in joints...capacity)
			activePosition[i] = -1;
		for (i in bodies...firstExcluded.length)
			firstExcluded[i] = -1;
	}

	/**
	 * Makes room for more bodies and joints, and keeps what is stored. The
	 * world raises its own body capacity first, then the joint solvers and the
	 * per-substep rows follow.
	 */
	public function grow(newBodies:Int, newJoints:Int):Void {
		var bodies = loopParent.length, joints = capacity;
		if (newBodies < bodies || newJoints < joints)
			throw 'A joint pool does not shrink';
		if (newBodies > bodies) {
			loopParent = Grow.ints(loopParent, bodies, newBodies);
			loopRank = Grow.ints(loopRank, bodies, newBodies);
			loopMarked = Grow.ints(loopMarked, bodies, newBodies);
			jointParent = Grow.ints(jointParent, bodies, newBodies);
			jointRank = Grow.ints(jointRank, bodies, newBodies);
			splitVelocity = Grow.ints(splitVelocity, bodies, newBodies);
			firstExcluded = Grow.ints(firstExcluded, bodies, newBodies, -1);
		}
		if (newJoints > joints) {
			activeIds = Grow.ints(activeIds, joints, newJoints);
			bodyA = Grow.ints(bodyA, joints, newJoints);
			bodyB = Grow.ints(bodyB, joints, newJoints);
			kind = Grow.ints(kind, joints, newJoints);
			activePosition = Grow.ints(activePosition, joints, newJoints, -1);
			generation = Grow.ints(generation, joints, newJoints);
			nextFree = Grow.ints(nextFree, joints, newJoints);
			collisionDisabled = Grow.ints(collisionDisabled, joints, newJoints);
			nextExcludedA = Grow.ints(nextExcludedA, joints, newJoints);
			nextExcludedB = Grow.ints(nextExcludedB, joints, newJoints);
			anchorAX = Grow.floats(anchorAX, joints, newJoints);
			anchorAY = Grow.floats(anchorAY, joints, newJoints);
			anchorAZ = Grow.floats(anchorAZ, joints, newJoints);
			anchorBX = Grow.floats(anchorBX, joints, newJoints);
			anchorBY = Grow.floats(anchorBY, joints, newJoints);
			anchorBZ = Grow.floats(anchorBZ, joints, newJoints);
			restLength = Grow.floats(restLength, joints, newJoints);
			frequencyHz = Grow.floats(frequencyHz, joints, newJoints);
			dampingRatio = Grow.floats(dampingRatio, joints, newJoints);
			axisX = Grow.floats(axisX, joints, newJoints);
			axisY = Grow.floats(axisY, joints, newJoints);
			axisZ = Grow.floats(axisZ, joints, newJoints);
			rAX = Grow.floats(rAX, joints, newJoints);
			rAY = Grow.floats(rAY, joints, newJoints);
			rAZ = Grow.floats(rAZ, joints, newJoints);
			rBX = Grow.floats(rBX, joints, newJoints);
			rBY = Grow.floats(rBY, joints, newJoints);
			rBZ = Grow.floats(rBZ, joints, newJoints);
			impulse = Grow.floats(impulse, joints, newJoints);
			capacity = newJoints;
			if (hinge != null)
				hinge.grow(joints, newJoints);
			if (prismatic != null)
				prismatic.grow(joints, newJoints);
			if (weld != null)
				weld.grow(joints, newJoints);
			if (spherical != null)
				spherical.grow(joints, newJoints);
		}
		rows = new JointRows(world, capacity);
	}


	/** Asks the world for twice the room, up to the limit that a handle's index allows. The pool calls it when a new joint does not fit. */
	function roomForOneMore():Void {
		if (capacity >= (1 << 20))
			throw 'Joint capacity exceeded';
		world.reserve(0, 0, Std.int(Math.min(1 << 20, Math.max(8, capacity * 2.0))));
	}

	public function createDistance(a:BodyId, b:BodyId, length:Single, frequency:Single = 0.0, damping:Single = 1.0, localA:Vec3 = null,
			localB:Vec3 = null):JointId {
		var ia = world.bodySlot(a), ib = world.bodySlot(b);
		if (ia == ib)
			throw 'Invalid joint bodies';
		if (world.bodyType[ia] == BodyType.Static && world.bodyType[ib] == BodyType.Static)
			throw 'Joint needs a body that can move';
		if (!Math.isFinite(length) || length < 0.0 || !Math.isFinite(frequency) || frequency < 0.0 || !Math.isFinite(damping) || damping < 0.0)
			throw 'Invalid distance joint parameters';
		if (localA == null)
			localA = new Vec3();
		if (localB == null)
			localB = new Vec3();
		for (v in [localA, localB]) {
			if (!Math.isFinite(v.x) || !Math.isFinite(v.y) || !Math.isFinite(v.z))
				throw 'Invalid joint anchor';
		}
		var id = reserve(ia, ib, DISTANCE);
		anchorAX[id] = localA.x;
		anchorAY[id] = localA.y;
		anchorAZ[id] = localA.z;
		anchorBX[id] = localB.x;
		anchorBY[id] = localB.y;
		anchorBZ[id] = localB.z;
		restLength[id] = length;
		frequencyHz[id] = frequency;
		dampingRatio[id] = damping;
		impulse[id] = 0.0;
		return (generation[id] << 20) | id;
	}

	public function createHinge(a:BodyId, b:BodyId, worldAnchor:Vec3, worldAxis:Vec3 = null, lowerAngle:Single = -1.0e30, upperAngle:Single = 1.0e30,
			motorSpeed:Single = 0.0, maxMotorTorque:Single = 0.0):JointId {
		var ia = world.bodySlot(a), ib = world.bodySlot(b);
		if (ia == ib)
			throw 'Invalid joint bodies';
		if (world.bodyType[ia] == BodyType.Static && world.bodyType[ib] == BodyType.Static)
			throw 'Joint needs a body that can move';
		if (worldAnchor == null || !Math.isFinite(worldAnchor.x) || !Math.isFinite(worldAnchor.y) || !Math.isFinite(worldAnchor.z))
			throw 'Invalid hinge anchor';
		if (worldAxis == null)
			worldAxis = new Vec3(0, 0, 1);
		var axisLength = Math.sqrt(Vec3.lengthSq(worldAxis));
		if (!Math.isFinite(axisLength) || axisLength < 1e-6 || !Math.isFinite(lowerAngle) || !Math.isFinite(upperAngle) || lowerAngle > upperAngle
			|| !Math.isFinite(motorSpeed) || !Math.isFinite(maxMotorTorque) || maxMotorTorque < 0.0)
			throw 'Invalid hinge parameters';
		var axis = Vec3.scale(worldAxis, 1.0 / axisLength);
		if (world.bodyDoF[ia] != DoFMask.Full3D
			&& world.bodyDoF[ib] != DoFMask.Full3D
			&& (Math.abs(axis.x) > 1e-5 || Math.abs(axis.y) > 1e-5))
			throw 'Planar hinge axis must be vertical';
		if (count >= capacity)
			roomForOneMore();
		var qa = new Quat(world.rotX[ia], world.rotY[ia], world.rotZ[ia], world.rotW[ia]);
		var qb = new Quat(world.rotX[ib], world.rotY[ib], world.rotZ[ib], world.rotW[ib]);
		var localA = Quat.invRotate(qa, new Vec3(worldAnchor.x - world.posX[ia], worldAnchor.y - world.posY[ia], worldAnchor.z - world.posZ[ia]));
		var localB = Quat.invRotate(qb, new Vec3(worldAnchor.x - world.posX[ib], worldAnchor.y - world.posY[ib], worldAnchor.z - world.posZ[ib]));
		if (hinge == null)
			hinge = new HingeSolver(this, capacity);
		var id = reserve(ia, ib, HINGE);
		anchorAX[id] = localA.x;
		anchorAY[id] = localA.y;
		anchorAZ[id] = localA.z;
		anchorBX[id] = localB.x;
		anchorBY[id] = localB.y;
		anchorBZ[id] = localB.z;
		hinge.initialize(id, qa, qb, axis, lowerAngle, upperAngle, motorSpeed, maxMotorTorque);
		return (generation[id] << 20) | id;
	}

	/** Moves a joint's anchors, each in its body's frame relative to the body's origin. */
	public function setAnchors(joint:JointId, localA:Vec3, localB:Vec3):Void {
		var value:Int = joint;
		var id = value & INDEX_MASK;
		if (id >= used || activePosition[id] < 0 || generation[id] != (value >>> 20))
			throw 'Invalid joint id';
		for (v in [localA, localB])
			if (v == null || !Math.isFinite(v.x) || !Math.isFinite(v.y) || !Math.isFinite(v.z))
				throw 'Invalid joint anchor';
		anchorAX[id] = localA.x;
		anchorAY[id] = localA.y;
		anchorAZ[id] = localA.z;
		anchorBX[id] = localB.x;
		anchorBY[id] = localB.y;
		anchorBZ[id] = localB.z;
		world.wakeBodySlot(bodyA[id]);
		world.wakeBodySlot(bodyB[id]);
	}

	public function setHingeDrive(joint:JointId, targetAngle:Single, stiffness:Single, damping:Single, maxTorque:Single):Void {
		var value:Int = joint;
		var id = value & INDEX_MASK;
		if (id >= used || activePosition[id] < 0 || generation[id] != (value >>> 20) || kind[id] != HINGE)
			throw 'Invalid hinge joint id';
		if (!Math.isFinite(targetAngle) || !Math.isFinite(stiffness) || stiffness < 0.0 || !Math.isFinite(damping) || damping < 0.0
			|| !Math.isFinite(maxTorque) || maxTorque < 0.0)
			throw 'Invalid hinge drive parameters';
		hinge.setDrive(id, targetAngle, stiffness, damping, maxTorque);
		world.wakeBodySlot(bodyA[id]);
		world.wakeBodySlot(bodyB[id]);
	}

	public function createPrismatic(a:BodyId, b:BodyId, worldAnchor:Vec3, worldAxis:Vec3, lowerTranslation:Single = -1.0e30, upperTranslation:Single = 1.0e30,
			motorSpeed:Single = 0.0, maxMotorForce:Single = 0.0):JointId {
		var ia = world.bodySlot(a), ib = world.bodySlot(b);
		if (ia == ib)
			throw 'Invalid joint bodies';
		if (world.bodyType[ia] == BodyType.Static && world.bodyType[ib] == BodyType.Static)
			throw 'Joint needs a body that can move';
		if (worldAnchor == null || !Math.isFinite(worldAnchor.x) || !Math.isFinite(worldAnchor.y) || !Math.isFinite(worldAnchor.z))
			throw 'Invalid slider anchor';
		if (worldAxis == null)
			throw 'Invalid slider axis';
		var axisLength = Math.sqrt(Vec3.lengthSq(worldAxis));
		if (!Math.isFinite(axisLength) || axisLength < 1e-6 || !Math.isFinite(lowerTranslation) || !Math.isFinite(upperTranslation)
			|| lowerTranslation > upperTranslation || !Math.isFinite(motorSpeed) || !Math.isFinite(maxMotorForce) || maxMotorForce < 0.0)
			throw 'Invalid slider parameters';
		var axis = Vec3.scale(worldAxis, 1.0 / axisLength);
		if (world.bodyDoF[ia] != DoFMask.Full3D && world.bodyDoF[ib] != DoFMask.Full3D && Math.abs(axis.z) > 1e-5)
			throw 'Planar slider axis must lie in XY';
		if (count >= capacity)
			roomForOneMore();
		var qa = new Quat(world.rotX[ia], world.rotY[ia], world.rotZ[ia], world.rotW[ia]);
		var qb = new Quat(world.rotX[ib], world.rotY[ib], world.rotZ[ib], world.rotW[ib]);
		var localA = Quat.invRotate(qa, new Vec3(worldAnchor.x - world.posX[ia], worldAnchor.y - world.posY[ia], worldAnchor.z - world.posZ[ia]));
		var localB = Quat.invRotate(qb, new Vec3(worldAnchor.x - world.posX[ib], worldAnchor.y - world.posY[ib], worldAnchor.z - world.posZ[ib]));
		if (prismatic == null)
			prismatic = new PrismaticSolver(this, capacity);
		var id = reserve(ia, ib, PRISMATIC);
		anchorAX[id] = localA.x;
		anchorAY[id] = localA.y;
		anchorAZ[id] = localA.z;
		anchorBX[id] = localB.x;
		anchorBY[id] = localB.y;
		anchorBZ[id] = localB.z;
		prismatic.initialize(id, qa, qb, axis, lowerTranslation, upperTranslation, motorSpeed, maxMotorForce);
		return (generation[id] << 20) | id;
	}

	public function createWeld(a:BodyId, b:BodyId, worldAnchor:Vec3, frequency:Single = 30.0, damping:Single = 1.0):JointId {
		var ia = world.bodySlot(a), ib = world.bodySlot(b);
		if (ia == ib)
			throw 'Invalid joint bodies';
		if (world.bodyType[ia] == BodyType.Static && world.bodyType[ib] == BodyType.Static)
			throw 'Joint needs a body that can move';
		if (worldAnchor == null || !Math.isFinite(worldAnchor.x) || !Math.isFinite(worldAnchor.y) || !Math.isFinite(worldAnchor.z))
			throw 'Invalid weld anchor';
		if (!Math.isFinite(frequency) || frequency < 0.0 || !Math.isFinite(damping) || damping < 0.0)
			throw 'Invalid weld parameters';
		if (count >= capacity)
			roomForOneMore();
		var qa = new Quat(world.rotX[ia], world.rotY[ia], world.rotZ[ia], world.rotW[ia]);
		var qb = new Quat(world.rotX[ib], world.rotY[ib], world.rotZ[ib], world.rotW[ib]);
		var localA = Quat.invRotate(qa, new Vec3(worldAnchor.x - world.posX[ia], worldAnchor.y - world.posY[ia], worldAnchor.z - world.posZ[ia]));
		var localB = Quat.invRotate(qb, new Vec3(worldAnchor.x - world.posX[ib], worldAnchor.y - world.posY[ib], worldAnchor.z - world.posZ[ib]));
		if (weld == null)
			weld = new WeldSolver(this, capacity);
		var id = reserve(ia, ib, WELD);
		anchorAX[id] = localA.x;
		anchorAY[id] = localA.y;
		anchorAZ[id] = localA.z;
		anchorBX[id] = localB.x;
		anchorBY[id] = localB.y;
		anchorBZ[id] = localB.z;
		weld.initialize(id, qa, qb, frequency, damping);
		return (generation[id] << 20) | id;
	}

	public function createSpherical(a:BodyId, b:BodyId, worldAnchor:Vec3, worldAxis:Vec3, swingLimit:Single, lowerTwist:Single, upperTwist:Single):JointId {
		var ia = world.bodySlot(a), ib = world.bodySlot(b);
		if (ia == ib)
			throw 'Invalid joint bodies';
		if (world.bodyType[ia] == BodyType.Static && world.bodyType[ib] == BodyType.Static)
			throw 'Joint needs a body that can move';
		if (world.bodyDoF[ia] != DoFMask.Full3D && world.bodyDoF[ib] != DoFMask.Full3D)
			throw 'Spherical joint needs a 3D dynamic body';
		if (worldAnchor == null || !Math.isFinite(worldAnchor.x) || !Math.isFinite(worldAnchor.y) || !Math.isFinite(worldAnchor.z) || worldAxis == null)
			throw 'Invalid spherical anchor or axis';
		var axisLength = Math.sqrt(Vec3.lengthSq(worldAxis));
		if (!Math.isFinite(axisLength) || axisLength < 1e-6 || !Math.isFinite(swingLimit) || swingLimit < 0.0 || swingLimit > Math.PI + 1e-6
			|| !Math.isFinite(lowerTwist) || !Math.isFinite(upperTwist) || lowerTwist < -Math.PI - 1e-6 || upperTwist > Math.PI + 1e-6
			|| lowerTwist > upperTwist)
			throw 'Invalid spherical limits';
		if (count >= capacity)
			roomForOneMore();
		var axis = Vec3.scale(worldAxis, 1.0 / axisLength);
		var qa = new Quat(world.rotX[ia], world.rotY[ia], world.rotZ[ia], world.rotW[ia]);
		var qb = new Quat(world.rotX[ib], world.rotY[ib], world.rotZ[ib], world.rotW[ib]);
		var localA = Quat.invRotate(qa, new Vec3(worldAnchor.x - world.posX[ia], worldAnchor.y - world.posY[ia], worldAnchor.z - world.posZ[ia]));
		var localB = Quat.invRotate(qb, new Vec3(worldAnchor.x - world.posX[ib], worldAnchor.y - world.posY[ib], worldAnchor.z - world.posZ[ib]));
		if (spherical == null)
			spherical = new SphericalSolver(this, capacity);
		var id = reserve(ia, ib, SPHERICAL);
		anchorAX[id] = localA.x;
		anchorAY[id] = localA.y;
		anchorAZ[id] = localA.z;
		anchorBX[id] = localB.x;
		anchorBY[id] = localB.y;
		anchorBZ[id] = localB.z;
		spherical.initialize(id, qa, qb, axis, swingLimit, lowerTwist, upperTwist);
		return (generation[id] << 20) | id;
	}

	/** Returns the slot of a live joint, or -1. */
	public function slotOf(joint:JointId):Int {
		var value:Int = joint;
		var id = value & INDEX_MASK;
		return id < used && activePosition[id] >= 0 && generation[id] == (value >>> 20) ? id : -1;
	}

	public inline function isHinge(slot:Int):Bool
		return kind[slot] == HINGE;

	public inline function isSpherical(slot:Int):Bool
		return kind[slot] == SPHERICAL;

	/** Returns the kind of the joint in `slot`: "distance", "hinge", "prismatic", "weld" or "spherical". */
	public function kindName(slot:Int):String {
		return switch (kind[slot]) {
			case DISTANCE: "distance";
			case HINGE: "hinge";
			case PRISMATIC: "prismatic";
			case WELD: "weld";
			default: "spherical";
		}
	}

	/**
	 * Reflects the frames of a hinge or spherical joint through the plane that
	 * the diagonal reflection (ex, ey, ez) fixes in its bodies' frames. Each of
	 * ex, ey and ez is 1 or -1. When the relative turn of the bodies was
	 * mirrored that way, the joint keeps the meaning of its limits.
	 */
	public function mirrorFrames(joint:JointId, ex:Float, ey:Float, ez:Float):Void {
		var id = slotOf(joint);
		if (id < 0)
			throw 'Invalid joint id';
		if (Math.abs(ex * ey * ez + 1) > 1e-9 || Math.abs(Math.abs(ex) - 1) > 1e-9 || Math.abs(Math.abs(ey) - 1) > 1e-9)
			throw 'Mirroring needs a reflection';
		if (kind[id] == HINGE)
			hinge.mirror(id, ex, ey, ez);
		else if (kind[id] == SPHERICAL)
			spherical.mirror(id, ex, ey, ez);
		else
			throw 'Only hinges and spherical joints mirror';
		world.wakeBodySlot(bodyA[id]);
		world.wakeBodySlot(bodyB[id]);
	}

	public function hingeAngleFor(joint:JointId, qa:Quat, qb:Quat):Float {
		var id = slotOf(joint);
		if (id < 0 || kind[id] != HINGE)
			throw 'Invalid hinge joint id';
		return hinge.angleFor(id, qa, qb);
	}

	public function sphericalOffsetFor(joint:JointId, qa:Quat, qb:Quat, out:Quat):Quat {
		var id = slotOf(joint);
		if (id < 0 || kind[id] != SPHERICAL)
			throw 'Invalid spherical joint id';
		return spherical.offsetFor(id, qa, qb, out);
	}

	public function setSphericalDrive(joint:JointId, offset:Quat, stiffness:Single, damping:Single, maxTorque:Single):Void {
		var value:Int = joint;
		var id = value & INDEX_MASK;
		if (id >= used || activePosition[id] < 0 || generation[id] != (value >>> 20) || kind[id] != SPHERICAL)
			throw 'Invalid spherical joint id';
		if (offset == null)
			throw 'Invalid spherical drive parameters';
		var lengthSq = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z + offset.w * offset.w;
		if (!Math.isFinite(lengthSq) || lengthSq < 1e-12 || !Math.isFinite(stiffness) || stiffness < 0.0 || !Math.isFinite(damping) || damping < 0.0
			|| !Math.isFinite(maxTorque) || maxTorque < 0.0)
			throw 'Invalid spherical drive parameters';
		spherical.setDrive(id, offset, stiffness, damping, maxTorque);
		world.wakeBodySlot(bodyA[id]);
		world.wakeBodySlot(bodyB[id]);
	}

	function reserve(a:Int, b:Int, jointKind:Int):Int {
		if (count >= capacity)
			roomForOneMore();
		var id = freeHead;
		if (id != -1)
			freeHead = nextFree[id];
		else
			id = used++;
		activePosition[id] = count;
		activeIds[count++] = id;
		bodyA[id] = a;
		bodyB[id] = b;
		kind[id] = jointKind;
		collisionDisabled[id] = 0;
		nextExcludedA[id] = nextExcludedB[id] = -1;
		world.wakeBodySlot(a);
		world.wakeBodySlot(b);
		return id;
	}

	public function setCollideConnected(joint:JointId, collide:Bool):Void {
		var value:Int = joint;
		var id = value & INDEX_MASK;
		if (id >= used || activePosition[id] < 0 || generation[id] != (value >>> 20))
			throw 'Invalid joint id';
		var disabled = collide ? 0 : 1;
		if (collisionDisabled[id] == disabled)
			return;
		var a = bodyA[id], b = bodyB[id];
		if (disabled != 0) {
			nextExcludedA[id] = firstExcluded[a];
			firstExcluded[a] = id;
			nextExcludedB[id] = firstExcluded[b];
			firstExcluded[b] = id;
		} else {
			unlinkExcluded(a, id);
			unlinkExcluded(b, id);
		}
		collisionDisabled[id] = disabled;
		world.wakeBodySlot(a);
		world.wakeBodySlot(b);
	}

	public function bodiesMayCollide(a:Int, b:Int):Bool {
		var joint = firstExcluded[a];
		while (joint != -1) {
			if (bodyA[joint] == b || bodyB[joint] == b)
				return false;
			joint = bodyA[joint] == a ? nextExcludedA[joint] : nextExcludedB[joint];
		}
		return true;
	}

	static function root(parent:Int32Buffer, body:Int):Int {
		while (parent[body] != body) {
			parent[body] = parent[parent[body]];
			body = parent[body];
		}
		return body;
	}

	inline function loopRoot(body:Int):Int
		return root(loopParent, body);

	static function join(parent:Int32Buffer, rank:Int32Buffer, marked:Int32Buffer, a:Int, b:Int):Void {
		a = root(parent, a);
		b = root(parent, b);
		if (a == b)
			return;
		if (rank[a] < rank[b]) {
			var t = a;
			a = b;
			b = t;
		}
		parent[b] = a;
		if (marked != null)
			marked[a] |= marked[b];
		if (rank[a] == rank[b])
			rank[a]++;
	}

	function joinLoop(a:Int, b:Int):Void {
		join(loopParent, loopRank, loopMarked, a, b);
	}

	/** Keeps a loop's velocity solve split across contact gaps until its bodies are replaced or change type. */
	@:noCompletion public function findContactLoops():Bool {
		var contacts = world.contacts, n = world.bodyCount;
		if (count == 0)
			return false;
		var found = false;
		for (b in 0...n) {
			loopParent[b] = b;
			loopRank[b] = 0;
			jointParent[b] = b;
			jointRank[b] = 0;
			loopMarked[b] = world.bodyType[b] == BodyType.Dynamic ? splitVelocity[b] : 0;
			if (loopMarked[b] != 0)
				found = true;
		}
		for (p in 0...count) {
			var id = activeIds[p], a = bodyA[id], b = bodyB[id];
			join(jointParent, jointRank, null, a, b);
			if (world.bodyType[a] == BodyType.Dynamic && world.bodyType[b] == BodyType.Dynamic)
				joinLoop(a, b);
		}
		for (c in 0...contacts.count) {
			var ba = contacts.bodyA[c], bb = contacts.bodyB[c];
			if (root(jointParent, ba) != root(jointParent, bb))
				continue;
			// Each fixed support closes loops but does not transmit a correction to its other branches.
			if (world.bodyType[ba] == BodyType.Dynamic) {
				loopMarked[loopRoot(ba)] = 1;
				found = true;
			}
			if (world.bodyType[bb] == BodyType.Dynamic) {
				loopMarked[loopRoot(bb)] = 1;
				found = true;
			}
		}
		if (!found)
			return false;
		// Fixed bodies cannot transmit a correction to another contact island.
		for (c in 0...contacts.count) {
			var a = contacts.bodyA[c], b = contacts.bodyB[c];
			if (world.bodyType[a] == BodyType.Dynamic && world.bodyType[b] == BodyType.Dynamic)
				joinLoop(a, b);
		}
		for (b in 0...n)
			splitVelocity[b] = loopMarked[loopRoot(b)];
		return true;
	}

	@:noCompletion public inline function resetSplitVelocity(body:Int):Void
		splitVelocity[body] = 0;

	/** Discards accumulated position-correction reactions on the selected bodies. */
	@:noCompletion public function clearCorrectionImpulses():Void
		rows.clearCorrectionImpulses(splitVelocity);

	function unlinkExcluded(body:Int, id:Int):Void {
		var previous = -1;
		var current = firstExcluded[body];
		while (current != id) {
			if (current == -1)
				throw 'Invalid joint exclusion';
			previous = current;
			current = bodyA[current] == body ? nextExcludedA[current] : nextExcludedB[current];
		}
		var next = bodyA[id] == body ? nextExcludedA[id] : nextExcludedB[id];
		if (previous == -1)
			firstExcluded[body] = next;
		else if (bodyA[previous] == body)
			nextExcludedA[previous] = next;
		else
			nextExcludedB[previous] = next;
		if (bodyA[id] == body)
			nextExcludedA[id] = -1;
		else
			nextExcludedB[id] = -1;
	}

	public function destroy(id:JointId):Void {
		var value:Int = id;
		var index = value & INDEX_MASK;
		if (index >= used || activePosition[index] < 0 || generation[index] != (value >>> 20))
			throw 'Invalid joint id';
		if (collisionDisabled[index] != 0) {
			unlinkExcluded(bodyA[index], index);
			unlinkExcluded(bodyB[index], index);
			collisionDisabled[index] = 0;
		}
		var position = activePosition[index];
		var last = activeIds[--count];
		activeIds[position] = last;
		activePosition[last] = position;
		activePosition[index] = -1;
		generation[index] = (generation[index] + 1) & 0xFFF;
		nextFree[index] = freeHead;
		freeHead = index;
		world.wakeBodySlot(bodyA[index]);
		world.wakeBodySlot(bodyB[index]);
	}

	public function destroyConnected(body:Int):Void {
		var position = 0;
		while (position < count) {
			var id = activeIds[position];
			if (bodyA[id] == body || bodyB[id] == body)
				destroy((generation[id] << 20) | id);
			else
				position++;
		}
	}

	public function propagateWake():Void {
		var changed = true;
		while (changed) {
			changed = false;
			for (position in 0...count) {
				var id = activeIds[position];
				var a = bodyA[id], b = bodyB[id];
				if (world.bodyType[a] == BodyType.Dynamic
					&& world.islands.isAwake[a] == 0
					&& (world.bodyType[b] == BodyType.Dynamic
						&& world.islands.isAwake[b] != 0
						|| world.bodyType[b] == BodyType.Kinematic
						&& moving(b))) {
					world.wakeBodySlot(a);
					changed = true;
				}
				if (world.bodyType[b] == BodyType.Dynamic
					&& world.islands.isAwake[b] == 0
					&& (world.bodyType[a] == BodyType.Dynamic
						&& world.islands.isAwake[a] != 0
						|| world.bodyType[a] == BodyType.Kinematic
						&& moving(a))) {
					world.wakeBodySlot(b);
					changed = true;
				}
			}
		}
	}

	inline function moving(body:Int):Bool {
		return world.velX[body] != 0.0 || world.velY[body] != 0.0 || world.velZ[body] != 0.0 || world.angVelX[body] != 0.0 || world.angVelY[body] != 0.0
			|| world.angVelZ[body] != 0.0;
	}

	/** Rebuilds every awake joint's constraint rows from the current body poses. */
	public function prepare(h:Single):Void {
		rows.reset(count);
		for (position in 0...count) {
			var id = activeIds[position];
			var a = bodyA[id], b = bodyB[id];
			if (world.bodyType[a] == BodyType.Dynamic
				&& world.islands.isAwake[a] == 0
				|| world.bodyType[b] == BodyType.Dynamic
				&& world.islands.isAwake[b] == 0) {
				rows.skip(id);
				continue;
			}
			var ax = anchorAX[id], ay = anchorAY[id], az = anchorAZ[id];
			var atx = 2.0 * (world.rotY[a] * az - world.rotZ[a] * ay);
			var aty = 2.0 * (world.rotZ[a] * ax - world.rotX[a] * az);
			var atz = 2.0 * (world.rotX[a] * ay - world.rotY[a] * ax);
			var pax = world.posX[a] + ax + world.rotW[a] * atx + world.rotY[a] * atz - world.rotZ[a] * aty;
			var pay = world.posY[a] + ay + world.rotW[a] * aty + world.rotZ[a] * atx - world.rotX[a] * atz;
			var paz = world.posZ[a] + az + world.rotW[a] * atz + world.rotX[a] * aty - world.rotY[a] * atx;
			var bx = anchorBX[id], by = anchorBY[id], bz = anchorBZ[id];
			var btx = 2.0 * (world.rotY[b] * bz - world.rotZ[b] * by);
			var bty = 2.0 * (world.rotZ[b] * bx - world.rotX[b] * bz);
			var btz = 2.0 * (world.rotX[b] * by - world.rotY[b] * bx);
			var pbx = world.posX[b] + bx + world.rotW[b] * btx + world.rotY[b] * btz - world.rotZ[b] * bty;
			var pby = world.posY[b] + by + world.rotW[b] * bty + world.rotZ[b] * btx - world.rotX[b] * btz;
			var pbz = world.posZ[b] + bz + world.rotW[b] * btz + world.rotX[b] * bty - world.rotY[b] * btx;
			rAX[id] = pax - world.worldCenterX[a];
			rAY[id] = pay - world.worldCenterY[a];
			rAZ[id] = paz - world.worldCenterZ[a];
			rBX[id] = pbx - world.worldCenterX[b];
			rBY[id] = pby - world.worldCenterY[b];
			rBZ[id] = pbz - world.worldCenterZ[b];
			var dx = pbx - pax, dy = pby - pay, dz = pbz - paz;
			rows.begin(id, a, b);
			switch (kind[id]) {
				case HINGE:
					hinge.prepare(id, dx, dy, dz, h);
				case PRISMATIC:
					prismatic.prepare(id, dx, dy, dz, h);
				case WELD:
					weld.prepare(id, dx, dy, dz, h);
				case SPHERICAL:
					spherical.prepare(id, dx, dy, dz, h);
				default:
					prepareDistance(id, dx, dy, dz, h);
			}
			rows.end(id);
		}
	}

	function prepareDistance(id:Int, dx:Float, dy:Float, dz:Float, h:Single):Void {
		var distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
		var nx = distance > 1e-6 ? dx / distance : (axisX[id] != 0.0 ? axisX[id] : 1.0);
		var ny = distance > 1e-6 ? dy / distance : axisY[id];
		var nz = distance > 1e-6 ? dz / distance : axisZ[id];
		axisX[id] = nx;
		axisY[id] = ny;
		axisZ[id] = nz;
		var k = rows.linear(nx, ny, nz, rAX[id], rAY[id], rAZ[id], rBX[id], rBY[id], rBZ[id]);
		var error = distance - restLength[id];
		var hz = frequencyHz[id];
		var gamma = 0.0, bias = 0.0;
		if (hz > 0.0 && k > 0.0) {
			var omega = 2.0 * Math.PI * hz;
			var stiffness = omega * omega / k;
			var damping = 2.0 * dampingRatio[id] * omega / k;
			var soft = h * (damping + h * stiffness);
			gamma = soft > 0.0 ? 1.0 / soft : 0.0;
			bias = error * h * stiffness * gamma;
		} else {
			var correction = Math.max(0.0, Math.abs(error) - 0.001);
			bias = Math.max(-10.0, Math.min(10.0, 0.2 * (error < 0.0 ? -correction : correction) / h));
		}
		rows.setEquality(k + gamma > 0.0 ? 1.0 / (k + gamma) : 0.0, bias, gamma, impulse, id);
	}

	public function warmStart():Void {
		rows.warmStart();
	}

	/** Orders an island task's joints by color so workers follow the serial color sequence. */
	public function sortByColor(ids:Int32Buffer, start:Int, count:Int):Void {
		rows.sortByColor(ids, start, count);
	}

	/** Counts the four-joint SIMD batches used in the last substep. It is zero without SIMD. */
	public var packedBatches(get, never):Int;

	inline function get_packedBatches():Int
		return rows.packedBatches;

	/** Switches the rows to their relax targets, as `JointRows.relax` describes. */
	public function relax():Void {
		rows.relax();
	}

	public function solveIteration():Void {
		rows.solveAll();
	}

	/** Forms the substep's joint batches within the islands of `partition`, or across all joints when it is null. Call it before `warmStart`. */
	public function usePartition(partition:Null<hxn.me.physics.island.IslandPartition>):Void {
		rows.usePartition(partition);
	}

	/** Gives each island worker its own batch kernel. */
	public function configureWorkers(count:Int):Void {
		rows.configureWorkers(count);
	}

	/** Solves the joints of island task `task` once, in the color order of the serial solve. `ids` from `start` holds them sorted by color. */
	public function solveTask(task:Int, ids:hxn.Int32Buffer, start:Int, count:Int, worker:Int):Void {
		rows.solveTask(task, ids, start, count, worker);
	}

	/** Solves one joint's rows. Island workers call this for the joints of their task. */
	function solveJoint(id:Int):Void {
		rows.solveJoint(id);
	}

	/** Returns the iterated impulses to each joint for the next substep's warm start. */
	public function storeImpulses():Void {
		rows.storeImpulses();
	}

	/** Visits joints, their warm starts and drives, for `WorldSnapshot`. */
	@:noCompletion public function visitState(s:hxn.me.physics.core.WorldSnapshot, bodies:Int):Void {
		var live = used;
		count = s.int(count);
		used = s.int(used);
		freeHead = s.int(freeHead);
		var n = s.span(live, used);
		s.ints(activeIds, n);
		s.ints(bodyA, n);
		s.ints(bodyB, n);
		s.ints(kind, n);
		s.ints(activePosition, n);
		s.ints(generation, n);
		s.ints(nextFree, n);
		s.ints(collisionDisabled, n);
		s.ints(nextExcludedA, n);
		s.ints(nextExcludedB, n);
		s.floats(restLength, n);
		s.floats(frequencyHz, n);
		s.floats(dampingRatio, n);
		s.floats(anchorAX, n);
		s.floats(anchorAY, n);
		s.floats(anchorAZ, n);
		s.floats(anchorBX, n);
		s.floats(anchorBY, n);
		s.floats(anchorBZ, n);
		s.floats(axisX, n);
		s.floats(axisY, n);
		s.floats(axisZ, n);
		s.floats(impulse, n);
		s.ints(firstExcluded, bodies);
		s.ints(splitVelocity, bodies);
		// Each kind's solver exists once a joint of that kind is made. Worlds built by the same calls
		// have the same solvers.
		if (s.bool(hinge != null)) {
			if (hinge == null)
				throw 'The world has no hinge joints to restore';
			hinge.visitState(s, n);
		}
		if (s.bool(prismatic != null)) {
			if (prismatic == null)
				throw 'The world has no prismatic joints to restore';
			prismatic.visitState(s, n);
		}
		if (s.bool(weld != null)) {
			if (weld == null)
				throw 'The world has no weld joints to restore';
			weld.visitState(s, n);
		}
		if (s.bool(spherical != null)) {
			if (spherical == null)
				throw 'The world has no spherical joints to restore';
			spherical.visitState(s, n);
		}
	}
}
