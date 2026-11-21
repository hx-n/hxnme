package hxn.me.physics.core;

import hxn.me.math.Grow;
import hxn.Float32Buffer;
import hxn.Int32Buffer;
import hxn.me.math.Vec3;
import hxn.me.math.Quat;
import hxn.me.math.Mat3;
import hxn.me.math.Simd.SimdBatch;
import hxn.me.physics.geom.VertexPool;
import hxn.me.physics.geom.ShapeDef;
import hxn.me.physics.geom.MassProperties;
import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.physics.geom.ConvexHull;
import hxn.me.physics.core.Handles;
import hxn.me.physics.core.WorldQuery.QueryHit;
import hxn.me.physics.collision.BroadPhase;
import hxn.me.physics.collision.TimeOfImpact;
import hxn.me.physics.collision.NarrowPhase;
import hxn.me.physics.collision.NarrowPhase.ContactManifoldPool;
import hxn.me.physics.collision.PairScratch;
import hxn.me.physics.collision.NarrowPhase.NarrowPhaseWorkspace;
import hxn.me.physics.collision.ManifoldClipper;
import hxn.me.physics.collision.ManifoldClipper.ClipTopology;
import hxn.me.physics.collision.ManifoldClipper.ClipWorkspace;
import hxn.me.physics.solver.SoftStepSolver;
import hxn.me.physics.island.IslandManager;
import hxn.me.physics.island.ParallelIslandSolver;
import hxn.me.physics.joints.JointPool;

@:allow(hxn.me.physics.core.WorldQuery)
@:allow(hxn.me.physics.water.Water)
@:allow(hxn.me.physics.core.WorldValidation)
@:allow(hxn.me.physics.collision.TimeOfImpact)
@:allow(hxn.me.physics.solver.SoftStepSolver)
@:allow(hxn.me.physics.island.ParallelIslandSolver)
class World {
	static inline var INDEX_MASK:Int = (1 << 20) - 1;

	public var verts:VertexPool;
	public var broadPhase:BroadPhase;
	public var contacts:ContactManifoldPool;
	public var solver:SoftStepSolver;
	public var islands:IslandManager;

	var parallelIslands:ParallelIslandSolver;

	public var joints:JointPool;
	public var query(default, null):WorldQuery;
	public var toi(default, null):TimeOfImpact;
	public var isBullet:Int32Buffer;

	// De-Interleaved 32-bit Single SoA Buffers (4-wide SIMD aligned)
	// SoA slots stay stable; count is the high-water mark and activeBodyCount is the live count.
	public var bodyCount:Int = 0;
	public var activeBodyCount(default, null):Int = 0;
	public var bodyCapacity:Int;
	public var shapeCapacity:Int;

	var bodyGeneration:Int32Buffer;
	var bodyActive:Int32Buffer;
	var activeBodyIds:Int32Buffer;
	var bodyActivePosition:Int32Buffer;
	var bodyNextFree:Int32Buffer;
	var bodyFreeHead:Int = -1;
	var kinematicPending:Int32Buffer;
	// Pose at the start of the step a kinematic target is consumed in.
	var kinematicStartX:Float32Buffer;
	var kinematicStartY:Float32Buffer;
	var kinematicStartZ:Float32Buffer;
	var kinematicStartQx:Float32Buffer;
	var kinematicStartQy:Float32Buffer;
	var kinematicStartQz:Float32Buffer;
	var kinematicStartQw:Float32Buffer;
	// Motion a kinematic body took through its target in the step it last moved, kept for a switch to dynamic.
	var kinematicVelX:Float32Buffer;
	var kinematicVelY:Float32Buffer;
	var kinematicVelZ:Float32Buffer;
	var kinematicAngX:Float32Buffer;
	var kinematicAngY:Float32Buffer;
	var kinematicAngZ:Float32Buffer;
	var kinematicMovedStep:Int32Buffer;
	var stepCount = 0;

	/** Steps taken since the world was created. */
	public var steps(get, never):Int;

	inline function get_steps():Int
		return stepCount;

	/** Kinematic target poses by body slot. Write them, then call `commitKinematicTarget`. */
	public var targetX(default, null):Float32Buffer;

	public var targetY(default, null):Float32Buffer;
	public var targetZ(default, null):Float32Buffer;
	public var targetQx(default, null):Float32Buffer;
	public var targetQy(default, null):Float32Buffer;
	public var targetQz(default, null):Float32Buffer;
	public var targetQw(default, null):Float32Buffer;

	var kinematicElapsed:Single = 0.0;
	var kinematicStepDt:Single = 0.0;

	public var bodyType:Int32Buffer;
	public var bodyDoF:Int32Buffer;

	// Field declarations:
	public var posX:Float32Buffer;
	public var posY:Float32Buffer;
	public var posZ:Float32Buffer;

	public var rotX:Float32Buffer;
	public var rotY:Float32Buffer;
	public var rotZ:Float32Buffer;
	public var rotW:Float32Buffer;

	/**
	 * Each body's pose before the most recent step, kept while
	 * `keepPreviousPoses` is on, for drawing between steps. A teleport sets it
	 * to the new pose, so a cut is never drawn halfway.
	 */
	public var prevPosX(default, null):Float32Buffer;

	public var prevPosY(default, null):Float32Buffer;
	public var prevPosZ(default, null):Float32Buffer;
	public var prevRotX(default, null):Float32Buffer;
	public var prevRotY(default, null):Float32Buffer;
	public var prevRotZ(default, null):Float32Buffer;
	public var prevRotW(default, null):Float32Buffer;

	/** Record each body's pose at the start of every step into `prevPosX`..`prevRotW`. Costs one copy per moving body per step. */
	public var keepPreviousPoses = false;

	public var velX:Float32Buffer;
	public var velY:Float32Buffer;
	public var velZ:Float32Buffer;

	public var angVelX:Float32Buffer;
	public var angVelY:Float32Buffer;
	public var angVelZ:Float32Buffer;

	public var invMassX:Float32Buffer;
	public var invMassY:Float32Buffer;
	public var invMassZ:Float32Buffer;

	public var invInertiaX:Float32Buffer;
	public var invInertiaY:Float32Buffer;
	public var invInertiaZ:Float32Buffer;
	public var invInertiaXY:Float32Buffer;
	public var invInertiaXZ:Float32Buffer;
	public var invInertiaYZ:Float32Buffer;
	public var localCenterX:Float32Buffer;
	public var localCenterY:Float32Buffer;
	public var localCenterZ:Float32Buffer;
	public var worldCenterX:Float32Buffer;
	public var worldCenterY:Float32Buffer;
	public var worldCenterZ:Float32Buffer;
	public var invIxx:Float32Buffer;
	public var invIyy:Float32Buffer;
	public var invIzz:Float32Buffer;
	public var invIxy:Float32Buffer;
	public var invIxz:Float32Buffer;
	public var invIyz:Float32Buffer;

	public var firstShape:Int32Buffer;

	// Shape SoA Buffers
	// Shape slots follow the same high-water and active-count convention.
	public var shapeCount:Int = 0;
	public var activeShapeCount(default, null):Int = 0;

	var shapeGeneration:Int32Buffer;
	var shapeActive:Int32Buffer;
	var activeShapeIds:Int32Buffer;
	var shapeActivePosition:Int32Buffer;
	var shapeNextFree:Int32Buffer;
	var shapeFreeHead:Int = -1;

	public var shapeBody:Int32Buffer;

	var shapeVertexOwned:Int32Buffer;

	public var shapeSensor(default, null):Int32Buffer;

	var shapeUserData:Int32Buffer;
	// Set once a reshaped shape has its own vertex block instead of its descriptor's.
	var shapeVertexPrivate:Int32Buffer;

	public var shapeNext:Int32Buffer;
	public var shapeProxy:Int32Buffer;
	public var shapeKind:Int32Buffer;
	public var shapeVertOffset:Int32Buffer;
	public var shapeVertCount:Int32Buffer;
	public var shapeDepth:Float32Buffer;
	public var shapeRadius:Float32Buffer;
	public var shapeLocalZ:Float32Buffer;
	public var shapeDensity:Float32Buffer;
	public var shapeCategoryBits:Int32Buffer;
	public var shapeMaskBits:Int32Buffer;
	public var shapeGroupIndex:Int32Buffer;
	public var shapeFriction:Float32Buffer;
	public var shapeRestitution:Float32Buffer;
	public var shapeTopology:Array<ClipTopology>;
	public var clipWorkspace:ClipWorkspace;
	public var narrowWorkspace(default, null):NarrowPhaseWorkspace;

	// Pair inputs and workspaces for the calling thread.
	var pairScratch:PairScratch = new PairScratch();

	/** Sensor overlaps, contact begins and ends, and impacts from the last step. */
	public var events(default, null):WorldEvents = new WorldEvents();

	// Awake flags as the broadphase saw them when it last found pairs.
	var pairAwake:Int32Buffer;
	var overlapScratch:Int32Buffer;
	// Lane constants for SIMD body integration, owned per world so worlds can step on separate threads.
	var integrationConstants:hl.Bytes = new hl.Bytes(80);
	var correctionVelocities:Float32Buffer;

	public var gravity:Vec3 = new Vec3(0.0, -9.81, 0.0);

	/**
	 * Joint sweeps per solver iteration. A load passes one joint per sweep, so a
	 * long jointed chain carrying weight, such as a standing character, needs
	 * more than one to settle. One is cheaper and suits loose chains; any
	 * positive value is safe.
	 */
	public var jointSweeps:Int = 2;

	/** Counts the calls that change collider geometry: attaching, destroying and reshaping shapes. Snapshots taken before one cannot be restored after it. */
	public var structureVersion(default, null):Int = 0;

	/**
	 * Starts a pool of Ash workers that solves large islands. A positive
	 * `minPairsPerWorker` also splits a segment's collision tests across the
	 * workers once there are at least that many candidate pairs per worker;
	 * zero keeps collision on the calling thread. Needs Ash 0.1.2 or later:
	 * earlier worker pools can hang when woken this often.
	 */
	public function enableParallelIslands(workers:Int = 4, minConstraintsPerIsland:Int = 128, minPairsPerWorker:Int = 64):Void {
		if (workers < 2 || minConstraintsPerIsland < 1 || minPairsPerWorker < 0)
			throw 'Invalid island worker configuration';
		disableParallelIslands();
		parallelIslands = new ParallelIslandSolver(this, workers, minConstraintsPerIsland, minPairsPerWorker);
	}

	public function disableParallelIslands():Void {
		if (parallelIslands == null)
			return;
		parallelIslands.shutdown();
		parallelIslands = null;
	}

	public function new(maxBodies:Int = 4096, maxShapes:Int = 8192, maxJoints:Int = 4096) {
		if (maxBodies < 0 || maxBodies > (1 << 20) || maxShapes < 0 || maxShapes > (1 << 20))
			throw 'Invalid world capacity';
		var bCap = (maxBodies + 3) & ~3;
		var sCap = (maxShapes + 3) & ~3;
		bodyCapacity = bCap;
		shapeCapacity = sCap;

		verts = new VertexPool(sCap * 8);
		// The limits on overlapping pairs and on contacts grow with the world, and their storage only as far as a step needs, so a crowded
		// scene is not silently missing collisions. The pair count a world can have is computed in floating point: sCap * sCap overflows an Int.
		var pairLimit = pairLimitFor(sCap);
		broadPhase = new BroadPhase(sCap * 2, pairLimit);
		contacts = new ContactManifoldPool(contactLimitFor(sCap, pairLimit));
		solver = new SoftStepSolver(this, contacts.capacity);
		islands = new IslandManager(bCap);
		joints = new JointPool(this, maxJoints);
		query = new WorldQuery(this);
		toi = new TimeOfImpact(this);

		bodyType = new Int32Buffer(bCap);
		kinematicPending = new Int32Buffer(bCap);
		kinematicStartX = new Float32Buffer(bCap);
		kinematicStartY = new Float32Buffer(bCap);
		kinematicStartZ = new Float32Buffer(bCap);
		kinematicStartQx = new Float32Buffer(bCap);
		kinematicStartQy = new Float32Buffer(bCap);
		kinematicStartQz = new Float32Buffer(bCap);
		kinematicStartQw = new Float32Buffer(bCap);
		kinematicVelX = new Float32Buffer(bCap);
		kinematicVelY = new Float32Buffer(bCap);
		kinematicVelZ = new Float32Buffer(bCap);
		kinematicAngX = new Float32Buffer(bCap);
		kinematicAngY = new Float32Buffer(bCap);
		kinematicAngZ = new Float32Buffer(bCap);
		kinematicMovedStep = new Int32Buffer(bCap);
		targetX = new Float32Buffer(bCap);
		targetY = new Float32Buffer(bCap);
		targetZ = new Float32Buffer(bCap);
		targetQx = new Float32Buffer(bCap);
		targetQy = new Float32Buffer(bCap);
		targetQz = new Float32Buffer(bCap);
		targetQw = new Float32Buffer(bCap);
		isBullet = new Int32Buffer(bCap);
		bodyDoF = new Int32Buffer(bCap);
		pairAwake = new Int32Buffer(bCap);
		bodyGeneration = new Int32Buffer(bCap);
		bodyActive = new Int32Buffer(bCap);
		activeBodyIds = new Int32Buffer(bCap);
		bodyActivePosition = new Int32Buffer(bCap);
		bodyNextFree = new Int32Buffer(bCap);
		posX = new Float32Buffer(bCap);
		posY = new Float32Buffer(bCap);
		posZ = new Float32Buffer(bCap);
		rotX = new Float32Buffer(bCap);
		rotY = new Float32Buffer(bCap);
		rotZ = new Float32Buffer(bCap);
		rotW = new Float32Buffer(bCap);
		prevPosX = new Float32Buffer(bCap);
		prevPosY = new Float32Buffer(bCap);
		prevPosZ = new Float32Buffer(bCap);
		prevRotX = new Float32Buffer(bCap);
		prevRotY = new Float32Buffer(bCap);
		prevRotZ = new Float32Buffer(bCap);
		prevRotW = new Float32Buffer(bCap);
		velX = new Float32Buffer(bCap);
		velY = new Float32Buffer(bCap);
		velZ = new Float32Buffer(bCap);
		angVelX = new Float32Buffer(bCap);
		angVelY = new Float32Buffer(bCap);
		angVelZ = new Float32Buffer(bCap);
		invMassX = new Float32Buffer(bCap);
		invMassY = new Float32Buffer(bCap);
		invMassZ = new Float32Buffer(bCap);
		invInertiaX = new Float32Buffer(bCap);
		invInertiaY = new Float32Buffer(bCap);
		invInertiaZ = new Float32Buffer(bCap);
		invInertiaXY = new Float32Buffer(bCap);
		invInertiaXZ = new Float32Buffer(bCap);
		invInertiaYZ = new Float32Buffer(bCap);
		localCenterX = new Float32Buffer(bCap);
		localCenterY = new Float32Buffer(bCap);
		localCenterZ = new Float32Buffer(bCap);
		worldCenterX = new Float32Buffer(bCap);
		worldCenterY = new Float32Buffer(bCap);
		worldCenterZ = new Float32Buffer(bCap);
		invIxx = new Float32Buffer(bCap);
		invIyy = new Float32Buffer(bCap);
		invIzz = new Float32Buffer(bCap);
		invIxy = new Float32Buffer(bCap);
		invIxz = new Float32Buffer(bCap);
		invIyz = new Float32Buffer(bCap);
		firstShape = new Int32Buffer(bCap);

		shapeBody = new Int32Buffer(sCap);
		shapeVertexOwned = new Int32Buffer(sCap);
		shapeSensor = new Int32Buffer(sCap);
		shapeUserData = new Int32Buffer(sCap);
		overlapScratch = new Int32Buffer(sCap);
		shapeVertexPrivate = new Int32Buffer(sCap);
		shapeGeneration = new Int32Buffer(sCap);
		shapeActive = new Int32Buffer(sCap);
		activeShapeIds = new Int32Buffer(sCap);
		shapeActivePosition = new Int32Buffer(sCap);
		shapeNextFree = new Int32Buffer(sCap);
		shapeNext = new Int32Buffer(sCap);
		shapeProxy = new Int32Buffer(sCap);
		shapeKind = new Int32Buffer(sCap);
		shapeVertOffset = new Int32Buffer(sCap);
		shapeVertCount = new Int32Buffer(sCap);
		shapeDepth = new Float32Buffer(sCap);
		shapeRadius = new Float32Buffer(sCap);
		shapeLocalZ = new Float32Buffer(sCap);
		shapeDensity = new Float32Buffer(sCap);
		shapeCategoryBits = new Int32Buffer(sCap);
		shapeMaskBits = new Int32Buffer(sCap);
		shapeGroupIndex = new Int32Buffer(sCap);
		shapeFriction = new Float32Buffer(sCap);
		shapeRestitution = new Float32Buffer(sCap);
		shapeTopology = [];
		clipWorkspace = new ClipWorkspace();
		narrowWorkspace = new NarrowPhaseWorkspace();
		for (i in 0...sCap)
			shapeProxy[i] = BroadPhase.NULL_NODE;
	}

	/**
	 * Makes room for at least this many bodies, shapes and joints, keeping everything: handles stay valid, and a world grown mid-run
	 * goes on exactly as one made this large would. Creating a body, shape or joint past the room calls this with twice as much, up to
	 * the 1,048,576 a handle's index can hold. Call it between steps; it replaces the world's buffers, so none should be held across it.
	 */
	public function reserve(bodies:Int, shapes:Int, jointRoom:Int = 0):Void {
		var limit = 1 << 20;
		if (bodies < 0 || shapes < 0 || jointRoom < 0 || bodies > limit || shapes > limit || jointRoom > limit)
			throw 'Invalid world capacity';
		var bCap = Std.int(Math.max(bodyCapacity, (bodies + 3) & ~3)), sCap = Std.int(Math.max(shapeCapacity, (shapes + 3) & ~3));
		var jCap = Std.int(Math.max(joints.capacity, jointRoom));
		if (bCap == bodyCapacity && sCap == shapeCapacity && jCap == joints.capacity)
			return;
		var oldBodies = bodyCapacity, oldShapes = shapeCapacity;
		if (bCap > oldBodies) {
			bodyType = Grow.ints(bodyType, oldBodies, bCap);
			kinematicPending = Grow.ints(kinematicPending, oldBodies, bCap);
			kinematicStartX = Grow.floats(kinematicStartX, oldBodies, bCap);
			kinematicStartY = Grow.floats(kinematicStartY, oldBodies, bCap);
			kinematicStartZ = Grow.floats(kinematicStartZ, oldBodies, bCap);
			kinematicStartQx = Grow.floats(kinematicStartQx, oldBodies, bCap);
			kinematicStartQy = Grow.floats(kinematicStartQy, oldBodies, bCap);
			kinematicStartQz = Grow.floats(kinematicStartQz, oldBodies, bCap);
			kinematicStartQw = Grow.floats(kinematicStartQw, oldBodies, bCap);
			kinematicVelX = Grow.floats(kinematicVelX, oldBodies, bCap);
			kinematicVelY = Grow.floats(kinematicVelY, oldBodies, bCap);
			kinematicVelZ = Grow.floats(kinematicVelZ, oldBodies, bCap);
			kinematicAngX = Grow.floats(kinematicAngX, oldBodies, bCap);
			kinematicAngY = Grow.floats(kinematicAngY, oldBodies, bCap);
			kinematicAngZ = Grow.floats(kinematicAngZ, oldBodies, bCap);
			kinematicMovedStep = Grow.ints(kinematicMovedStep, oldBodies, bCap);
			targetX = Grow.floats(targetX, oldBodies, bCap);
			targetY = Grow.floats(targetY, oldBodies, bCap);
			targetZ = Grow.floats(targetZ, oldBodies, bCap);
			targetQx = Grow.floats(targetQx, oldBodies, bCap);
			targetQy = Grow.floats(targetQy, oldBodies, bCap);
			targetQz = Grow.floats(targetQz, oldBodies, bCap);
			targetQw = Grow.floats(targetQw, oldBodies, bCap);
			isBullet = Grow.ints(isBullet, oldBodies, bCap);
			bodyDoF = Grow.ints(bodyDoF, oldBodies, bCap);
			pairAwake = Grow.ints(pairAwake, oldBodies, bCap);
			bodyGeneration = Grow.ints(bodyGeneration, oldBodies, bCap);
			bodyActive = Grow.ints(bodyActive, oldBodies, bCap);
			activeBodyIds = Grow.ints(activeBodyIds, oldBodies, bCap);
			bodyActivePosition = Grow.ints(bodyActivePosition, oldBodies, bCap);
			bodyNextFree = Grow.ints(bodyNextFree, oldBodies, bCap);
			posX = Grow.floats(posX, oldBodies, bCap);
			posY = Grow.floats(posY, oldBodies, bCap);
			posZ = Grow.floats(posZ, oldBodies, bCap);
			rotX = Grow.floats(rotX, oldBodies, bCap);
			rotY = Grow.floats(rotY, oldBodies, bCap);
			rotZ = Grow.floats(rotZ, oldBodies, bCap);
			rotW = Grow.floats(rotW, oldBodies, bCap);
			prevPosX = Grow.floats(prevPosX, oldBodies, bCap);
			prevPosY = Grow.floats(prevPosY, oldBodies, bCap);
			prevPosZ = Grow.floats(prevPosZ, oldBodies, bCap);
			prevRotX = Grow.floats(prevRotX, oldBodies, bCap);
			prevRotY = Grow.floats(prevRotY, oldBodies, bCap);
			prevRotZ = Grow.floats(prevRotZ, oldBodies, bCap);
			prevRotW = Grow.floats(prevRotW, oldBodies, bCap);
			velX = Grow.floats(velX, oldBodies, bCap);
			velY = Grow.floats(velY, oldBodies, bCap);
			velZ = Grow.floats(velZ, oldBodies, bCap);
			angVelX = Grow.floats(angVelX, oldBodies, bCap);
			angVelY = Grow.floats(angVelY, oldBodies, bCap);
			angVelZ = Grow.floats(angVelZ, oldBodies, bCap);
			invMassX = Grow.floats(invMassX, oldBodies, bCap);
			invMassY = Grow.floats(invMassY, oldBodies, bCap);
			invMassZ = Grow.floats(invMassZ, oldBodies, bCap);
			invInertiaX = Grow.floats(invInertiaX, oldBodies, bCap);
			invInertiaY = Grow.floats(invInertiaY, oldBodies, bCap);
			invInertiaZ = Grow.floats(invInertiaZ, oldBodies, bCap);
			invInertiaXY = Grow.floats(invInertiaXY, oldBodies, bCap);
			invInertiaXZ = Grow.floats(invInertiaXZ, oldBodies, bCap);
			invInertiaYZ = Grow.floats(invInertiaYZ, oldBodies, bCap);
			localCenterX = Grow.floats(localCenterX, oldBodies, bCap);
			localCenterY = Grow.floats(localCenterY, oldBodies, bCap);
			localCenterZ = Grow.floats(localCenterZ, oldBodies, bCap);
			worldCenterX = Grow.floats(worldCenterX, oldBodies, bCap);
			worldCenterY = Grow.floats(worldCenterY, oldBodies, bCap);
			worldCenterZ = Grow.floats(worldCenterZ, oldBodies, bCap);
			invIxx = Grow.floats(invIxx, oldBodies, bCap);
			invIyy = Grow.floats(invIyy, oldBodies, bCap);
			invIzz = Grow.floats(invIzz, oldBodies, bCap);
			invIxy = Grow.floats(invIxy, oldBodies, bCap);
			invIxz = Grow.floats(invIxz, oldBodies, bCap);
			invIyz = Grow.floats(invIyz, oldBodies, bCap);
			firstShape = Grow.ints(firstShape, oldBodies, bCap);
			bodyCapacity = bCap;
			islands.grow(oldBodies, bCap);
			solver.graph.growBodies(bCap);
		}
		if (sCap > oldShapes) {
			shapeBody = Grow.ints(shapeBody, oldShapes, sCap);
			shapeVertexOwned = Grow.ints(shapeVertexOwned, oldShapes, sCap);
			shapeSensor = Grow.ints(shapeSensor, oldShapes, sCap);
			shapeUserData = Grow.ints(shapeUserData, oldShapes, sCap);
			overlapScratch = Grow.ints(overlapScratch, oldShapes, sCap);
			shapeVertexPrivate = Grow.ints(shapeVertexPrivate, oldShapes, sCap);
			shapeGeneration = Grow.ints(shapeGeneration, oldShapes, sCap);
			shapeActive = Grow.ints(shapeActive, oldShapes, sCap);
			activeShapeIds = Grow.ints(activeShapeIds, oldShapes, sCap);
			shapeActivePosition = Grow.ints(shapeActivePosition, oldShapes, sCap);
			shapeNextFree = Grow.ints(shapeNextFree, oldShapes, sCap);
			shapeNext = Grow.ints(shapeNext, oldShapes, sCap);
			shapeProxy = Grow.ints(shapeProxy, oldShapes, sCap);
			shapeKind = Grow.ints(shapeKind, oldShapes, sCap);
			shapeVertOffset = Grow.ints(shapeVertOffset, oldShapes, sCap);
			shapeVertCount = Grow.ints(shapeVertCount, oldShapes, sCap);
			shapeDepth = Grow.singles(shapeDepth, oldShapes, sCap);
			shapeRadius = Grow.singles(shapeRadius, oldShapes, sCap);
			shapeLocalZ = Grow.singles(shapeLocalZ, oldShapes, sCap);
			shapeDensity = Grow.singles(shapeDensity, oldShapes, sCap);
			shapeCategoryBits = Grow.ints(shapeCategoryBits, oldShapes, sCap);
			shapeMaskBits = Grow.ints(shapeMaskBits, oldShapes, sCap);
			shapeGroupIndex = Grow.ints(shapeGroupIndex, oldShapes, sCap);
			shapeFriction = Grow.floats(shapeFriction, oldShapes, sCap);
			shapeRestitution = Grow.floats(shapeRestitution, oldShapes, sCap);
			for (i in oldShapes...sCap)
				shapeProxy[i] = BroadPhase.NULL_NODE;
			shapeCapacity = sCap;
			verts.grow(sCap * 8);
			broadPhase.growNodes(sCap * 2);
			broadPhase.maxPairs = Std.int(Math.max(broadPhase.maxPairs, pairLimitFor(sCap)));
			contacts.maxContacts = Std.int(Math.max(contacts.maxContacts, contactLimitFor(sCap, broadPhase.maxPairs)));
		}
		joints.grow(bodyCapacity, jCap);
		query.releaseScratch();
		toi.resize();
		if (parallelIslands != null)
			parallelIslands.resize();
		correctionVelocities = null;
		capacityRevision++;
	}

	/** Gives the room a snapshot did not cover, in a world larger than the one it was taken from, the values a new world has. */
	@:allow(hxn.me.physics.core.WorldSnapshot)
	function afterRestore(savedBodies:Int, savedShapes:Int, savedJoints:Int):Void {
		if (shapeCapacity > savedShapes) {
			for (i in savedShapes...shapeCapacity)
				shapeProxy[i] = BroadPhase.NULL_NODE;
			broadPhase.linkFree(savedShapes * 2);
		}
		if (bodyCapacity > savedBodies)
			islands.clearTail(savedBodies);
		joints.clearTails(savedBodies, savedJoints);
	}

	/** Bumped each time `reserve` replaces the world's buffers, for code that sized something by `bodyCapacity` or `shapeCapacity`. */
	public var capacityRevision(default, null) = 0;

	static function pairLimitFor(sCap:Int):Int
		return Std.int(Math.max(16384, Math.min(1 << 24, sCap * 16.0)));

	static function contactLimitFor(sCap:Int, pairLimit:Int):Int {
		var possible:Float = sCap * (sCap - 1.0) / 2;
		return Std.int(Math.min(1 << 24, Math.min(pairLimit, possible) * 4));
	}

	// Validate a public handle before using its slot to index SoA buffers.
	public inline function bodySlot(body:BodyId):Int {
		var value:Int = body;
		var slot = value & INDEX_MASK;
		if (slot >= bodyCount || bodyActive[slot] == 0 || bodyGeneration[slot] != (value >>> 20))
			throw 'Invalid body id';
		return slot;
	}

	public inline function shapeSlot(shape:ShapeId):Int {
		var value:Int = shape;
		var slot = value & INDEX_MASK;
		if (slot >= shapeCount || shapeActive[slot] == 0 || shapeGeneration[slot] != (value >>> 20))
			throw 'Invalid shape id';
		return slot;
	}

	public inline function bodyHandleAt(position:Int):BodyId {
		if (position < 0 || position >= activeBodyCount)
			throw 'Invalid body position';
		var slot = activeBodyIds[position];
		return (bodyGeneration[slot] << 20) | slot;
	}

	public inline function shapeHandleAt(position:Int):ShapeId {
		if (position < 0 || position >= activeShapeCount)
			throw 'Invalid shape position';
		var slot = activeShapeIds[position];
		return (shapeGeneration[slot] << 20) | slot;
	}

	public function createBody(type:BodyType, x:Single, y:Single, z:Single = 0.0):BodyId {
		if (bodyFreeHead == -1 && bodyCount >= bodyCapacity) {
			if (bodyCapacity >= (1 << 20))
				throw 'World body capacity exceeded';
			reserve(Std.int(Math.min(1 << 20, Math.max(8, bodyCapacity * 2.0))), 0);
		}
		var id = bodyFreeHead;
		if (id != -1)
			bodyFreeHead = bodyNextFree[id];
		else
			id = bodyCount++;
		bodyActive[id] = 1;
		bodyActivePosition[id] = activeBodyCount;
		activeBodyIds[activeBodyCount++] = id;
		bodyType[id] = type;
		joints.resetSplitVelocity(id);
		kinematicPending[id] = 0;
		kinematicMovedStep[id] = 0;
		isBullet[id] = 0;
		islands.addBody(id, type);
		bodyDoF[id] = DoFMask.Locked;
		firstShape[id] = -1;

		posX[id] = x;
		posY[id] = y;
		posZ[id] = z;
		rotX[id] = 0.0;
		rotY[id] = 0.0;
		rotZ[id] = 0.0;
		rotW[id] = 1.0;
		velX[id] = velY[id] = velZ[id] = 0.0;
		angVelX[id] = angVelY[id] = angVelZ[id] = 0.0;
		invMassX[id] = invMassY[id] = invMassZ[id] = 0.0;
		invInertiaX[id] = invInertiaY[id] = invInertiaZ[id] = 0.0;
		invInertiaXY[id] = invInertiaXZ[id] = invInertiaYZ[id] = 0.0;
		invIxx[id] = invIyy[id] = invIzz[id] = 0.0;
		invIxy[id] = invIxz[id] = invIyz[id] = 0.0;
		localCenterX[id] = localCenterY[id] = localCenterZ[id] = 0.0;
		worldCenterX[id] = x;
		worldCenterY[id] = y;
		worldCenterZ[id] = z;
		copyPreviousPose(id);
		return (bodyGeneration[id] << 20) | id;
	}

	public function attachShape(body:BodyId, def:ShapeDef, categoryBits:Int = 1, maskBits:Int = -1, groupIndex:Int = 0, friction:Single = 0.5,
			restitution:Single = 0.0):ShapeId {
		if (groupIndex < -32768 || groupIndex > 32767)
			throw 'groupIndex must fit in signed 16 bits';
		if (!Math.isFinite(friction) || friction < 0.0 || !Math.isFinite(restitution) || restitution < 0.0 || restitution > 1.0)
			throw 'Invalid friction or restitution';
		if (def == null || !Math.isFinite(def.radius) || !Math.isFinite(def.depth) || !Math.isFinite(def.localZ) || !Math.isFinite(def.density)
			|| def.radius < 0.0 || def.depth < 0.0 || def.density < 0.0)
			throw 'Invalid shape dimensions or density';
		var bId = bodySlot(body);
		if (shapeFreeHead == -1 && shapeCount >= shapeCapacity) {
			if (shapeCapacity >= (1 << 20))
				throw 'World shape capacity exceeded';
			reserve(0, Std.int(Math.min(1 << 20, Math.max(8, shapeCapacity * 2.0))));
		}
		var kindValue:Int = def.kind;
		if (kindValue < 0 || kindValue > 3)
			throw 'Invalid shape kind';
		def.ensureVertices(verts);
		var required = def.kind == ShapeKind.Point ? 0 : (def.kind == ShapeKind.Segment ? 2 : (def.kind == ShapeKind.Polygon ? 3 : 4));
		if (def.vertCount < required
			|| (kindValue < 2 && def.vertCount != required)
			|| def.vertOffset < 0
			|| def.vertOffset + def.vertCount > verts.count)
			throw 'Invalid shape vertices';
		if (def.kind == ShapeKind.Polygon
			&& MassProperties.polygon(verts, def.vertOffset, def.vertCount, def.depth, def.localZ, 1.0).mass <= 0.0)
			throw 'Polygon has zero area';
		if (def.kind == ShapeKind.Hull)
			MassProperties.hull(verts, def.vertOffset, def.vertCount, def.localZ, 1.0);
		var sId = shapeFreeHead;
		if (sId != -1)
			shapeFreeHead = shapeNextFree[sId];
		else
			sId = shapeCount++;
		shapeActive[sId] = 1;
		shapeActivePosition[sId] = activeShapeCount;
		activeShapeIds[activeShapeCount++] = sId;

		shapeBody[sId] = bId;
		shapeVertexOwned[sId] = def.vertCount > 0 && verts.hasLiveBlock(def.vertOffset) ? 1 : 0;
		shapeVertexPrivate[sId] = 0;
		shapeSensor[sId] = 0;
		shapeUserData[sId] = 0;
		shapeKind[sId] = def.kind;
		shapeVertOffset[sId] = def.vertOffset;
		shapeVertCount[sId] = def.vertCount;
		shapeDepth[sId] = def.depth;
		shapeRadius[sId] = def.radius;
		shapeLocalZ[sId] = def.localZ;
		shapeDensity[sId] = def.density;
		shapeCategoryBits[sId] = categoryBits;
		shapeMaskBits[sId] = maskBits;
		shapeGroupIndex[sId] = groupIndex;
		shapeFriction[sId] = friction;
		shapeRestitution[sId] = restitution;
		structureVersion++;
		shapeTopology[sId] = def.kind == ShapeKind.Polygon
			|| def.kind == ShapeKind.Hull ? ManifoldClipper.buildTopology(verts, def) : null;

		shapeNext[sId] = firstShape[bId];
		firstShape[bId] = sId;
		wakeBodySlot(bId);

		var q = new Quat(rotX[bId], rotY[bId], rotZ[bId], rotW[bId]);
		var px = posX[bId];
		var py = posY[bId];
		var pz = posZ[bId];
		var r = def.radius;

		var minX = px + Quat.rotate(q, def.getLocalSupport(verts, Quat.invRotate(q, new Vec3(-1, 0, 0)))).x - r;
		var maxX = px + Quat.rotate(q, def.getLocalSupport(verts, Quat.invRotate(q, new Vec3(1, 0, 0)))).x + r;
		var minY = py + Quat.rotate(q, def.getLocalSupport(verts, Quat.invRotate(q, new Vec3(0, -1, 0)))).y - r;
		var maxY = py + Quat.rotate(q, def.getLocalSupport(verts, Quat.invRotate(q, new Vec3(0, 1, 0)))).y + r;
		var minZ = pz + Quat.rotate(q, def.getLocalSupport(verts, Quat.invRotate(q, new Vec3(0, 0, -1)))).z - r;
		var maxZ = pz + Quat.rotate(q, def.getLocalSupport(verts, Quat.invRotate(q, new Vec3(0, 0, 1)))).z + r;

		shapeProxy[sId] = broadPhase.createProxy(minX, minY, minZ, maxX, maxY, maxZ, sId);
		if (shapeVertexOwned[sId] != 0)
			verts.retainBlock(shapeVertOffset[sId]);
		recalculateBodyMassAndDoF(bId);
		updateWorldCenter(bId);
		return (shapeGeneration[sId] << 20) | sId;
	}

	/**
	 * Turns a shape's collision on or off without detaching it. A disabled shape
	 * keeps its handle, geometry and share of the body's mass, but takes no part
	 * in contacts, queries or time-of-impact checks until it is enabled again.
	 */
	public function setShapeEnabled(shape:ShapeId, enabled:Bool):Void {
		var sId = shapeSlot(shape);
		if (enabled == (shapeProxy[sId] != BroadPhase.NULL_NODE))
			return;
		var body = shapeBody[sId];
		if (enabled) {
			shapeProxy[sId] = broadPhase.createProxy(posX[body], posY[body], posZ[body], posX[body], posY[body], posZ[body], sId);
			updateShapeAABBs(body, true);
		} else {
			for (c in 0...contacts.count) {
				if (contacts.shapeA[c] == sId || contacts.shapeB[c] == sId) {
					wakeBodySlot(contacts.bodyA[c]);
					wakeBodySlot(contacts.bodyB[c]);
				}
			}
			contacts.removeShape(sId);
			broadPhase.destroyProxy(shapeProxy[sId]);
			shapeProxy[sId] = BroadPhase.NULL_NODE;
		}
		wakeBodySlot(body);
	}

	public function isShapeEnabled(shape:ShapeId):Bool {
		return shapeProxy[shapeSlot(shape)] != BroadPhase.NULL_NODE;
	}

	/**
	 * Replaces the core vertices of a segment, polygon or hull on a static or
	 * kinematic body, keeping the shape's handle, vertex count, material and
	 * filtering. Polygons must stay convex in the local XY plane. Other shapes
	 * built from the same descriptor keep their original vertices.
	 */
	public function setShapeVertices(shape:ShapeId, vertices:Array<Vec3>):Void {
		var sId = shapeSlot(shape);
		var body = shapeBody[sId];
		if (bodyType[body] == BodyType.Dynamic)
			throw 'Only static and kinematic shapes can be reshaped';
		var kind:ShapeKind = shapeKind[sId];
		var count = shapeVertCount[sId];
		if (kind == ShapeKind.Point)
			throw 'Circles and spheres have no vertices to reshape';
		if (vertices == null || vertices.length != count)
			throw 'Reshaping must keep the vertex count';
		for (v in vertices) {
			if (v == null || !Math.isFinite(v.x) || !Math.isFinite(v.y) || !Math.isFinite(v.z))
				throw 'Invalid shape vertices';
			if (kind != ShapeKind.Hull && Math.abs(v.z) > 1e-6)
				throw 'Segment and polygon vertices must lie in the local XY plane';
		}
		if (kind == ShapeKind.Polygon)
			ShapeBuilder.checkPolygon(vertices);
		if (kind == ShapeKind.Hull)
			ConvexHull.triangles(vertices);
		if (shapeVertexPrivate[sId] == 0) {
			var offset = verts.allocateBlock(count);
			verts.retainBlock(offset);
			if (shapeVertexOwned[sId] != 0)
				verts.releaseBlock(shapeVertOffset[sId]);
			shapeVertOffset[sId] = offset;
			shapeVertexOwned[sId] = 1;
			shapeVertexPrivate[sId] = 1;
		}
		var offset = shapeVertOffset[sId];
		for (i in 0...count) {
			verts.vx[offset + i] = vertices[i].x;
			verts.vy[offset + i] = vertices[i].y;
			verts.vz[offset + i] = kind == ShapeKind.Hull ? vertices[i].z : 0.0;
		}
		structureVersion++;
		if (kind == ShapeKind.Polygon || kind == ShapeKind.Hull) {
			var def = pairScratch.shapeA;
			def.assign(kind, offset, count, shapeDepth[sId], shapeRadius[sId], shapeLocalZ[sId], shapeDensity[sId]);
			// A polygon keeping its winding only moves its faces; anything else is rebuilt.
			if (!ManifoldClipper.refreshPolygon(verts, def, shapeTopology[sId]))
				shapeTopology[sId] = ManifoldClipper.buildTopology(verts, def);
		}
		wakeTouching(body);
		updateShapeAABBs(body, true);
	}

	/**
	 * Gives a shape new geometry from `def`, on a body of any type, keeping its
	 * handle, material, filtering, sensor flag and user data. Its contacts are
	 * dropped, so the next step finds them afresh. A dynamic body's mass,
	 * inertia and centre follow the new geometry; its velocities are kept.
	 */
	public function reshapeShape(shape:ShapeId, def:ShapeDef):Void {
		var sId = shapeSlot(shape);
		if (def == null || !Math.isFinite(def.radius) || !Math.isFinite(def.depth) || !Math.isFinite(def.localZ) || !Math.isFinite(def.density)
			|| def.radius < 0.0 || def.depth < 0.0 || def.density < 0.0)
			throw 'Invalid shape dimensions or density';
		var kindValue:Int = def.kind;
		if (kindValue < 0 || kindValue > 3)
			throw 'Invalid shape kind';
		def.ensureVertices(verts);
		var required = def.kind == ShapeKind.Point ? 0 : (def.kind == ShapeKind.Segment ? 2 : (def.kind == ShapeKind.Polygon ? 3 : 4));
		if (def.vertCount < required
			|| (kindValue < 2 && def.vertCount != required)
			|| def.vertOffset < 0
			|| def.vertOffset + def.vertCount > verts.count)
			throw 'Invalid shape vertices';
		if (def.kind == ShapeKind.Polygon
			&& MassProperties.polygon(verts, def.vertOffset, def.vertCount, def.depth, def.localZ, 1.0).mass <= 0.0)
			throw 'Polygon has zero area';
		if (def.kind == ShapeKind.Hull)
			MassProperties.hull(verts, def.vertOffset, def.vertCount, def.localZ, 1.0);
		var body = shapeBody[sId];
		for (c in 0...contacts.count) {
			if (contacts.shapeA[c] == sId || contacts.shapeB[c] == sId) {
				wakeBodySlot(contacts.bodyA[c]);
				wakeBodySlot(contacts.bodyB[c]);
			}
		}
		// Manifold points are in the old geometry's terms.
		contacts.removeShape(sId);
		var owned = def.vertCount > 0 && verts.hasLiveBlock(def.vertOffset) ? 1 : 0;
		if (owned != 0)
			verts.retainBlock(def.vertOffset);
		if (shapeVertexOwned[sId] != 0)
			verts.releaseBlock(shapeVertOffset[sId]);
		shapeVertexOwned[sId] = owned;
		shapeVertexPrivate[sId] = 0;
		shapeKind[sId] = def.kind;
		shapeVertOffset[sId] = def.vertOffset;
		shapeVertCount[sId] = def.vertCount;
		shapeDepth[sId] = def.depth;
		shapeRadius[sId] = def.radius;
		shapeLocalZ[sId] = def.localZ;
		shapeDensity[sId] = def.density;
		shapeTopology[sId] = def.kind == ShapeKind.Polygon
			|| def.kind == ShapeKind.Hull ? ManifoldClipper.buildTopology(verts, def) : null;
		structureVersion++;
		recalculateBodyMassAndDoF(body);
		updateWorldCenter(body);
		wakeBodySlot(body);
		updateShapeAABBs(body, true);
	}

	/**
	 * Moves a joint's anchors: `localA` in its first body's frame and `localB`
	 * in its second's, relative to each body's origin. Axes, limits and drives
	 * are unchanged.
	 */
	public function setJointAnchors(joint:JointId, localA:Vec3, localB:Vec3):Void {
		joints.setAnchors(joint, localA, localB);
	}

	/** Mirrors a hinge's or spherical joint's frames; see `JointPool.mirrorFrames`. */
	public function mirrorJoint(joint:JointId, ex:Float, ey:Float, ez:Float):Void {
		joints.mirrorFrames(joint, ex, ey, ez);
	}

	/**
	 * Makes a shape a sensor, or a solid collider again. A sensor reports
	 * overlaps through `events` but never pushes on anything; ray and shape
	 * casts and time-of-impact checks pass through it.
	 */
	public function setShapeSensor(shape:ShapeId, sensor:Bool):Void {
		var sId = shapeSlot(shape);
		var value = sensor ? 1 : 0;
		if (shapeSensor[sId] == value)
			return;
		shapeSensor[sId] = value;
		if (sensor) {
			for (c in 0...contacts.count) {
				if (contacts.shapeA[c] == sId || contacts.shapeB[c] == sId) {
					wakeBodySlot(contacts.bodyA[c]);
					wakeBodySlot(contacts.bodyB[c]);
				}
			}
			contacts.removeShape(sId);
		}
		wakeBodySlot(shapeBody[sId]);
	}

	public function isShapeSensor(shape:ShapeId):Bool {
		return shapeSensor[shapeSlot(shape)] != 0;
	}

	/** Stores a value with the shape, such as a bone or slot index; events report it for both shapes. */
	public function setShapeUserData(shape:ShapeId, value:Int):Void {
		shapeUserData[shapeSlot(shape)] = value;
	}

	public function getShapeUserData(shape:ShapeId):Int {
		return shapeUserData[shapeSlot(shape)];
	}

	inline function shapeHandle(slot:Int):ShapeId {
		return (shapeGeneration[slot] << 20) | slot;
	}

	inline function liveShape(handle:Int):Bool {
		var slot = handle & 0xFFFFF;
		return slot < shapeCount
			&& shapeActive[slot] != 0
			&& shapeGeneration[slot] == (handle >>> 20)
			&& shapeProxy[slot] != BroadPhase.NULL_NODE;
	}

	inline function passiveBody(body:Int):Bool {
		return bodyType[body] == BodyType.Static || bodyType[body] == BodyType.Dynamic && pairAwake[body] == 0;
	}

	/** Records an impact for contact `c`, whose new point approached at `speed`. */
	function recordImpact(c:Int, speed:Float):Void {
		var sa = contacts.shapeA[c], sb = contacts.shapeB[c];
		var sign = 1.0;
		if (sa > sb) {
			var t = sa;
			sa = sb;
			sb = t;
			sign = -1.0;
		}
		events.impacts.pushImpact(shapeHandle(sa), shapeHandle(sb), shapeUserData[sa], shapeUserData[sb], speed, contacts.pointX[c], contacts.pointY[c],
			contacts.pointZ[c], sign * contacts.normalX[c], sign * contacts.normalY[c], sign * contacts.normalZ[c]);
	}

	/**
	 * Collects this step's touching solid pairs and sensor overlaps. Pairs the
	 * broadphase skipped because both bodies were passive are still touching.
	 */
	function gatherEvents():Void {
		var touching = events.touchingNext;
		var lastA = -1, lastB = -1;
		for (c in 0...contacts.count) {
			var sa = contacts.shapeA[c], sb = contacts.shapeB[c];
			if (sa > sb) {
				var t = sa;
				sa = sb;
				sb = t;
			}
			if (sa == lastA && sb == lastB)
				continue;
			lastA = sa;
			lastB = sb;
			touching.push(shapeHandle(sa), shapeHandle(sb), shapeUserData[sa], shapeUserData[sb]);
		}
		var previous = events.touching;
		for (i in 0...previous.count) {
			var ha = previous.a[i], hb = previous.b[i];
			if (!liveShape(ha) || !liveShape(hb))
				continue;
			var sa = ha & 0xFFFFF, sb = hb & 0xFFFFF;
			if (shapeSensor[sa] != 0 || shapeSensor[sb] != 0)
				continue;
			if (passiveBody(shapeBody[sa]) && passiveBody(shapeBody[sb]))
				touching.push(ha, hb, shapeUserData[sa], shapeUserData[sb]);
		}
		var overlaps = events.overlappingNext;
		for (position in 0...activeShapeCount) {
			var s = activeShapeIds[position];
			if (shapeSensor[s] == 0 || shapeProxy[s] == BroadPhase.NULL_NODE)
				continue;
			var count = broadPhase.overlapping(shapeProxy[s], overlapScratch);
			var body = shapeBody[s];
			for (k in 0...count) {
				var o = overlapScratch[k];
				if (o == s || shapeBody[o] == body || shapeSensor[o] != 0 && o < s)
					continue;
				if (!BroadPhase.filtersAllow(s, o, shapeCategoryBits, shapeMaskBits, shapeGroupIndex))
					continue;
				var other = shapeBody[o];
				var ps = pairScratch;
				loadPair(s, o, ps);
				if (NarrowPhase.overlapPair(verts, ps.shapeA, ps.posA, ps.rotA, ps.shapeB, ps.posB, ps.rotB, ps.narrow))
					overlaps.push(shapeHandle(s), shapeHandle(o), shapeUserData[s], shapeUserData[o]);
			}
		}
		events.finishStep();
	}

	/** Loads shapes `sA` and `sB` and their bodies' poses into `scratch`. */
	inline function loadPair(sA:Int, sB:Int, scratch:PairScratch):Void {
		var bA = shapeBody[sA], bB = shapeBody[sB];
		scratch.shapeA.assign(shapeKind[sA], shapeVertOffset[sA], shapeVertCount[sA], shapeDepth[sA], shapeRadius[sA], shapeLocalZ[sA], shapeDensity[sA]);
		scratch.shapeB.assign(shapeKind[sB], shapeVertOffset[sB], shapeVertCount[sB], shapeDepth[sB], shapeRadius[sB], shapeLocalZ[sB], shapeDensity[sB]);
		scratch.posA.x = posX[bA];
		scratch.posA.y = posY[bA];
		scratch.posA.z = posZ[bA];
		scratch.rotA.x = rotX[bA];
		scratch.rotA.y = rotY[bA];
		scratch.rotA.z = rotZ[bA];
		scratch.rotA.w = rotW[bA];
		scratch.posB.x = posX[bB];
		scratch.posB.y = posY[bB];
		scratch.posB.z = posZ[bB];
		scratch.rotB.x = rotX[bB];
		scratch.rotB.y = rotY[bB];
		scratch.rotB.z = rotZ[bB];
		scratch.rotB.w = rotW[bB];
	}

	/**
	 * Tests broadphase pair `i` and appends its contacts to `out`; returns
	 * whether any were added. Reads world state only, so worker threads can
	 * call it with their own scratch and output.
	 */
	function collideOne(i:Int, scratch:PairScratch, out:ContactManifoldPool):Bool {
		var p2 = i * 2;
		var sA = broadPhase.pairs[p2], sB = broadPhase.pairs[p2 + 1];
		if (shapeSensor[sA] != 0 || shapeSensor[sB] != 0 || !joints.bodiesMayCollide(shapeBody[sA], shapeBody[sB]))
			return false;
		var before = out.count;
		loadPair(sA, sB, scratch);
		NarrowPhase.collidePair(verts, scratch.shapeA, shapeBody[sA], scratch.posA, scratch.rotA, scratch.shapeB, shapeBody[sB], scratch.posB, scratch.rotB,
			out, sA, sB, shapeTopology[sA], shapeTopology[sB], scratch.clip, scratch.narrow);
		return out.count > before;
	}

	/** Wakes sleeping dynamic bodies of broadphase pair `i` once it has made contact. */
	function wakePair(i:Int):Void {
		wakeContactBodies(shapeBody[broadPhase.pairs[i * 2]], shapeBody[broadPhase.pairs[i * 2 + 1]]);
	}

	function wakeContactBodies(bA:Int, bB:Int):Void {
		if (bodyType[bA] == BodyType.Dynamic && islands.isAwake[bA] == 0)
			wakeBodySlot(bA);
		if (bodyType[bB] == BodyType.Dynamic && islands.isAwake[bB] == 0)
			wakeBodySlot(bB);
	}

	public function getShapeDef(shape:ShapeId):ShapeDef {
		var sId = shapeSlot(shape);
		var def = getShapeDefSlot(sId);
		if (shapeVertexOwned[sId] != 0) {
			var values:Array<Single> = [];
			for (i in 0...shapeVertCount[sId]) {
				values.push(verts.vx[shapeVertOffset[sId] + i]);
				values.push(verts.vy[shapeVertOffset[sId] + i]);
				values.push(verts.vz[shapeVertOffset[sId] + i]);
			}
			def.bindVertices(verts, values);
		}
		return def;
	}

	inline function getShapeDefSlot(sId:Int):ShapeDef {
		return new ShapeDef(shapeKind[sId], shapeVertOffset[sId], shapeVertCount[sId], shapeDepth[sId], shapeRadius[sId], shapeLocalZ[sId], shapeDensity[sId]);
	}

	public function destroyShape(shape:ShapeId):Void {
		destroyShapeSlot(shapeSlot(shape), true);
	}

	function destroyShapeSlot(sId:Int, recalculate:Bool):Void {
		var body = shapeBody[sId];
		var previous = -1, current = firstShape[body];
		while (current != sId) {
			previous = current;
			current = shapeNext[current];
		}
		if (previous == -1)
			firstShape[body] = shapeNext[sId];
		else
			shapeNext[previous] = shapeNext[sId];
		for (c in 0...contacts.count) {
			if (contacts.shapeA[c] == sId || contacts.shapeB[c] == sId) {
				wakeBodySlot(contacts.bodyA[c]);
				wakeBodySlot(contacts.bodyB[c]);
			}
		}
		// A reused shape slot must not inherit this shape's warm-start impulses.
		contacts.removeShape(sId);
		if (shapeProxy[sId] != BroadPhase.NULL_NODE)
			broadPhase.destroyProxy(shapeProxy[sId]);
		if (shapeVertexOwned[sId] != 0)
			verts.releaseBlock(shapeVertOffset[sId]);
		shapeProxy[sId] = BroadPhase.NULL_NODE;
		shapeTopology[sId] = null;
		structureVersion++;
		shapeActive[sId] = 0;
		var position = shapeActivePosition[sId];
		var last = activeShapeIds[--activeShapeCount];
		activeShapeIds[position] = last;
		shapeActivePosition[last] = position;
		shapeActivePosition[sId] = -1;
		shapeGeneration[sId] = (shapeGeneration[sId] + 1) & 0xFFF;
		shapeNextFree[sId] = shapeFreeHead;
		shapeFreeHead = sId;
		if (recalculate) {
			recalculateBodyMassAndDoF(body);
			updateWorldCenter(body);
			wakeBodySlot(body);
		}
	}

	public function destroyBody(body:BodyId):Void {
		var slot = bodySlot(body);
		wakeBodySlot(slot);
		for (c in 0...contacts.count) {
			if (contacts.bodyA[c] == slot || contacts.bodyB[c] == slot) {
				wakeBodySlot(contacts.bodyA[c]);
				wakeBodySlot(contacts.bodyB[c]);
			}
		}
		joints.destroyConnected(slot);
		joints.resetSplitVelocity(slot);
		while (firstShape[slot] != -1)
			destroyShapeSlot(firstShape[slot], false);
		bodyType[slot] = BodyType.Static;
		kinematicPending[slot] = 0;
		isBullet[slot] = 0;
		bodyDoF[slot] = DoFMask.Locked;
		islands.addBody(slot, BodyType.Static);
		bodyActive[slot] = 0;
		var position = bodyActivePosition[slot];
		var last = activeBodyIds[--activeBodyCount];
		activeBodyIds[position] = last;
		bodyActivePosition[last] = position;
		bodyActivePosition[slot] = -1;
		bodyGeneration[slot] = (bodyGeneration[slot] + 1) & 0xFFF;
		bodyNextFree[slot] = bodyFreeHead;
		bodyFreeHead = slot;
	}

	/** Whether a body's shapes give it volume, which makes it a 3D body when dynamic. */
	/**
	 * A body's velocity over the last step, by slot: its velocity, or for a
	 * kinematic body that followed a target in that step, the motion the
	 * target gave it, which `velX` and the rest no longer hold after the step.
	 */
	public inline function stepVelocityX(slot:Int):Float
		return movedKinematic(slot) ? kinematicVelX[slot] : velX[slot];

	public inline function stepVelocityY(slot:Int):Float
		return movedKinematic(slot) ? kinematicVelY[slot] : velY[slot];

	public inline function stepVelocityZ(slot:Int):Float
		return movedKinematic(slot) ? kinematicVelZ[slot] : velZ[slot];

	public inline function stepAngularVelocityX(slot:Int):Float
		return movedKinematic(slot) ? kinematicAngX[slot] : angVelX[slot];

	public inline function stepAngularVelocityY(slot:Int):Float
		return movedKinematic(slot) ? kinematicAngY[slot] : angVelY[slot];

	public inline function stepAngularVelocityZ(slot:Int):Float
		return movedKinematic(slot) ? kinematicAngZ[slot] : angVelZ[slot];

	inline function movedKinematic(slot:Int):Bool
		return bodyType[slot] == BodyType.Kinematic && kinematicMovedStep[slot] == stepCount && stepCount > 0;

	/**
	 * The mass a body's shapes give it, whatever its type, with their centroid
	 * in the body's frame written to `centroid`. Kinematic and static bodies
	 * keep no mass for the solver, but balance and similar measures need it.
	 * Allocates.
	 */
	public function shapeMass(body:BodyId, centroid:Vec3):Float {
		var bId = bodySlot(body);
		var sId = firstShape[bId];
		var mass = 0.0, sx = 0.0, sy = 0.0, sz = 0.0;
		while (sId != -1) {
			var kind:ShapeKind = shapeKind[sId];
			var props = kind == ShapeKind.Point ? MassProperties.point(shapeRadius[sId], shapeDepth[sId], shapeLocalZ[sId],
				shapeDensity[sId]) : kind == ShapeKind.Segment ? MassProperties.capsule(verts, shapeVertOffset[sId], shapeRadius[sId], shapeDepth[sId],
					shapeLocalZ[sId],
					shapeDensity[sId]) : kind == ShapeKind.Polygon ? MassProperties.polygon(verts, shapeVertOffset[sId], shapeVertCount[sId], shapeDepth[sId],
						shapeLocalZ[sId],
						shapeDensity[sId]) : MassProperties.hull(verts, shapeVertOffset[sId], shapeVertCount[sId], shapeLocalZ[sId], shapeDensity[sId]);
			mass += props.mass;
			sx += props.mass * props.centroidX;
			sy += props.mass * props.centroidY;
			sz += props.mass * props.centroidZ;
			sId = shapeNext[sId];
		}
		centroid.x = mass > 0.0 ? sx / mass : 0.0;
		centroid.y = mass > 0.0 ? sy / mass : 0.0;
		centroid.z = mass > 0.0 ? sz / mass : 0.0;
		return mass;
	}

	public function hasVolume(body:BodyId):Bool {
		return shapesHaveVolume(bodySlot(body));
	}

	/** Any shape with depth, a hull, or shapes at different local Z make a body volumetric. */
	function shapesHaveVolume(bId:Int):Bool {
		var sId = firstShape[bId];
		if (sId == -1)
			return false;
		var baseZ = shapeLocalZ[sId];
		while (sId != -1) {
			if (shapeDepth[sId] > 0.0 || shapeKind[sId] == ShapeKind.Hull || shapeLocalZ[sId] != baseZ)
				return true;
			sId = shapeNext[sId];
		}
		return false;
	}

	function recalculateBodyMassAndDoF(bId:Int):Void {
		if (bodyType[bId] != BodyType.Dynamic || firstShape[bId] == -1) {
			bodyDoF[bId] = DoFMask.Locked;
			invMassX[bId] = invMassY[bId] = invMassZ[bId] = 0.0;
			invInertiaX[bId] = invInertiaY[bId] = invInertiaZ[bId] = 0.0;
			invInertiaXY[bId] = invInertiaXZ[bId] = invInertiaYZ[bId] = 0.0;
			localCenterX[bId] = localCenterY[bId] = localCenterZ[bId] = 0.0;
			updateWorldInertia(bId);
			return;
		}

		var sId = firstShape[bId];
		var isVolumetric = shapesHaveVolume(bId);
		var mass:Float = 0.0, sx:Float = 0.0, sy:Float = 0.0, sz:Float = 0.0;
		var ixx:Float = 0.0, iyy:Float = 0.0, izz:Float = 0.0;
		var ixy:Float = 0.0, ixz:Float = 0.0, iyz:Float = 0.0;
		while (sId != -1) {
			var kind:ShapeKind = shapeKind[sId];
			var depth = shapeDepth[sId];
			var zOff = shapeLocalZ[sId];
			var props:MassProperties;
			if (kind == ShapeKind.Point)
				props = MassProperties.point(shapeRadius[sId], depth, zOff, shapeDensity[sId]);
			else if (kind == ShapeKind.Segment)
				props = MassProperties.capsule(verts, shapeVertOffset[sId], shapeRadius[sId], depth, zOff, shapeDensity[sId]);
			else if (kind == ShapeKind.Polygon)
				props = MassProperties.polygon(verts, shapeVertOffset[sId], shapeVertCount[sId], depth, zOff, shapeDensity[sId]);
			else
				props = MassProperties.hull(verts, shapeVertOffset[sId], shapeVertCount[sId], zOff, shapeDensity[sId]);
			mass += props.mass;
			sx += props.mass * props.centroidX;
			sy += props.mass * props.centroidY;
			sz += props.mass * props.centroidZ;
			ixx += props.ixx;
			iyy += props.iyy;
			izz += props.izz;
			ixy += props.ixy;
			ixz += props.ixz;
			iyz += props.iyz;
			sId = shapeNext[sId];
		}

		if (mass <= 0.0) {
			bodyDoF[bId] = DoFMask.Locked;
			invMassX[bId] = invMassY[bId] = invMassZ[bId] = 0.0;
			invInertiaX[bId] = invInertiaY[bId] = invInertiaZ[bId] = 0.0;
			invInertiaXY[bId] = invInertiaXZ[bId] = invInertiaYZ[bId] = 0.0;
			localCenterX[bId] = localCenterY[bId] = localCenterZ[bId] = 0.0;
			updateWorldInertia(bId);
			return;
		}
		var cx = sx / mass, cy = sy / mass, cz = sz / mass;
		localCenterX[bId] = cx;
		localCenterY[bId] = cy;
		localCenterZ[bId] = cz;
		// Each shape contributes inertia about the body origin; move the sum to its center of mass.
		var inertia = new Mat3(ixx
			- mass * (cy * cy + cz * cz), iyy
			- mass * (cx * cx + cz * cz), izz
			- mass * (cx * cx + cy * cy), ixy
			+ mass * cx * cy,
			ixz
			+ mass * cx * cz, iyz
			+ mass * cy * cz);
		var invMass:Single = 1.0 / mass;
		if (isVolumetric) {
			bodyDoF[bId] = DoFMask.Full3D;
			invMassX[bId] = invMassY[bId] = invMassZ[bId] = invMass;
			var inv = inertia.inverse();
			invInertiaX[bId] = inv.xx;
			invInertiaY[bId] = inv.yy;
			invInertiaZ[bId] = inv.zz;
			invInertiaXY[bId] = inv.xy;
			invInertiaXZ[bId] = inv.xz;
			invInertiaYZ[bId] = inv.yz;
		} else {
			bodyDoF[bId] = DoFMask.Planar;
			invMassX[bId] = invMassY[bId] = invMass;
			invMassZ[bId] = 0.0;
			invInertiaX[bId] = invInertiaY[bId] = 0.0;
			invInertiaZ[bId] = inertia.zz > 0.0 ? 1.0 / inertia.zz : 0.0;
			invInertiaXY[bId] = invInertiaXZ[bId] = invInertiaYZ[bId] = 0.0;
		}
		updateWorldInertia(bId);
	}

	function updateWorldInertia(bId:Int):Void {
		if (bodyDoF[bId] != DoFMask.Full3D) {
			invIxx[bId] = invIyy[bId] = invIxy[bId] = invIxz[bId] = invIyz[bId] = 0.0;
			invIzz[bId] = invInertiaZ[bId];
			return;
		}
		var x:Float = rotX[bId],
			y:Float = rotY[bId],
			z:Float = rotZ[bId],
			w:Float = rotW[bId];
		var r00 = 1.0 - 2.0 * (y * y + z * z),
			r01 = 2.0 * (x * y - z * w),
			r02 = 2.0 * (x * z + y * w);
		var r10 = 2.0 * (x * y + z * w),
			r11 = 1.0 - 2.0 * (x * x + z * z),
			r12 = 2.0 * (y * z - x * w);
		var r20 = 2.0 * (x * z - y * w),
			r21 = 2.0 * (y * z + x * w),
			r22 = 1.0 - 2.0 * (x * x + y * y);
		var mxx:Float = invInertiaX[bId],
			myy:Float = invInertiaY[bId],
			mzz:Float = invInertiaZ[bId];
		var mxy:Float = invInertiaXY[bId],
			mxz:Float = invInertiaXZ[bId],
			myz:Float = invInertiaYZ[bId];
		// World tensor R M R^T.
		var t00 = r00 * mxx + r01 * mxy + r02 * mxz,
			t01 = r00 * mxy + r01 * myy + r02 * myz,
			t02 = r00 * mxz + r01 * myz + r02 * mzz;
		var t10 = r10 * mxx + r11 * mxy + r12 * mxz,
			t11 = r10 * mxy + r11 * myy + r12 * myz,
			t12 = r10 * mxz + r11 * myz + r12 * mzz;
		var t20 = r20 * mxx + r21 * mxy + r22 * mxz,
			t21 = r20 * mxy + r21 * myy + r22 * myz,
			t22 = r20 * mxz + r21 * myz + r22 * mzz;
		invIxx[bId] = t00 * r00 + t01 * r01 + t02 * r02;
		invIyy[bId] = t10 * r10 + t11 * r11 + t12 * r12;
		invIzz[bId] = t20 * r20 + t21 * r21 + t22 * r22;
		invIxy[bId] = t00 * r10 + t01 * r11 + t02 * r12;
		invIxz[bId] = t00 * r20 + t01 * r21 + t02 * r22;
		invIyz[bId] = t10 * r20 + t11 * r21 + t12 * r22;
	}

	function updateWorldCenter(bId:Int):Void {
		var qx:Float = rotX[bId],
			qy:Float = rotY[bId],
			qz:Float = rotZ[bId],
			qw:Float = rotW[bId];
		var cx:Float = localCenterX[bId],
			cy:Float = localCenterY[bId],
			cz:Float = localCenterZ[bId];
		var tx = 2.0 * (qy * cz - qz * cy),
			ty = 2.0 * (qz * cx - qx * cz),
			tz = 2.0 * (qx * cy - qy * cx);
		worldCenterX[bId] = posX[bId] + cx + qw * tx + (qy * tz - qz * ty);
		worldCenterY[bId] = posY[bId] + cy + qw * ty + (qz * tx - qx * tz);
		worldCenterZ[bId] = posZ[bId] + cz + qw * tz + (qx * ty - qy * tx);
	}

	/**
	 * Refits each shape's broadphase box. Core vertices are rotated once and
	 * bounded; local Z offset and extrusion depth move along the body's rotated
	 * Z axis, and the rounding radius pads every side.
	 */
	function updateShapeAABBs(bId:Int, force:Bool = false):Void {
		var px:Float = posX[bId], py:Float = posY[bId], pz:Float = posZ[bId];
		var x:Float = rotX[bId],
			y:Float = rotY[bId],
			z:Float = rotZ[bId],
			w:Float = rotW[bId];
		var r00 = 1.0 - 2.0 * (y * y + z * z),
			r01 = 2.0 * (x * y - z * w),
			r02 = 2.0 * (x * z + y * w);
		var r10 = 2.0 * (x * y + z * w),
			r11 = 1.0 - 2.0 * (x * x + z * z),
			r12 = 2.0 * (y * z - x * w);
		var r20 = 2.0 * (x * z - y * w),
			r21 = 2.0 * (y * z + x * w),
			r22 = 1.0 - 2.0 * (x * x + y * y);
		var vx = verts.vx, vy = verts.vy, vz = verts.vz;
		var sId = firstShape[bId];
		while (sId != -1) {
			if (shapeProxy[sId] == BroadPhase.NULL_NODE) {
				sId = shapeNext[sId];
				continue;
			}
			var minX = 0.0, minY = 0.0, minZ = 0.0, maxX = 0.0, maxY = 0.0, maxZ = 0.0;
			var count = shapeKind[sId] == ShapeKind.Point ? 0 : shapeVertCount[sId];
			if (count > 0) {
				var offset = shapeVertOffset[sId];
				var ax:Float = vx[offset],
					ay:Float = vy[offset],
					az:Float = vz[offset];
				minX = maxX = r00 * ax + r01 * ay + r02 * az;
				minY = maxY = r10 * ax + r11 * ay + r12 * az;
				minZ = maxZ = r20 * ax + r21 * ay + r22 * az;
				for (i in 1...count) {
					var bx:Float = vx[offset + i],
						by:Float = vy[offset + i],
						bz:Float = vz[offset + i];
					var wx = r00 * bx + r01 * by + r02 * bz;
					var wy = r10 * bx + r11 * by + r12 * bz;
					var wz = r20 * bx + r21 * by + r22 * bz;
					if (wx < minX)
						minX = wx;
					else if (wx > maxX)
						maxX = wx;
					if (wy < minY)
						minY = wy;
					else if (wy > maxY)
						maxY = wy;
					if (wz < minZ)
						minZ = wz;
					else if (wz > maxZ)
						maxZ = wz;
				}
			}
			var lz:Float = shapeLocalZ[sId];
			var half:Float = shapeDepth[sId] * 0.5;
			var pad:Float = shapeRadius[sId];
			var ex = half * Math.abs(r02) + pad,
				ey = half * Math.abs(r12) + pad,
				ez = half * Math.abs(r22) + pad;
			var ox = px + lz * r02, oy = py + lz * r12, oz = pz + lz * r22;
			broadPhase.updateProxy(shapeProxy[sId], ox + minX - ex, oy + minY - ey, oz + minZ - ez, ox + maxX + ex, oy + maxY + ey, oz + maxZ + ez, force);
			sId = shapeNext[sId];
		}
	}

	/** Substeps a step is split into; gravity is added at the start of each. */
	public static inline var SUBSTEPS = 4;

	public function step(dt:Single):Void {
		if (dt <= 0.0)
			return;
		stepCount++;
		if (keepPreviousPoses)
			for (position in 0...activeBodyCount) {
				var i = activeBodyIds[position];
				if (bodyType[i] != BodyType.Static)
					copyPreviousPose(i);
			}
		events.beginStep();
		toi.beginStep();
		prepareKinematicTargets(dt);
		// Direct velocity writes are common while constructing scenes; treat them as a wake request.
		for (position in 0...activeBodyCount) {
			var i = activeBodyIds[position];
			if (bodyType[i] == BodyType.Dynamic
				&& islands.isAwake[i] == 0
				&& (velX[i] != 0.0 || velY[i] != 0.0 || velZ[i] != 0.0 || angVelX[i] != 0.0 || angVelY[i] != 0.0 || angVelZ[i] != 0.0))
				wakeBodySlot(i);
		}
		if (joints.count > 0)
			joints.propagateWake();
		for (substep in 0...SUBSTEPS) {
			var remaining:Single = dt / SUBSTEPS;
			var impacts = 0;
			while (remaining > 0.0) {
				var event = impacts < 32 ? toi.findEarliest(remaining, dt) : null;
				if (event == null) {
					stepSegment(remaining);
					break;
				}
				// Enter contact by a small fraction so the discrete manifold can resolve it.
				var fraction = Math.min(1.0, event.fraction + 1e-4);
				var advance:Single = remaining * Math.max(fraction, 1e-5);
				stepSegment(advance);
				toi.resolve(event);
				remaining -= advance;
				impacts++;
			}
		}
		gatherEvents();
		islands.build(contacts, bodyType, bodyCount, joints);
		islands.updateSleep(dt, bodyType, bodyCount, velX, velY, velZ, angVelX, angVelY, angVelZ, posX, posY, posZ, rotX, rotY, rotZ, rotW);
		finishKinematicTargets();
	}

	/**
	 * One substep, in the order of Box2D's soft step: gravity, then a solve
	 * whose bias pushes overlaps apart, then the poses move, then a relax pass
	 * without bias takes that push back out of the velocities, so resting
	 * contacts carry no velocity into the next substep. Restitution comes last,
	 * from the approach speed measured before the solve.
	 */
	function stepSegment(h:Single):Void {
		SimdBatch.integrateVelocities(bodyCount, velX, velY, velZ, invMassX, invMassY, invMassZ, gravity.x, gravity.y, gravity.z, h, islands.integrationMask,
			integrationConstants);

		for (b in 0...bodyCount)
			pairAwake[b] = islands.isAwake[b];
		broadPhase.findPairs(activeShapeCount, shapeProxy, shapeBody, bodyType, shapeCategoryBits, shapeMaskBits, shapeGroupIndex, islands.isAwake,
			activeShapeIds);
		contacts.beginStep();
		// Workers fill their own buffers and merge them in pair order, matching a serial pass.
		if (parallelIslands == null || !parallelIslands.collidePairs()) {
			for (i in 0...broadPhase.pairCount) {
				if (collideOne(i, pairScratch, contacts))
					wakePair(i);
			}
		}
		if (joints.count > 0)
			joints.propagateWake();
		var split = joints.findContactLoops();
		if (split)
			saveCorrectionVelocities();
		var parallelCandidate = parallelIslands != null && parallelIslands.mayDispatch();
		if (parallelCandidate)
			islands.build(contacts, bodyType, bodyCount, joints);
		solver.color();
		var partition = parallelCandidate ? parallelIslands.plan() : null;
		solver.prepare(h, partition);
		if (joints.count > 0) {
			joints.prepare(h);
			joints.usePartition(partition);
			joints.warmStart();
		}
		solver.warmStart();
		if (partition != null)
			parallelIslands.solve(4);
		else
			solver.solve(4);

		SimdBatch.integratePositions(bodyCount, posX, posY, posZ, velX, velY, velZ, h, islands.integrationMask, integrationConstants);
		kinematicElapsed += h;
		for (position in 0...activeBodyCount) {
			var i = activeBodyIds[position];
			if (bodyType[i] != BodyType.Static && islands.isAwake[i] != 0) {
				var qx:Float = rotX[i],
					qy:Float = rotY[i],
					qz:Float = rotZ[i],
					qw:Float = rotW[i];
				var cx:Float = localCenterX[i],
					cy:Float = localCenterY[i],
					cz:Float = localCenterZ[i];
				var nx:Float, ny:Float, nz:Float, nw:Float;
				var targeted = bodyType[i] == BodyType.Kinematic && kinematicPending[i] != 0;
				if (targeted) {
					var fraction:Float = Math.min(1.0, kinematicElapsed / kinematicStepDt);
					var sx:Float = kinematicStartX[i],
						sy:Float = kinematicStartY[i],
						sz:Float = kinematicStartZ[i];
					posX[i] = sx + (targetX[i] - sx) * fraction;
					posY[i] = sy + (targetY[i] - sy) * fraction;
					posZ[i] = sz + (targetZ[i] - sz) * fraction;
					var ax:Float = kinematicStartQx[i],
						ay:Float = kinematicStartQy[i],
						az:Float = kinematicStartQz[i],
						aw:Float = kinematicStartQw[i];
					var bx:Float = targetQx[i],
						by:Float = targetQy[i],
						bz:Float = targetQz[i],
						bw:Float = targetQw[i];
					var dot:Float = ax * bx + ay * by + az * bz + aw * bw;
					var sign = dot < 0.0 ? -1.0 : 1.0;
					if (dot < 0.0)
						dot = -dot;
					var wa:Float, wb:Float;
					if (dot > 0.9995) {
						wa = 1.0 - fraction;
						wb = fraction;
					} else {
						var angle = Math.acos(Math.min(1.0, dot));
						var inverse = 1.0 / Math.sin(angle);
						wa = Math.sin((1.0 - fraction) * angle) * inverse;
						wb = Math.sin(fraction * angle) * inverse;
					}
					nx = wa * ax + wb * sign * bx;
					ny = wa * ay + wb * sign * by;
					nz = wa * az + wb * sign * bz;
					nw = wa * aw + wb * sign * bw;
				} else {
					var half = 0.5 * h;
					var ox:Float = angVelX[i],
						oy:Float = angVelY[i],
						oz:Float = angVelZ[i];
					nx = qx + half * (ox * qw + oy * qz - oz * qy);
					ny = qy + half * (oy * qw + oz * qx - ox * qz);
					nz = qz + half * (oz * qw + ox * qy - oy * qx);
					nw = qw - half * (ox * qx + oy * qy + oz * qz);
				}
				var length = 1.0 / Math.sqrt(nx * nx + ny * ny + nz * nz + nw * nw);
				nx *= length;
				ny *= length;
				nz *= length;
				nw *= length;
				if (!targeted) {
					// Bodies turn about their center of mass, so the origin moves by the change in the rotated center.
					var otx = 2.0 * (qy * cz - qz * cy),
						oty = 2.0 * (qz * cx - qx * cz),
						otz = 2.0 * (qx * cy - qy * cx);
					var ntx = 2.0 * (ny * cz - nz * cy),
						nty = 2.0 * (nz * cx - nx * cz),
						ntz = 2.0 * (nx * cy - ny * cx);
					posX[i] += qw * otx + (qy * otz - qz * oty) - (nw * ntx + (ny * ntz - nz * nty));
					posY[i] += qw * oty + (qz * otx - qx * otz) - (nw * nty + (nz * ntx - nx * ntz));
					posZ[i] += qw * otz + (qx * oty - qy * otx) - (nw * ntz + (nx * nty - ny * ntx));
				}
				rotX[i] = nx;
				rotY[i] = ny;
				rotZ[i] = nz;
				rotW[i] = nw;
				updateWorldInertia(i);
				updateShapeAABBs(i);
			}
			updateWorldCenter(i);
		}
		if (split) {
			restoreCorrectionVelocities();
			solver.clearCorrectionImpulses(joints.splitVelocity);
			joints.clearCorrectionImpulses();
		}
		solver.relax();
		if (joints.count > 0)
			joints.relax();
		if (partition != null)
			parallelIslands.solve(1);
		else
			solver.solve(1);
		solver.applyRestitution();
		solver.storeImpulses();
		if (joints.count > 0)
			joints.storeImpulses();
	}

	function saveCorrectionVelocities():Void {
		var stride = bodyCapacity, count = bodyCount;
		if (correctionVelocities == null)
			correctionVelocities = new Float32Buffer(stride * 6);
		correctionVelocities.blit(0, velX, 0, count);
		correctionVelocities.blit(stride, velY, 0, count);
		correctionVelocities.blit(stride * 2, velZ, 0, count);
		correctionVelocities.blit(stride * 3, angVelX, 0, count);
		correctionVelocities.blit(stride * 4, angVelY, 0, count);
		correctionVelocities.blit(stride * 5, angVelZ, 0, count);
	}

	/** Position corrections move loop bodies without becoming their next-step velocity. */
	function restoreCorrectionVelocities():Void {
		var stride = bodyCapacity, mask = joints.splitVelocity;
		for (p in 0...activeBodyCount) {
			var b = activeBodyIds[p];
			if (mask[b] == 0)
				continue;
			velX[b] = correctionVelocities[b];
			velY[b] = correctionVelocities[stride + b];
			velZ[b] = correctionVelocities[stride * 2 + b];
			angVelX[b] = correctionVelocities[stride * 3 + b];
			angVelY[b] = correctionVelocities[stride * 4 + b];
			angVelZ[b] = correctionVelocities[stride * 5 + b];
		}
	}

	static function checkedRotation(rotation:Quat):Quat {
		if (rotation == null || !Math.isFinite(rotation.x) || !Math.isFinite(rotation.y) || !Math.isFinite(rotation.z) || !Math.isFinite(rotation.w))
			throw 'Invalid body rotation';
		var length = Math.sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z + rotation.w * rotation.w);
		if (length < 1e-8)
			throw 'Invalid body rotation';
		return new Quat(rotation.x / length, rotation.y / length, rotation.z / length, rotation.w / length);
	}

	static function checkedPosition(position:Vec3):Void {
		if (position == null || !Math.isFinite(position.x) || !Math.isFinite(position.y) || !Math.isFinite(position.z))
			throw 'Invalid body position';
	}

	inline function copyPreviousPose(slot:Int):Void {
		prevPosX[slot] = posX[slot];
		prevPosY[slot] = posY[slot];
		prevPosZ[slot] = posZ[slot];
		prevRotX[slot] = rotX[slot];
		prevRotY[slot] = rotY[slot];
		prevRotZ[slot] = rotZ[slot];
		prevRotW[slot] = rotW[slot];
	}

	/**
	 * A body's pose a fraction `alpha` of the way from before the most recent
	 * step (0) to now (1), for drawing between fixed steps. Needs
	 * `keepPreviousPoses`; without it the previous pose may be stale.
	 */
	public function getInterpolatedTransform(body:BodyId, alpha:Float):BodyTransform {
		var slot = bodySlot(body);
		var t = alpha < 0.0 ? 0.0 : alpha > 1.0 ? 1.0 : alpha;
		var ax:Float = prevRotX[slot],
			ay:Float = prevRotY[slot],
			az:Float = prevRotZ[slot],
			aw:Float = prevRotW[slot];
		var bx:Float = rotX[slot],
			by:Float = rotY[slot],
			bz:Float = rotZ[slot],
			bw:Float = rotW[slot];
		if (ax * bx + ay * by + az * bz + aw * bw < 0.0) {
			bx = -bx;
			by = -by;
			bz = -bz;
			bw = -bw;
		}
		var qx = ax + (bx - ax) * t,
			qy = ay + (by - ay) * t,
			qz = az + (bz - az) * t,
			qw = aw + (bw - aw) * t;
		var length = Math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
		return new BodyTransform(new Vec3(prevPosX[slot]
			+ (posX[slot] - prevPosX[slot]) * t, prevPosY[slot]
			+ (posY[slot] - prevPosY[slot]) * t,
			prevPosZ[slot]
			+ (posZ[slot] - prevPosZ[slot]) * t),
			new Quat(qx / length, qy / length, qz / length, qw / length));
	}

	/**
	 * A JSON snapshot of the world: every body with its type, sleep state,
	 * pose, velocities and shapes; every joint; and the contact count. Bodies
	 * come in slot order and numbers are rounded to four decimals, so equal
	 * worlds give equal text.
	 */
	/**
	 * What is wrong with the world, as findings with stable codes and paths:
	 * non-finite or skewed poses, dynamic bodies with no mass or only
	 * sensors, bodies far from the origin or fallen out of the world, joints
	 * that hold nothing, shapes with no extent, and capacities nearly full.
	 * A sound world reports nothing. Allocates only the report; pass a report
	 * to clear and reuse it without allocating on a sound world.
	 */
	public function validate(?report:hxn.me.physics.diagnostics.Diagnostics):hxn.me.physics.diagnostics.Diagnostics {
		return WorldValidation.world(this, report);
	}

	public function describe():String {
		return WorldDescription.world(this);
	}

	/** The JSON entry `describe` gives for one body. */
	public function describeBody(body:BodyId):String {
		return WorldDescription.body(this, bodySlot(body));
	}

	public function getBodyTransform(body:BodyId):BodyTransform {
		var slot = bodySlot(body);
		return new BodyTransform(new Vec3(posX[slot], posY[slot], posZ[slot]), new Quat(rotX[slot], rotY[slot], rotZ[slot], rotW[slot]));
	}

	public function setKinematicTarget(body:BodyId, position:Vec3, rotation:Quat):Void {
		var slot = bodySlot(body);
		if (bodyType[slot] != BodyType.Kinematic)
			throw 'Body is not kinematic';
		checkedPosition(position);
		if (rotation == null || !Math.isFinite(rotation.x) || !Math.isFinite(rotation.y) || !Math.isFinite(rotation.z) || !Math.isFinite(rotation.w))
			throw 'Invalid body rotation';
		targetX[slot] = position.x;
		targetY[slot] = position.y;
		targetZ[slot] = position.z;
		targetQx[slot] = rotation.x;
		targetQy[slot] = rotation.y;
		targetQz[slot] = rotation.z;
		targetQw[slot] = rotation.w;
		commitKinematicTarget(slot);
	}

	/**
	 * Uses the pose in `targetX`..`targetQw` at `slot` as the kinematic target
	 * for the next step, like `setKinematicTarget` without building objects.
	 * Normalises the rotation. A pose that is not finite, or a zero rotation,
	 * throws and leaves the body with no pending target.
	 */
	public function commitKinematicTarget(slot:Int):Void {
		if (slot < 0 || slot >= bodyCount || bodyActive[slot] == 0)
			throw 'Invalid body slot';
		if (bodyType[slot] != BodyType.Kinematic)
			throw 'Body is not kinematic';
		var x:Float = targetX[slot],
			y:Float = targetY[slot],
			z:Float = targetZ[slot];
		var qx:Float = targetQx[slot],
			qy:Float = targetQy[slot],
			qz:Float = targetQz[slot],
			qw:Float = targetQw[slot];
		var length = Math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
		if (!Math.isFinite(x) || !Math.isFinite(y) || !Math.isFinite(z)) {
			kinematicPending[slot] = 0;
			throw 'Invalid body position';
		}
		if (!Math.isFinite(length) || length < 1e-8) {
			kinematicPending[slot] = 0;
			throw 'Invalid body rotation';
		}
		targetQx[slot] = qx / length;
		targetQy[slot] = qy / length;
		targetQz[slot] = qz / length;
		targetQw[slot] = qw / length;
		kinematicPending[slot] = 1;
	}

	function prepareKinematicTargets(dt:Single):Void {
		kinematicStepDt = dt;
		kinematicElapsed = 0.0;
		for (position in 0...activeBodyCount) {
			var slot = activeBodyIds[position];
			if (kinematicPending[slot] == 0)
				continue;
			var px:Float = posX[slot],
				py:Float = posY[slot],
				pz:Float = posZ[slot];
			var ax:Float = rotX[slot],
				ay:Float = rotY[slot],
				az:Float = rotZ[slot],
				aw:Float = rotW[slot];
			kinematicStartX[slot] = px;
			kinematicStartY[slot] = py;
			kinematicStartZ[slot] = pz;
			kinematicStartQx[slot] = ax;
			kinematicStartQy[slot] = ay;
			kinematicStartQz[slot] = az;
			kinematicStartQw[slot] = aw;
			var vx = (targetX[slot] - px) / dt,
				vy = (targetY[slot] - py) / dt,
				vz = (targetZ[slot] - pz) / dt;
			velX[slot] = vx;
			velY[slot] = vy;
			velZ[slot] = vz;
			// Angular velocity that turns the current rotation into the target over dt, the short way round.
			var dot = ax * targetQx[slot] + ay * targetQy[slot] + az * targetQz[slot] + aw * targetQw[slot];
			var sign = dot < 0.0 ? -1.0 : 1.0;
			var tx = targetQx[slot] * sign,
				ty = targetQy[slot] * sign,
				tz = targetQz[slot] * sign,
				tw = targetQw[slot] * sign;
			var rx = tx * aw - tw * ax - ty * az + tz * ay;
			var ry = ty * aw - tw * ay - tz * ax + tx * az;
			var rz = tz * aw - tw * az - tx * ay + ty * ax;
			var vectorLength = Math.sqrt(rx * rx + ry * ry + rz * rz);
			var scale = vectorLength < 1e-6 ? 2.0 / dt : 2.0 * Math.atan2(vectorLength, Math.max(0.0, dot * sign)) / (vectorLength * dt);
			angVelX[slot] = rx * scale;
			angVelY[slot] = ry * scale;
			angVelZ[slot] = rz * scale;
			kinematicVelX[slot] = vx;
			kinematicVelY[slot] = vy;
			kinematicVelZ[slot] = vz;
			kinematicAngX[slot] = rx * scale;
			kinematicAngY[slot] = ry * scale;
			kinematicAngZ[slot] = rz * scale;
			kinematicMovedStep[slot] = stepCount;
			if (vx != 0.0 || vy != 0.0 || vz != 0.0 || rx != 0.0 || ry != 0.0 || rz != 0.0)
				wakeTouching(slot);
		}
	}

	function finishKinematicTargets():Void {
		for (position in 0...activeBodyCount) {
			var slot = activeBodyIds[position];
			if (kinematicPending[slot] == 0)
				continue;
			posX[slot] = targetX[slot];
			posY[slot] = targetY[slot];
			posZ[slot] = targetZ[slot];
			rotX[slot] = targetQx[slot];
			rotY[slot] = targetQy[slot];
			rotZ[slot] = targetQz[slot];
			rotW[slot] = targetQw[slot];
			updateWorldCenter(slot);
			updateShapeAABBs(slot, true);
			velX[slot] = velY[slot] = velZ[slot] = 0.0;
			angVelX[slot] = angVelY[slot] = angVelZ[slot] = 0.0;
			kinematicPending[slot] = 0;
		}
	}

	function wakeTouching(slot:Int):Void {
		for (c in 0...contacts.count) {
			if (contacts.bodyA[c] == slot)
				wakeBodySlot(contacts.bodyB[c]);
			if (contacts.bodyB[c] == slot)
				wakeBodySlot(contacts.bodyA[c]);
		}
	}

	function wakeJointNeighbors(slot:Int):Void {
		for (position in 0...joints.count) {
			var joint = joints.activeIds[position];
			if (joints.bodyA[joint] == slot)
				wakeBodySlot(joints.bodyB[joint]);
			if (joints.bodyB[joint] == slot)
				wakeBodySlot(joints.bodyA[joint]);
		}
	}

	public function teleportBody(body:BodyId, position:Vec3, rotation:Quat):Void {
		var slot = bodySlot(body);
		checkedPosition(position);
		var q = checkedRotation(rotation);
		wakeTouching(slot);
		wakeJointNeighbors(slot);
		wakeBodySlot(slot);
		contacts.removeBody(slot);
		kinematicPending[slot] = 0;
		kinematicMovedStep[slot] = 0;
		posX[slot] = position.x;
		posY[slot] = position.y;
		posZ[slot] = position.z;
		rotX[slot] = q.x;
		rotY[slot] = q.y;
		rotZ[slot] = q.z;
		rotW[slot] = q.w;
		copyPreviousPose(slot);
		velX[slot] = velY[slot] = velZ[slot] = 0.0;
		angVelX[slot] = angVelY[slot] = angVelZ[slot] = 0.0;
		updateWorldInertia(slot);
		updateWorldCenter(slot);
		updateShapeAABBs(slot, true);
	}

	/**
	 * Changes a body between static, kinematic and dynamic, keeping its pose.
	 * Mass and degrees of freedom are recomputed from its shapes, its contacts
	 * are rebuilt on the next step, and touching or jointed bodies wake. A
	 * kinematic body that followed a target in the last step keeps that motion
	 * as a dynamic body; any other switch leaves the body at rest. Set
	 * `velX`..`angVelZ` afterwards to choose the motion yourself.
	 * A joint with no dynamic body applies no impulse until one of its bodies
	 * is dynamic.
	 */
	public function setBodyType(body:BodyId, type:BodyType):Void {
		var slot = bodySlot(body);
		if (bodyType[slot] == type)
			return;
		var carry = bodyType[slot] == BodyType.Kinematic
			&& type == BodyType.Dynamic
			&& kinematicMovedStep[slot] == stepCount
			&& stepCount > 0;
		wakeTouching(slot);
		wakeJointNeighbors(slot);
		contacts.removeBody(slot);
		kinematicPending[slot] = 0;
		bodyType[slot] = type;
		joints.resetSplitVelocity(slot);
		islands.addBody(slot, type);
		velX[slot] = velY[slot] = velZ[slot] = 0.0;
		angVelX[slot] = angVelY[slot] = angVelZ[slot] = 0.0;
		recalculateBodyMassAndDoF(slot);
		if (carry) {
			velX[slot] = kinematicVelX[slot];
			velY[slot] = kinematicVelY[slot];
			velZ[slot] = kinematicVelZ[slot];
			angVelX[slot] = kinematicAngX[slot];
			angVelY[slot] = kinematicAngY[slot];
			angVelZ[slot] = kinematicAngZ[slot];
			if (bodyDoF[slot] == DoFMask.Planar)
				velZ[slot] = angVelX[slot] = angVelY[slot] = 0.0;
		}
		updateWorldCenter(slot);
		updateShapeAABBs(slot, true);
	}

	public function setBullet(body:BodyId, bullet:Bool):Void {
		isBullet[bodySlot(body)] = bullet ? 1 : 0;
	}

	public function wakeBody(body:BodyId):Void {
		wakeBodySlot(bodySlot(body));
	}

	/**
	 * Changes a dynamic body's velocities as an impulse (newton-seconds) at a
	 * world point would, and wakes it. Static and kinematic bodies are left as
	 * they are.
	 */
	public function applyImpulse(body:BodyId, impulse:Vec3, point:Vec3):Void {
		var s = bodySlot(body);
		checkedPosition(impulse);
		checkedPosition(point);
		if (bodyType[s] != BodyType.Dynamic)
			return;
		wakeBodySlot(s);
		velX[s] += impulse.x * invMassX[s];
		velY[s] += impulse.y * invMassY[s];
		velZ[s] += impulse.z * invMassZ[s];
		var rx = point.x - worldCenterX[s],
			ry = point.y - worldCenterY[s],
			rz = point.z - worldCenterZ[s];
		var tx = ry * impulse.z - rz * impulse.y,
			ty = rz * impulse.x - rx * impulse.z,
			tz = rx * impulse.y - ry * impulse.x;
		angVelX[s] += invIxx[s] * tx + invIxy[s] * ty + invIxz[s] * tz;
		angVelY[s] += invIxy[s] * tx + invIyy[s] * ty + invIyz[s] * tz;
		angVelZ[s] += invIxz[s] * tx + invIyz[s] * ty + invIzz[s] * tz;
	}

	@:allow(hxn.me.physics.joints.JointPool)
	function wakeBodySlot(slot:Int):Void {
		islands.wakeBody(slot, bodyType, bodyCount);
	}

	public function createDistanceJoint(a:BodyId, b:BodyId, length:Single, frequency:Single = 0.0, damping:Single = 1.0, localA:Vec3 = null,
			localB:Vec3 = null):JointId {
		return joints.createDistance(a, b, length, frequency, damping, localA, localB);
	}

	public function createHingeJoint(a:BodyId, b:BodyId, worldAnchor:Vec3, worldAxis:Vec3 = null, lowerAngle:Single = -1.0e30, upperAngle:Single = 1.0e30,
			motorSpeed:Single = 0.0, maxMotorTorque:Single = 0.0):JointId {
		return joints.createHinge(a, b, worldAnchor, worldAxis, lowerAngle, upperAngle, motorSpeed, maxMotorTorque);
	}

	public function setHingeDrive(joint:JointId, targetAngle:Single, stiffness:Single, damping:Single, maxTorque:Single):Void {
		joints.setHingeDrive(joint, targetAngle, stiffness, damping, maxTorque);
	}

	public function createPrismaticJoint(a:BodyId, b:BodyId, worldAnchor:Vec3, worldAxis:Vec3, lowerTranslation:Single = -1.0e30,
			upperTranslation:Single = 1.0e30, motorSpeed:Single = 0.0, maxMotorForce:Single = 0.0):JointId {
		return joints.createPrismatic(a, b, worldAnchor, worldAxis, lowerTranslation, upperTranslation, motorSpeed, maxMotorForce);
	}

	public function createWeldJoint(a:BodyId, b:BodyId, worldAnchor:Vec3, frequency:Single = 30.0, damping:Single = 1.0):JointId {
		return joints.createWeld(a, b, worldAnchor, frequency, damping);
	}

	public function createSphericalJoint(a:BodyId, b:BodyId, worldAnchor:Vec3, worldAxis:Vec3 = null, swingLimit:Single = 3.14159265,
			lowerTwist:Single = -3.14159265, upperTwist:Single = 3.14159265):JointId {
		return joints.createSpherical(a, b, worldAnchor, worldAxis == null ? new Vec3(0, 1, 0) : worldAxis, swingLimit, lowerTwist, upperTwist);
	}

	public function setSphericalDrive(joint:JointId, targetOffset:Quat, stiffness:Single, damping:Single, maxTorque:Single):Void {
		joints.setSphericalDrive(joint, targetOffset, stiffness, damping, maxTorque);
	}

	public function destroyJoint(id:JointId):Void {
		joints.destroy(id);
	}

	public function setJointCollideConnected(id:JointId, collide:Bool):Void {
		joints.setCollideConnected(id, collide);
	}

	public inline function queryAABB(min:Vec3, max:Vec3, mask:Int, callback:ShapeId->Bool):Void {
		query.queryAABB(min, max, mask, callback);
	}

	public inline function rayCast(origin:Vec3, dir:Vec3, maxFraction:Single, mask:Int = -1, callback:QueryHit->Void = null):QueryHit {
		return query.rayCast(origin, dir, maxFraction, mask, callback);
	}

	public inline function shapeCast(def:ShapeDef, startPos:Vec3, startRot:Quat, translation:Vec3, mask:Int = -1):QueryHit {
		return query.shapeCast(def, startPos, startRot, translation, mask);
	}

	/** Visits the state a `WorldSnapshot` saves and restores, in a fixed order. */
	@:noCompletion public function visitState(s:WorldSnapshot):Void {
		var liveBodies = bodyCount, liveShapes = shapeCount;
		bodyCount = s.int(bodyCount);
		activeBodyCount = s.int(activeBodyCount);
		bodyFreeHead = s.int(bodyFreeHead);
		shapeCount = s.int(shapeCount);
		activeShapeCount = s.int(activeShapeCount);
		shapeFreeHead = s.int(shapeFreeHead);
		stepCount = s.int(stepCount);
		jointSweeps = s.int(jointSweeps);
		keepPreviousPoses = s.bool(keepPreviousPoses);
		gravity.x = s.float(gravity.x);
		gravity.y = s.float(gravity.y);
		gravity.z = s.float(gravity.z);
		var bodies = s.span(liveBodies, bodyCount),
			shapes = s.span(liveShapes, shapeCount);
		s.ints(bodyGeneration, bodies);
		s.ints(bodyActive, bodies);
		s.ints(activeBodyIds, bodies);
		s.ints(bodyActivePosition, bodies);
		s.ints(bodyNextFree, bodies);
		s.ints(kinematicPending, bodies);
		s.ints(kinematicMovedStep, bodies);
		s.ints(bodyType, bodies);
		s.ints(bodyDoF, bodies);
		s.ints(isBullet, bodies);
		s.ints(firstShape, bodies);
		s.floats(kinematicVelX, bodies);
		s.floats(kinematicVelY, bodies);
		s.floats(kinematicVelZ, bodies);
		s.floats(kinematicAngX, bodies);
		s.floats(kinematicAngY, bodies);
		s.floats(kinematicAngZ, bodies);
		s.floats(targetX, bodies);
		s.floats(targetY, bodies);
		s.floats(targetZ, bodies);
		s.floats(targetQx, bodies);
		s.floats(targetQy, bodies);
		s.floats(targetQz, bodies);
		s.floats(targetQw, bodies);
		s.floats(posX, bodies);
		s.floats(posY, bodies);
		s.floats(posZ, bodies);
		s.floats(rotX, bodies);
		s.floats(rotY, bodies);
		s.floats(rotZ, bodies);
		s.floats(rotW, bodies);
		s.floats(prevPosX, bodies);
		s.floats(prevPosY, bodies);
		s.floats(prevPosZ, bodies);
		s.floats(prevRotX, bodies);
		s.floats(prevRotY, bodies);
		s.floats(prevRotZ, bodies);
		s.floats(prevRotW, bodies);
		s.floats(velX, bodies);
		s.floats(velY, bodies);
		s.floats(velZ, bodies);
		s.floats(angVelX, bodies);
		s.floats(angVelY, bodies);
		s.floats(angVelZ, bodies);
		s.floats(invMassX, bodies);
		s.floats(invMassY, bodies);
		s.floats(invMassZ, bodies);
		s.floats(invInertiaX, bodies);
		s.floats(invInertiaY, bodies);
		s.floats(invInertiaZ, bodies);
		s.floats(invInertiaXY, bodies);
		s.floats(invInertiaXZ, bodies);
		s.floats(invInertiaYZ, bodies);
		s.floats(localCenterX, bodies);
		s.floats(localCenterY, bodies);
		s.floats(localCenterZ, bodies);
		s.floats(worldCenterX, bodies);
		s.floats(worldCenterY, bodies);
		s.floats(worldCenterZ, bodies);
		s.floats(invIxx, bodies);
		s.floats(invIyy, bodies);
		s.floats(invIzz, bodies);
		s.floats(invIxy, bodies);
		s.floats(invIxz, bodies);
		s.floats(invIyz, bodies);
		s.ints(shapeGeneration, shapes);
		s.ints(shapeActive, shapes);
		s.ints(activeShapeIds, shapes);
		s.ints(shapeActivePosition, shapes);
		s.ints(shapeNextFree, shapes);
		s.ints(shapeBody, shapes);
		s.ints(shapeVertexOwned, shapes);
		s.ints(shapeSensor, shapes);
		s.ints(shapeUserData, shapes);
		s.ints(shapeVertexPrivate, shapes);
		s.ints(shapeNext, shapes);
		s.ints(shapeProxy, shapes);
		s.ints(shapeKind, shapes);
		s.ints(shapeVertOffset, shapes);
		s.ints(shapeVertCount, shapes);
		s.ints(shapeCategoryBits, shapes);
		s.ints(shapeMaskBits, shapes);
		s.ints(shapeGroupIndex, shapes);
		s.singles(shapeDepth, shapes);
		s.singles(shapeRadius, shapes);
		s.singles(shapeLocalZ, shapes);
		s.singles(shapeDensity, shapes);
		s.floats(shapeFriction, shapes);
		s.floats(shapeRestitution, shapes);
		broadPhase.visitState(s);
		contacts.visitState(s);
		islands.visitState(s, bodies);
		joints.visitState(s, bodies);
		events.visitState(s);
	}
}
