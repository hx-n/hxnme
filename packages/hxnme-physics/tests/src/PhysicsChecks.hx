import hxn.me.physics.geom.MassProperties;
import hxn.me.physics.geom.VertexPool;
import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Mat3;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles;
import hxn.me.physics.collision.BroadPhase;
import hxn.me.physics.collision.NarrowPhase;
import hxn.me.physics.collision.NarrowPhase.ContactManifoldPool;
import hxn.me.physics.collision.ManifoldClipper;
import hxn.me.physics.collision.ManifoldClipper.ClipWorkspace;
import hxn.me.physics.island.ConstraintGraph;
import hxn.me.physics.island.IslandManager;
import hxn.Float32Buffer;

class PhysicsChecks {
    static function near(actual:Float, expected:Float, label:String, tolerance:Float = 0.0001):Void {
        if (Math.abs(actual - expected) > tolerance) throw '$label: expected $expected, got $actual';
    }

    static function mustThrow(action:Void->Void, label:String):Void {
        var thrown = false;
        try action() catch (_:Dynamic) thrown = true;
        if (!thrown) throw '$label accepted a stale handle';
    }

    static function checkQueries():Void {
        var world = new World(8, 8);
        var nearBody = world.createBody(BodyType.Static, 2, 0, 0);
        var nearShape = world.attachShape(nearBody, ShapeBuilder.makeCircle(0.5), 1);
        var farBody = world.createBody(BodyType.Static, 5, 0, 0);
        var farShape = world.attachShape(farBody, ShapeBuilder.makeCircle(0.5), 2);
        var highBody = world.createBody(BodyType.Static, 2, 0, 3);
        var highShape = world.attachShape(highBody, ShapeBuilder.makeCircle(0.5, 1.0), 4);
        var found:Array<ShapeId> = [];
        world.queryAABB(new Vec3(1, -1, 0), new Vec3(3, 1, 0), -1, function(shape) {
            found.push(shape); return true;
        });
        if (found.length != 1 || found[0] != nearShape) throw 'planar AABB slice';
        found = [];
        world.queryAABB(new Vec3(1, -1, 0.25), new Vec3(3, 1, 0.25), 1, function(shape) {
            found.push(shape); return true;
        });
        if (found.length != 0) throw 'planar AABB accepted an off-plane slice';
        found = [];
        world.queryAABB(new Vec3(1, -1, 2), new Vec3(3, 1, 4), 4, function(shape) {
            found.push(shape); return true;
        });
        if (found.length != 1 || found[0] != highShape) throw 'volumetric AABB or mask';
        var callbacks = 0;
        var ray = world.rayCast(new Vec3(), new Vec3(1, 0, 0), 10, -1, function(hit) callbacks++);
        if (ray == null || ray.shape != nearShape || callbacks != 1) throw 'nearest planar ray';
        near(ray.fraction, 1.5, 'planar ray fraction', 0.002);
        near(ray.point.x, 1.5, 'planar ray point', 0.002);
        near(ray.normal.x, -1.0, 'planar ray normal', 0.002);
        if (world.rayCast(new Vec3(0, 0, 0.25), new Vec3(1, 0, 0), 10, 1) != null)
            throw 'off-plane ray hit planar shape';
        var downward = world.rayCast(new Vec3(2, 0, 2), new Vec3(0, 0, -1), 4, 1);
        if (downward == null || downward.shape != nearShape) throw 'cross-plane ray';
        near(downward.fraction, 2, 'cross-plane fraction', 0.002);
        near(downward.normal.z, 1, 'cross-plane normal');
        var masked = world.rayCast(new Vec3(), new Vec3(1, 0, 0), 10, 2);
        if (masked == null || masked.shape != farShape) throw 'ray category mask';
        near(masked.fraction, 4.5, 'masked ray fraction', 0.002);
        if (world.rayCast(new Vec3(), new Vec3(1, 0, 0), 1, 1) != null) throw 'short ray hit';
        var inside = world.rayCast(new Vec3(2, 0, 0), new Vec3(1, 0, 0), 10, 1);
        if (inside == null || inside.shape != nearShape) throw 'inside ray';
        near(inside.fraction, 0, 'inside ray fraction');
        var sweep = world.shapeCast(ShapeBuilder.makeCircle(0.5), new Vec3(), new Quat(), new Vec3(4, 0, 0), 1);
        if (sweep == null || sweep.shape != nearShape) throw 'planar shape cast';
        near(sweep.fraction, 0.25, 'planar shape cast fraction', 0.002);
        if (world.shapeCast(ShapeBuilder.makeCircle(0.5), new Vec3(0, 0, 0.25),
            new Quat(), new Vec3(4, 0, 0), 1) != null) throw 'off-plane shape cast';
        var highRay = world.rayCast(new Vec3(0, 0, 3), new Vec3(1, 0, 0), 10, 4);
        if (highRay == null || highRay.shape != highShape) throw '3D ray cast';
        near(highRay.fraction, 1.5, '3D ray fraction', 0.002);
        world.destroyBody(nearBody);
        var recycledBody = world.createBody(BodyType.Static, 2, 0, 0);
        var recycledShape = world.attachShape(recycledBody, ShapeBuilder.makeCircle(0.25), 1);
        if (recycledShape == nearShape) throw 'query handle generation';
        var recycledHit = world.rayCast(new Vec3(), new Vec3(1, 0, 0), 10, 1);
        if (recycledHit == null || recycledHit.shape != recycledShape) throw 'query returned stale handle';

        var boxWorld = new World(4, 4);
        var boxBody = boxWorld.createBody(BodyType.Static, 0, 0, 0);
        var boxShape = boxWorld.attachShape(boxBody, ShapeBuilder.makeBox(boxWorld.verts, 1, 1, 2, 0));
        var boxRay = boxWorld.rayCast(new Vec3(-3, 0, 0), new Vec3(1, 0, 0), 6);
        if (boxRay == null || boxRay.shape != boxShape) throw '3D convex ray';
        near(boxRay.fraction, 2, '3D box ray fraction', 0.002);
        var boxSweep = boxWorld.shapeCast(ShapeBuilder.makeCircle(0.5, 1),
            new Vec3(-3, 0, 0), new Quat(), new Vec3(4, 0, 0));
        if (boxSweep == null || boxSweep.shape != boxShape) throw '3D convex shape cast';
        near(boxSweep.fraction, 0.375, '3D box shape cast fraction', 0.002);

        var tree = new BroadPhase(128);
        for (i in 0...50) tree.createProxy(i * 3, 0, 0, i * 3 + 1, 1, 1, i);
        var visited = 0;
        tree.queryAABB(-1, -1, -1, 200, 2, 2, function(_) { visited++; return true; });
        near(visited, 50, 'tree query stack traversal');
    }

    static function checkCCD():Void {
        var circle = new World(4, 4);
        circle.gravity = new Vec3();
        var wall = circle.createBody(BodyType.Static, 0, 0);
        circle.attachShape(wall, ShapeBuilder.makeBox(circle.verts, 0.025, 2, 0, 0));
        var ball = circle.createBody(BodyType.Dynamic, -2, 0);
        circle.attachShape(ball, ShapeBuilder.makeCircle(0.1));
        circle.velX[circle.bodySlot(ball)] = 600;
        circle.step(1.0 / 60.0);
        if (circle.posX[circle.bodySlot(ball)] > -0.08)
            throw 'fast circle crossed planar wall: x=${circle.posX[circle.bodySlot(ball)]}, vx=${circle.velX[circle.bodySlot(ball)]}';

        var capsule = new World(4, 4);
        capsule.gravity = new Vec3();
        wall = capsule.createBody(BodyType.Static, 0, 0);
        capsule.attachShape(wall, ShapeBuilder.makeBox(capsule.verts, 0.025, 2, 0, 0));
        var rod = capsule.createBody(BodyType.Dynamic, -2, 0);
        capsule.attachShape(rod, ShapeBuilder.makeCapsule(capsule.verts, 0, -0.2, 0, 0.2, 0, 0.1));
        capsule.velX[capsule.bodySlot(rod)] = 600;
        capsule.step(1.0 / 60.0);
        if (capsule.posX[capsule.bodySlot(rod)] > -0.08) throw 'fast capsule crossed planar wall';

        var solid = new World(4, 4);
        solid.gravity = new Vec3();
        wall = solid.createBody(BodyType.Static, 0, 0);
        solid.attachShape(wall, ShapeBuilder.makeBox(solid.verts, 0.025, 2, 2, 0));
        var block = solid.createBody(BodyType.Dynamic, -2, 0);
        solid.attachShape(block, ShapeBuilder.makeBox(solid.verts, 0.1, 0.1, 0.2, 0));
        solid.velX[solid.bodySlot(block)] = 600;
        solid.step(1.0 / 60.0);
        if (solid.posX[solid.bodySlot(block)] > -0.08) throw 'fast box crossed volumetric wall';

        var miss = new World(4, 4);
        miss.gravity = new Vec3();
        wall = miss.createBody(BodyType.Static, 0, 0);
        miss.attachShape(wall, ShapeBuilder.makeBox(miss.verts, 0.025, 2, 0, 0));
        var passing = miss.createBody(BodyType.Dynamic, -2, 3);
        miss.attachShape(passing, ShapeBuilder.makeCircle(0.1));
        miss.velX[miss.bodySlot(passing)] = 600;
        miss.step(1.0 / 60.0);
        near(miss.posX[miss.bodySlot(passing)], 8, 'CCD miss stays a miss', 0.01);

        var filteredSweep = new World(4, 4);
        filteredSweep.gravity = new Vec3();
        wall = filteredSweep.createBody(BodyType.Static, 0, 0);
        filteredSweep.attachShape(wall, ShapeBuilder.makeBox(filteredSweep.verts, 0.025, 2, 0, 0), 1, 0);
        var filteredBody = filteredSweep.createBody(BodyType.Dynamic, -2, 0);
        filteredSweep.attachShape(filteredBody, ShapeBuilder.makeCircle(0.1), 2, 2);
        filteredSweep.velX[filteredSweep.bodySlot(filteredBody)] = 600;
        filteredSweep.step(1.0 / 60.0);
        near(filteredSweep.posX[filteredSweep.bodySlot(filteredBody)], 8, 'CCD collision filter', 0.01);

        var overlap = new World(4, 4);
        overlap.gravity = new Vec3();
        wall = overlap.createBody(BodyType.Static, 0, 0);
        overlap.attachShape(wall, ShapeBuilder.makeBox(overlap.verts, 0.025, 2, 0, 0));
        var embedded = overlap.createBody(BodyType.Dynamic, 0, 0);
        overlap.attachShape(embedded, ShapeBuilder.makeCircle(0.1));
        overlap.setBullet(embedded, true);
        overlap.velX[overlap.bodySlot(embedded)] = 600;
        overlap.step(1.0 / 60.0);
        if (!Math.isFinite(overlap.posX[overlap.bodySlot(embedded)])
            || !Math.isFinite(overlap.velX[overlap.bodySlot(embedded)])) throw 'CCD overlap became non-finite';

        var graze = new World(4, 4);
        graze.gravity = new Vec3();
        wall = graze.createBody(BodyType.Static, 0, 0);
        graze.attachShape(wall, ShapeBuilder.makeBox(graze.verts, 0.025, 2, 0, 0));
        var skimming = graze.createBody(BodyType.Dynamic, -2, 2.2);
        graze.attachShape(skimming, ShapeBuilder.makeCircle(0.1));
        graze.setBullet(skimming, true);
        graze.velX[graze.bodySlot(skimming)] = 600;
        graze.step(1.0 / 60.0);
        near(graze.posX[graze.bodySlot(skimming)], 8, 'CCD grazing miss', 0.01);

        var bilateral = new World(4, 4);
        bilateral.gravity = new Vec3();
        var left = bilateral.createBody(BodyType.Dynamic, -2, 0);
        var right = bilateral.createBody(BodyType.Dynamic, 2, 0);
        bilateral.attachShape(left, ShapeBuilder.makeCircle(0.1));
        bilateral.attachShape(right, ShapeBuilder.makeCircle(0.1));
        bilateral.velX[bilateral.bodySlot(left)] = 600;
        bilateral.velX[bilateral.bodySlot(right)] = -600;
        bilateral.step(1.0 / 60.0);
        if (bilateral.posX[bilateral.bodySlot(left)] > bilateral.posX[bilateral.bodySlot(right)])
            throw 'bilateral CCD bodies passed through each other';

        var bounce = new World(6, 6);
        bounce.gravity = new Vec3();
        var leftWall = bounce.createBody(BodyType.Static, 0, 0);
        var rightWall = bounce.createBody(BodyType.Static, 4, 0);
        bounce.attachShape(leftWall, ShapeBuilder.makeBox(bounce.verts, 0.025, 2, 0, 0));
        bounce.attachShape(rightWall, ShapeBuilder.makeBox(bounce.verts, 0.025, 2, 0, 0));
        var ricochet = bounce.createBody(BodyType.Dynamic, 2, 0);
        bounce.attachShape(ricochet, ShapeBuilder.makeCircle(0.1), 1, -1, 0, 0, 1);
        bounce.setBullet(ricochet, true);
        bounce.velX[bounce.bodySlot(ricochet)] = 2000;
        bounce.step(1.0 / 60.0);
        var bouncedX = bounce.posX[bounce.bodySlot(ricochet)];
        if (bouncedX <= 0.1 || bouncedX >= 3.9 || !Math.isFinite(bounce.velX[bounce.bodySlot(ricochet)]))
            throw 'CCD skipped a later wall impact: x=$bouncedX';
        if (bounce.toi.resolvedImpacts < 2) throw 'CCD did not resolve successive impacts';

        var explicit = new World(4, 4);
        explicit.gravity = new Vec3();
        wall = explicit.createBody(BodyType.Static, 0, 0);
        explicit.attachShape(wall, ShapeBuilder.makeBox(explicit.verts, 0.025, 2, 0, 0));
        var slowBox = explicit.createBody(BodyType.Dynamic, -0.7, 0);
        explicit.attachShape(slowBox, ShapeBuilder.makeBox(explicit.verts, 0.5, 0.5, 0, 0));
        explicit.setBullet(slowBox, true);
        explicit.velX[explicit.bodySlot(slowBox)] = 24;
        explicit.step(1.0 / 60.0);
        if (explicit.posX[explicit.bodySlot(slowBox)] > -0.5) throw 'explicit bullet crossed wall';

        var crossing = new World(4, 4);
        crossing.gravity = new Vec3();
        var horizontal = crossing.createBody(BodyType.Dynamic, -2, 0);
        var vertical = crossing.createBody(BodyType.Dynamic, 0, -2);
        crossing.attachShape(horizontal, ShapeBuilder.makeCircle(0.1));
        crossing.attachShape(vertical, ShapeBuilder.makeCircle(0.1));
        crossing.velX[crossing.bodySlot(horizontal)] = 960;
        crossing.velY[crossing.bodySlot(vertical)] = 960;
        var crossingHit = crossing.toi.findEarliest(1.0 / 240.0, 1.0 / 60.0);
        if (crossingHit == null) throw 'bilateral swept proxies missed crossing paths';
        near(crossingHit.fraction, 0.4646, 'bilateral crossing fraction', 0.01);
    }

    static function checkKinematicTargets():Void {
        var planar = new World(8, 8);
        planar.gravity = new Vec3();
        var platform = planar.createBody(BodyType.Kinematic, 0, 0);
        var platformShape = planar.attachShape(platform, ShapeBuilder.makeBox(planar.verts, 1, 0.2, 0, 0));
        var angle:Single = Math.PI * 0.25;
        planar.setKinematicTarget(platform, new Vec3(2, 1), new Quat(0, 0, Math.sin(angle), Math.cos(angle)));
        var before = planar.getBodyTransform(platform);
        near(before.position.x, 0, 'kinematic target deferred');
        planar.step(1.0 / 60.0);
        var pose = planar.getBodyTransform(platform);
        near(pose.position.x, 2, 'kinematic target x');
        near(pose.position.y, 1, 'kinematic target y');
        near(pose.rotation.z, Math.sin(angle), 'kinematic target rotation', 0.001);
        near(planar.velX[planar.bodySlot(platform)], 0, 'kinematic target velocity cleared');
        var inside:Array<ShapeId> = [];
        planar.queryAABB(new Vec3(1.9, 1.8, 0), new Vec3(2.1, 2.0, 0), -1,
            function(shape) { inside.push(shape); return true; });
        if (inside.length != 1 || inside[0] != platformShape) throw 'kinematic rotated proxy did not reach target';
        inside = [];
        planar.queryAABB(new Vec3(2.8, 0.9, 0), new Vec3(3.0, 1.1, 0), -1,
            function(shape) { inside.push(shape); return true; });
        if (inside.length != 0) throw 'kinematic rotated proxy retained old bounds';
        planar.step(1.0 / 60.0);
        near(planar.getBodyTransform(platform).position.x, 2, 'kinematic target holds after step');
        mustThrow(function() planar.setKinematicTarget(platform, new Vec3(), new Quat(0, 0, 0, 0)), 'zero target quaternion');

        var push = new World(8, 8);
        push.gravity = new Vec3();
        var pusher = push.createBody(BodyType.Kinematic, -1, 0);
        push.attachShape(pusher, ShapeBuilder.makeCircle(0.5));
        var pushed = push.createBody(BodyType.Dynamic, 0, 0);
        push.attachShape(pushed, ShapeBuilder.makeCircle(0.5));
        push.setKinematicTarget(pusher, new Vec3(0.25, 0), new Quat());
        push.step(1.0 / 60.0);
        if (push.velX[push.bodySlot(pushed)] <= 0.1) throw 'moving kinematic collider did not transfer motion';
        var pushedPose = push.getBodyTransform(pushed);
        near(pushedPose.position.x, push.posX[push.bodySlot(pushed)], 'dynamic transform readback');
        pushedPose.position.x = 100;
        if (push.posX[push.bodySlot(pushed)] == 100) throw 'transform readback aliased body state';
        mustThrow(function() push.setKinematicTarget(pushed, new Vec3(), new Quat()), 'dynamic kinematic target');
        push.teleportBody(pushed, new Vec3(5, 0), new Quat());
        near(push.velX[push.bodySlot(pushed)], 0, 'dynamic teleport clears velocity');
        push.step(1.0 / 60.0);
        near(push.getBodyTransform(pushed).position.x, 5, 'dynamic teleport stays fixed');

        var rotating = new World(8, 8);
        rotating.gravity = new Vec3();
        var paddle = rotating.createBody(BodyType.Kinematic, 0, 0, 0);
        rotating.attachShape(paddle, ShapeBuilder.makeBox(rotating.verts, 1, 0.15, 0.3, 0));
        var bead = rotating.createBody(BodyType.Dynamic, 0.75, 0.75, 0);
        rotating.attachShape(bead, ShapeBuilder.makeCircle(0.2, 0.3));
        // Turns a quarter turn over several steps, so the paddle's face meets the bead rather than appearing inside it.
        for (step in 1...7) {
            var half = angle * step / 6;
            rotating.setKinematicTarget(paddle, new Vec3(), new Quat(0, 0, Math.sin(half), Math.cos(half)));
            rotating.step(1.0 / 60.0);
        }
        var beadSlot = rotating.bodySlot(bead);
        var beadSpeed = Math.sqrt(rotating.velX[beadSlot] * rotating.velX[beadSlot]
            + rotating.velY[beadSlot] * rotating.velY[beadSlot]);
        if (beadSpeed <= 0.1) throw 'rotating kinematic collider did not transfer motion';

        var linked = new World(8, 8, 2);
        linked.gravity = new Vec3();
        var driver = linked.createBody(BodyType.Kinematic, 0, 0);
        linked.attachShape(driver, ShapeBuilder.makeCircle(0.2));
        var follower = linked.createBody(BodyType.Dynamic, 1, 0);
        linked.attachShape(follower, ShapeBuilder.makeCircle(0.2));
        linked.createDistanceJoint(driver, follower, 1);
        for (i in 0...90) linked.step(1.0 / 60.0);
        if (linked.islands.isAwake[linked.bodySlot(follower)] != 0) throw 'joint follower failed to sleep';
        linked.setKinematicTarget(driver, new Vec3(0.2, 0), new Quat());
        linked.step(1.0 / 60.0);
        if (linked.islands.isAwake[linked.bodySlot(follower)] == 0) throw 'kinematic target did not wake joint neighbor';

        var spatial = new World(4, 4);
        spatial.gravity = new Vec3();
        var cube = spatial.createBody(BodyType.Kinematic, 0, 0, 0);
        spatial.attachShape(cube, ShapeBuilder.makeBox(spatial.verts, 0.4, 0.2, 0.6, 0));
        spatial.setKinematicTarget(cube, new Vec3(1, 2, 3),
            new Quat(0, Math.sin(angle), 0, Math.cos(angle)));
        spatial.step(1.0 / 60.0);
        var cubePose = spatial.getBodyTransform(cube);
        near(cubePose.position.z, 3, '3D kinematic target z');
        near(cubePose.rotation.y, Math.sin(angle), '3D kinematic target rotation', 0.001);
        spatial.teleportBody(cube, new Vec3(4, 5, 6), new Quat());
        near(spatial.velX[spatial.bodySlot(cube)], 0, 'teleport linear velocity');
        near(spatial.angVelY[spatial.bodySlot(cube)], 0, 'teleport angular velocity');
        spatial.step(1.0 / 60.0);
        cubePose = spatial.getBodyTransform(cube);
        near(cubePose.position.x, 4, 'teleport x stays fixed');
        near(cubePose.position.z, 6, 'teleport z stays fixed');
        mustThrow(function() spatial.setKinematicTarget((cube + (1 << 20)), new Vec3(), new Quat()), 'stale kinematic body');
    }

    /** Checks many kinematic targets per step through the buffers, without allocating. */
    static function checkKinematicBulk():Void {
        var world = new World(128, 128);
        world.gravity = new Vec3();
        var slots:Array<Int> = [];
        for (i in 0...100) {
            var body = world.createBody(BodyType.Kinematic, i * 2, 0);
            world.attachShape(body, ShapeBuilder.makeCircle(0.4));
            slots.push(world.bodySlot(body));
        }
        inline function push(frame:Int):Void {
            for (i in 0...slots.length) {
                var slot = slots[i], angle = frame * 0.01 + i * 0.1;
                world.targetX[slot] = i * 2 + frame * 0.01; world.targetY[slot] = Math.sin(angle); world.targetZ[slot] = 0;
                world.targetQx[slot] = 0; world.targetQy[slot] = 0;
                world.targetQz[slot] = Math.sin(angle * 0.5) * 3; world.targetQw[slot] = Math.cos(angle * 0.5) * 3;
                world.commitKinematicTarget(slot);
            }
        }
        for (frame in 0...200) { push(frame); world.step(1.0 / 60.0); }
        var allocated = Allocation.least(() -> for (frame in 200...300) { push(frame); world.step(1.0 / 60.0); });
        if (allocated > 512) throw 'kinematic targets allocated $allocated bytes';
        var slot = slots[7], angle = 299 * 0.01 + 7 * 0.1;
        near(world.posX[slot], 14 + 2.99, 'bulk target x');
        near(world.posY[slot], Math.sin(angle), 'bulk target y');
        near(world.rotZ[slot], Math.sin(angle * 0.5), 'bulk target rotation normalised', 0.001);
        world.targetQw[slot] = Math.NaN;
        mustThrow(function() world.commitKinematicTarget(slot), 'non-finite bulk target');
        var x = world.posX[slot];
        world.step(1.0 / 60.0);
        near(world.posX[slot], x, 'rejected bulk target is not applied');
    }

    static function checkBodyTypeSwitch():Void {
        var world = new World(8, 8, 4);
        var floor = world.createBody(BodyType.Static, 0, -0.5);
        world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 5, 0.5));
        var box = world.createBody(BodyType.Kinematic, 0, 3);
        world.attachShape(box, ShapeBuilder.makeBox(world.verts, 0.25, 0.25));
        var slot = world.bodySlot(box);
        for (i in 0...30) world.step(1.0 / 60.0);
        near(world.posY[slot], 3, 'kinematic box holds');
        if (world.invMassX[slot] != 0) throw 'kinematic box has mass';

        // When a body moves under a target and then turns dynamic, it keeps that motion, falls, and
        // lands on the floor.
        world.setKinematicTarget(box, new Vec3(0.025, 3), new Quat());
        world.step(1.0 / 60.0);
        world.setBodyType(box, BodyType.Dynamic);
        if (world.bodyDoF[slot] != DoFMask.Planar || world.invMassX[slot] <= 0) throw 'switched box has no planar mass';
        near(world.velX[slot], 1.5, 'switch keeps the last target motion', 0.001);
        world.step(1.0 / 60.0);
        if (world.posX[slot] < 0.02 || world.posY[slot] >= 3) throw 'switched box did not keep its velocity or fall';
        for (i in 0...120) world.step(1.0 / 60.0);
        near(world.posY[slot], 0.25, 'switched box landed', 0.05);

        // Each kinematic body that held still in the last step switches at rest.
        var still = world.createBody(BodyType.Kinematic, -3, 2);
        world.attachShape(still, ShapeBuilder.makeCircle(0.2));
        world.setKinematicTarget(still, new Vec3(-2.9, 2), new Quat());
        world.step(1.0 / 60.0);
        world.step(1.0 / 60.0);
        world.setBodyType(still, BodyType.Dynamic);
        near(world.velX[world.bodySlot(still)], 0, 'switch after holding is at rest');

        // When the body turns kinematic again, it stops where it is and follows targets again.
        var x = world.posX[slot];
        world.setBodyType(box, BodyType.Kinematic);
        world.step(1.0 / 60.0);
        near(world.posX[slot], x, 'kinematic again holds', 0.0001);
        world.setKinematicTarget(box, new Vec3(x, 2), new Quat());
        world.step(1.0 / 60.0);
        near(world.posY[slot], 2, 'kinematic again follows targets');

        // Each volumetric body regains full 3D freedom. Each joint left between two kinematic bodies is
        // inert.
        var cube = world.createBody(BodyType.Kinematic, 3, 2, 0);
        world.attachShape(cube, ShapeBuilder.makeBox(world.verts, 0.2, 0.2, 0.2, 0));
        var arm = world.createBody(BodyType.Dynamic, 3, 1, 0);
        world.attachShape(arm, ShapeBuilder.makeBox(world.verts, 0.1, 0.4, 0.1, 0));
        world.createSphericalJoint(cube, arm, new Vec3(3, 1.5, 0));
        world.setBodyType(arm, BodyType.Kinematic);
        for (i in 0...10) world.step(1.0 / 60.0);
        near(world.posY[world.bodySlot(arm)], 1, 'kinematic pair joint inert');
        world.setBodyType(cube, BodyType.Dynamic);
        if (world.bodyDoF[world.bodySlot(cube)] != DoFMask.Full3D) throw 'switched cube is not volumetric';
        world.setBodyType(arm, BodyType.Dynamic);
        world.setBodyType(cube, BodyType.Static);
        for (i in 0...60) world.step(1.0 / 60.0);
        var armSlot = world.bodySlot(arm);
        var dy = world.posY[armSlot] - 1.5, dx = world.posX[armSlot] - 3;
        near(Math.sqrt(dx * dx + dy * dy), 0.5, 'joint holds the arm once one body is dynamic', 0.05);
    }

    static function checkLifecycle():Void {
        var blocks = new VertexPool(8);
        var small = blocks.allocateBlock(2);
        blocks.retainBlock(small);
        var large = blocks.allocateBlock(4);
        blocks.retainBlock(large);
        blocks.releaseBlock(small);
        blocks.releaseBlock(large);
        near(blocks.allocateBlock(8), 0, 'vertex padding coalescence');

        var world = new World(4, 4, 2);
        world.gravity = new Vec3();
        var anchor = world.createBody(BodyType.Static, 0, 0);
        var oldBody = world.createBody(BodyType.Dynamic, 0, 0);
        var oldShape = world.attachShape(oldBody, ShapeBuilder.makeCircle(0.5));
        var oldExtra = world.attachShape(oldBody, ShapeBuilder.makeCircle(0.2));
        var other = world.createBody(BodyType.Dynamic, 0.8, 0);
        world.attachShape(other, ShapeBuilder.makeCircle(0.5));
        var oldJoint = world.createDistanceJoint(anchor, oldBody, 0.0);
        world.step(1.0 / 60.0);
        if (world.contacts.count == 0) throw 'lifecycle contact setup failed';
        world.destroyBody(oldBody);
        near(world.activeBodyCount, 2, 'body count after destruction');
        near(world.activeShapeCount, 1, 'shape count after body destruction');
        near(world.joints.count, 0, 'body destruction removed joint');
        near(world.contacts.count, 0, 'body destruction removed contacts');
        near(world.broadPhase.nodeCount, 1, 'body destruction removed proxy');
        for (position in 0...world.activeBodyCount) {
            var active = world.bodyHandleAt(position);
            if (active == oldBody) throw 'destroyed body remained active';
            world.bodySlot(active);
        }
        for (position in 0...world.activeShapeCount) {
            var active = world.shapeHandleAt(position);
            if (active == oldShape || active == oldExtra) throw 'destroyed shape remained active';
            world.shapeSlot(active);
        }
        mustThrow(function() world.bodySlot(oldBody), 'body slot');
        mustThrow(function() world.wakeBody(oldBody), 'wake body');
        mustThrow(function() world.setBullet(oldBody, true), 'bullet body');
        mustThrow(function() world.attachShape(oldBody, ShapeBuilder.makeCircle(0.1)), 'attach shape');
        mustThrow(function() world.getShapeDef(oldShape), 'shape definition');
        mustThrow(function() world.destroyShape(oldShape), 'destroy shape');
        mustThrow(function() world.destroyShape(oldExtra), 'destroy compound shape');
        mustThrow(function() world.createDistanceJoint(anchor, oldBody, 1.0), 'joint body');
        mustThrow(function() world.destroyJoint(oldJoint), 'joint after body destruction');
        world.step(1.0 / 60.0);
        for (cycle in 0...24) {
            var body = world.createBody(BodyType.Dynamic, 4, 0);
            var shape = world.attachShape(body, ShapeBuilder.makeCircle(0.25));
            near(world.bodySlot(body), oldBody & ((1 << 20) - 1), 'recycled body slot');
            near(world.shapeSlot(shape), oldShape & ((1 << 20) - 1), 'recycled shape slot');
            if (body == oldBody || shape == oldShape) throw 'recycled handle retained old generation';
            mustThrow(function() world.bodySlot(oldBody), 'body after slot reuse');
            mustThrow(function() world.shapeSlot(oldShape), 'shape after slot reuse');
            world.step(1.0 / 60.0);
            world.destroyBody(body);
            near(world.broadPhase.nodeCount, 1, 'proxy count under churn');
            near(world.activeBodyCount, 2, 'active body count under churn');
            near(world.activeShapeCount, 1, 'active shape count under churn');
        }
        var recycled = world.createBody(BodyType.Dynamic, 3, 0);
        var attached = world.attachShape(recycled, ShapeBuilder.makeCircle(0.2));
        world.destroyShape(attached);
        near(world.bodyDoF[world.bodySlot(recycled)], DoFMask.Locked, 'shape removal resets DoF');
        near(world.activeShapeCount, 1, 'standalone shape destruction');
        mustThrow(function() world.destroyBody(oldBody), 'destroy body');

        var geometry = new World(2, 2, 0);
        geometry.gravity = new Vec3();
        var owner = geometry.createBody(BodyType.Dynamic, 0, 0);
        var template = ShapeBuilder.makeBox(geometry.verts, 0.25, 0.25);
        for (cycle in 0...24) {
            var def = cycle % 2 == 0 ? template
                : ShapeBuilder.makeSegment(geometry.verts, -0.25, 0, 0.25, 0);
            var shape = geometry.attachShape(owner, def);
            geometry.step(1.0 / 60.0);
            geometry.destroyShape(shape);
            near(geometry.activeShapeCount, 0, 'vertex churn shape count');
            near(geometry.verts.count, 4, 'vertex blocks reused');
        }
        var first = geometry.attachShape(owner, template);
        var copied = geometry.getShapeDef(first);
        var secondBody = geometry.createBody(BodyType.Dynamic, 2, 0);
        var second = geometry.attachShape(secondBody, copied);
        geometry.destroyShape(first);
        geometry.step(1.0 / 60.0);
        near(geometry.activeShapeCount, 1, 'shared vertex block stays live');
        geometry.destroyShape(second);
        var rebuilt = geometry.attachShape(owner, copied);
        geometry.step(1.0 / 60.0);
        geometry.destroyShape(rebuilt);
    }

    static function checkTreeNode(tree:BroadPhase, node:Int, expectedParent:Int):Int {
        if (tree.parent[node] != expectedParent) throw 'broad-phase parent link';
        var left = tree.child1[node], right = tree.child2[node];
        if (left == BroadPhase.NULL_NODE) {
            if (right != BroadPhase.NULL_NODE || tree.height[node] != 0) throw 'broad-phase leaf';
            return 1;
        }
        if (right == BroadPhase.NULL_NODE) throw 'broad-phase missing child';
        var leftLeaves = checkTreeNode(tree, left, node);
        var rightLeaves = checkTreeNode(tree, right, node);
        if (tree.height[node] != 1 + Std.int(Math.max(tree.height[left], tree.height[right])))
            throw 'broad-phase height';
        var offset = node * 6, lo = left * 6, ro = right * 6;
        for (axis in 0...3) {
            near(tree.aabb[offset + axis], Math.min(tree.aabb[lo + axis], tree.aabb[ro + axis]), 'broad-phase lower bound');
            near(tree.aabb[offset + axis + 3], Math.max(tree.aabb[lo + axis + 3], tree.aabb[ro + axis + 3]), 'broad-phase upper bound');
        }
        return leftLeaves + rightLeaves;
    }

    static function checkBroadPhaseTree():Void {
        var count = 256;
        var tree = new BroadPhase(count * 2, 16);
        var proxies = new hxn.Int32Buffer(count);
        var bodies = new hxn.Int32Buffer(count);
        var types = new hxn.Int32Buffer(count);
        var categories = new hxn.Int32Buffer(count);
        var masks = new hxn.Int32Buffer(count);
        var groups = new hxn.Int32Buffer(count);
        for (i in 0...count) {
            proxies[i] = tree.createProxy(i * 3.0, 0, 0, i * 3.0 + 1, 1, 1, i);
            bodies[i] = i;
            types[i] = BodyType.Dynamic;
            categories[i] = masks[i] = 1;
            groups[i] = 0;
        }
        if (tree.height[tree.root] > 20 || checkTreeNode(tree, tree.root, BroadPhase.NULL_NODE) != count)
            throw 'broad-phase tree did not balance';
        tree.findPairs(count, proxies, bodies, types, categories, masks, groups);
        near(tree.pairCount, 0, 'separated broad-phase pairs');
        tree.updateProxy(proxies[1], 0.5, 0, 0, 1.5, 1, 1);
        tree.findPairs(count, proxies, bodies, types, categories, masks, groups);
        near(tree.pairCount, 1, 'moved broad-phase pair');
        if (tree.pairs[0] != 0 || tree.pairs[1] != 1) throw 'moved broad-phase pair ids';
        if (tree.height[tree.root] > 20 || checkTreeNode(tree, tree.root, BroadPhase.NULL_NODE) != count)
            throw 'broad-phase tree lost balance after move';
    }

    static function checkSoftStepMaterials():Void {
        var sticky = new World(8, 8);
        var slick = new World(8, 8);
        for (scene in [sticky, slick]) {
            var coefficient:Single = scene == sticky ? 0.8 : 0.0;
            var floor = scene.createBody(BodyType.Static, 0, 0);
            scene.attachShape(floor, ShapeBuilder.makeBox(scene.verts, 20, 0.5), 1, -1, 0, coefficient);
            var box = scene.createBody(BodyType.Dynamic, 0, 1.01);
            scene.attachShape(box, ShapeBuilder.makeBox(scene.verts, 0.5, 0.5), 1, -1, 0, coefficient);
            scene.velX[box] = 3.0;
            for (step in 0...120) scene.step(1.0 / 60.0);
        }
        if (Math.abs(sticky.velX[1]) >= Math.abs(slick.velX[1]) - 0.5)
            throw 'contact friction did not reduce sliding speed';
        near(slick.velX[1], 3.0, 'frictionless sliding speed', 0.1);

        var bouncing = new World(8, 8);
        bouncing.gravity = new Vec3();
        var ground = bouncing.createBody(BodyType.Static, 0, 0);
        bouncing.attachShape(ground, ShapeBuilder.makeBox(bouncing.verts, 5, 0.5), 1, -1, 0, 0.0, 1.0);
        var ball = bouncing.createBody(BodyType.Dynamic, 0, 1.7);
        bouncing.attachShape(ball, ShapeBuilder.makeCircle(0.5), 1, -1, 0, 0.0, 1.0);
        bouncing.velY[ball] = -5.0;
        var upward = 0.0;
        for (step in 0...40) {
            bouncing.step(1.0 / 60.0);
            upward = Math.max(upward, bouncing.velY[ball]);
        }
        if (upward < 2.0) throw 'contact restitution did not rebound';
    }

    static function checkIndependentContactBatch():Void {
        var world = new World(12, 12);
        world.gravity = new Vec3();
        var floor = world.createBody(BodyType.Static, 3.75, 0);
        world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 6, 0.5));
        for (i in 0...4) {
            var x = i * 2.5;
            var ball = world.createBody(BodyType.Dynamic, x, 0.95);
            world.attachShape(ball, ShapeBuilder.makeCircle(0.5));
            world.velY[ball] = -1.0;
        }
        world.step(1.0 / 60.0);
        #if (ash_simd && !solver_scalar_bench)
        if (world.solver.packedBatches == 0) throw 'independent contacts were not SIMD batched';
        #end
        for (i in 0...4) {
            if (world.velY[i + 1] <= -0.5) throw 'batched contact did not resolve';
            near(world.velY[i + 1], world.velY[1], 'independent contact parity', 0.001);
        }
        near(world.velX[floor], 0, 'static floor x velocity');
        near(world.velY[floor], 0, 'static floor y velocity');
    }

    static function check3DStack():Void {
        var world = new World(8, 8);
        var floor = world.createBody(BodyType.Static, 0, 0);
        world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 3, 0.5, 2));
        var lower = world.createBody(BodyType.Dynamic, 0, 1.05);
        world.attachShape(lower, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 0.5));
        var upper = world.createBody(BodyType.Dynamic, 0, 2.07);
        world.attachShape(upper, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 0.5));
        for (step in 0...120) world.step(1.0 / 60.0);
        near(world.posY[lower], 1.0, '3D stack lower height', 0.12);
        near(world.posY[upper], 2.0, '3D stack upper height', 0.2);
        if (!Math.isFinite(world.rotX[upper]) || !Math.isFinite(world.rotY[upper])
            || !Math.isFinite(world.rotZ[upper]) || !Math.isFinite(world.rotW[upper]))
            throw '3D stack rotation became non-finite';
    }

    static function contactImpulse(world:World, body:Int):Float {
        var sum = 0.0;
        for (c in 0...world.contacts.count)
            if (world.contacts.bodyA[c] == body || world.contacts.bodyB[c] == body) sum += world.contacts.normalImpulse[c];
        return sum;
    }

    static function touches(world:World, shapeSlot:Int):Bool {
        for (c in 0...world.contacts.count)
            if (world.contacts.shapeA[c] == shapeSlot || world.contacts.shapeB[c] == shapeSlot) return true;
        return false;
    }

    static function checkLocalContactInvalidation():Void {
        var world = new World(8, 8);
        var floor = world.createBody(BodyType.Static, 0, -0.5);
        world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 10, 0.5));
        var moved = world.createBody(BodyType.Dynamic, -4, 0.5);
        var movedShape = world.attachShape(moved, ShapeBuilder.makeBox(world.verts, 0.5, 0.5));
        var resting = world.createBody(BodyType.Dynamic, 4, 0.5);
        world.attachShape(resting, ShapeBuilder.makeBox(world.verts, 0.5, 0.5));
        for (_ in 0...20) world.step(1.0 / 60.0);
        var restingSlot = world.bodySlot(resting);
        var before = contactImpulse(world, restingSlot);
        if (before <= 0.0) throw 'resting box carries no contact impulse';
        world.teleportBody(moved, new Vec3(-4, 3), new Quat());
        near(contactImpulse(world, restingSlot), before, 'teleport keeps unrelated warm-start impulses', 1e-9);
        near(contactImpulse(world, world.bodySlot(moved)), 0, 'teleported body contacts');
        world.step(1.0 / 60.0);
        before = contactImpulse(world, restingSlot);
        var slot = world.shapeSlot(movedShape);
        world.destroyShape(movedShape);
        near(contactImpulse(world, restingSlot), before, 'shape destruction keeps unrelated impulses', 1e-9);
        if (touches(world, slot)) throw 'destroyed shape left contacts behind';
    }

    static function checkShapeToggle():Void {
        var world = new World(8, 8);
        var platform = world.createBody(BodyType.Kinematic, 0, 0);
        var deck = world.attachShape(platform, ShapeBuilder.makeBox(world.verts, 2, 0.25));
        var ball = world.createBody(BodyType.Dynamic, 0, 0.55);
        world.attachShape(ball, ShapeBuilder.makeCircle(0.3));
        for (_ in 0...30) world.step(1.0 / 60.0);
        near(world.posY[world.bodySlot(ball)], 0.55, 'ball resting on the deck', 0.03);
        world.setShapeEnabled(deck, false);
        if (world.isShapeEnabled(deck)) throw 'deck still enabled';
        if (touches(world, world.shapeSlot(deck))) throw 'disabled deck kept its contacts';
        var found = false;
        world.queryAABB(new Vec3(-3, -1, -1), new Vec3(3, 1, 1), -1, function(s) {
            if (s == deck) found = true;
            return true;
        });
        if (found) throw 'disabled deck still answers queries';
        for (_ in 0...30) world.step(1.0 / 60.0);
        if (world.posY[world.bodySlot(ball)] > -0.5) throw 'ball did not fall through the disabled deck';
        world.teleportBody(ball, new Vec3(0, 1.5), new Quat());
        world.setShapeEnabled(deck, true);
        for (_ in 0...60) world.step(1.0 / 60.0);
        near(world.posY[world.bodySlot(ball)], 0.55, 'ball lands on the re-enabled deck', 0.03);
        for (_ in 0...4) { world.setShapeEnabled(deck, false); world.setShapeEnabled(deck, true); }
        var allocated = Allocation.least(() -> for (_ in 0...100) { world.setShapeEnabled(deck, false); world.setShapeEnabled(deck, true); });
        if (allocated > 512) throw 'shape toggling allocated $allocated bytes';
    }

    static function sameTopology(world:World, shape:ShapeId, label:String):Void {
        var kept = world.shapeTopology[world.shapeSlot(shape)];
        var fresh = ManifoldClipper.buildTopology(world.verts, world.getShapeDef(shape));
        near(kept.points.length, fresh.points.length, '$label topology points');
        for (i in 0...fresh.points.length) {
            near(kept.points[i].x, fresh.points[i].x, '$label point $i x');
            near(kept.points[i].y, fresh.points[i].y, '$label point $i y');
            near(kept.points[i].z, fresh.points[i].z, '$label point $i z');
        }
        near(kept.faces.length, fresh.faces.length, '$label topology faces');
        for (i in 0...fresh.faces.length) {
            if (kept.faces[i].indices.join(',') != fresh.faces[i].indices.join(',')) throw '$label face $i indices differ';
            near(kept.faces[i].normal.x, fresh.faces[i].normal.x, '$label face $i normal x');
            near(kept.faces[i].normal.y, fresh.faces[i].normal.y, '$label face $i normal y');
            near(kept.faces[i].normal.z, fresh.faces[i].normal.z, '$label face $i normal z');
        }
    }

    static function checkShapeReshape():Void {
        var world = new World(8, 8);
        var lift = world.createBody(BodyType.Kinematic, 0, 0);
        var def = ShapeBuilder.makeBox(world.verts, 2, 0.2);
        var deck = world.attachShape(lift, def);
        var twin = world.createBody(BodyType.Static, 10, 0);
        var twinDeck = world.attachShape(twin, def);
        var ball = world.createBody(BodyType.Dynamic, 0, 0.5);
        world.attachShape(ball, ShapeBuilder.makeCircle(0.3));
        for (_ in 0...20) world.step(1.0 / 60.0);
        for (frame in 0...60) {
            var top = 0.2 + 0.4 * (frame + 1) / 60.0;
            world.setShapeVertices(deck, [new Vec3(-2, -0.2), new Vec3(2, -0.2), new Vec3(2, top), new Vec3(-2, top)]);
            world.step(1.0 / 60.0);
        }
        for (_ in 0...30) world.step(1.0 / 60.0);
        near(world.posY[world.bodySlot(ball)], 0.6 + 0.3, 'ball rides a reshaped deck', 0.04);
        sameTopology(world, deck, 'in-place reshape');
        // Reversing the winding takes the rebuild path. The result must also match a freshly built shape.
        world.setShapeVertices(deck, [new Vec3(-2, 0.6), new Vec3(2, 0.6), new Vec3(2, -0.2), new Vec3(-2, -0.2)]);
        sameTopology(world, deck, 'reshape with reversed winding');
        world.setShapeVertices(deck, [new Vec3(-2, -0.2), new Vec3(2, -0.2), new Vec3(2, 0.6), new Vec3(-2, 0.6)]);
        var twinDef = world.getShapeDef(twinDeck);
        near(world.verts.vy[twinDef.vertOffset + 2], 0.2, 'shared descriptor keeps its geometry');
        var later = world.attachShape(world.createBody(BodyType.Static, -10, 0), def);
        near(world.verts.vy[world.getShapeDef(later).vertOffset + 2], 0.2, 'later attachments keep the original geometry');
        mustThrow(function() world.setShapeVertices(deck, [new Vec3(0, 0), new Vec3(1, 0), new Vec3(0, 1)]),
            'reshape with a new vertex count');
        mustThrow(function() world.setShapeVertices(deck, [new Vec3(-2, -0.2), new Vec3(2, -0.2), new Vec3(-2, 0.5), new Vec3(2, 0.5)]),
            'reshape into a crossed polygon');
        var hullWorld = new World(4, 4);
        var hullLift = hullWorld.createBody(BodyType.Kinematic, 0, 0, 0);
        inline function slab(top:Float):Array<Vec3> return [
            new Vec3(-1, -0.2, -1), new Vec3(1, -0.2, -1), new Vec3(1, -0.2, 1), new Vec3(-1, -0.2, 1),
            new Vec3(-1, top, -1), new Vec3(1, top, -1), new Vec3(1, top, 1), new Vec3(-1, top, 1)];
        var hullDeck = hullWorld.attachShape(hullLift, ShapeBuilder.makeHull(hullWorld.verts, slab(0.2)));
        var crate = hullWorld.createBody(BodyType.Dynamic, 0, 0.55, 0);
        hullWorld.attachShape(crate, ShapeBuilder.makeBox(hullWorld.verts, 0.3, 0.3, 0.6));
        for (_ in 0...20) hullWorld.step(1.0 / 60.0);
        for (frame in 0...60) {
            hullWorld.setShapeVertices(hullDeck, slab(0.2 + 0.4 * (frame + 1) / 60.0));
            hullWorld.step(1.0 / 60.0);
        }
        for (_ in 0...30) hullWorld.step(1.0 / 60.0);
        var crateSlot = hullWorld.bodySlot(crate);
        near(hullWorld.posY[crateSlot], 0.6 + 0.3, 'crate rides a reshaped hull', 0.05);
        near(hullWorld.posX[crateSlot], 0, 'crate stays centred on the hull', 0.05);
        var mover = world.createBody(BodyType.Dynamic, 5, 5);
        var moverShape = world.attachShape(mover, ShapeBuilder.makeBox(world.verts, 0.5, 0.5));
        mustThrow(function() world.setShapeVertices(moverShape, [new Vec3(-1, -1), new Vec3(1, -1), new Vec3(1, 1), new Vec3(-1, 1)]),
            'reshape a dynamic body');
    }

    static function sweepHitbox(depth:Float):Void {
        var world = new World(8, 8);
        world.gravity = new Vec3();
        var sword = world.createBody(BodyType.Kinematic, -3, 1);
        var blade = world.attachShape(sword, ShapeBuilder.makeBox(world.verts, 0.4, 0.1, depth));
        world.setShapeSensor(blade, true);
        world.setShapeUserData(blade, 7);
        var enemy = world.createBody(BodyType.Kinematic, 0, 1);
        var hurtbox = world.attachShape(enemy, ShapeBuilder.makeBox(world.verts, 0.3, 0.6, depth));
        world.setShapeSensor(hurtbox, true);
        world.setShapeUserData(hurtbox, 11);
        var begins = 0, ends = 0;
        for (frame in 0...90) {
            world.setKinematicTarget(sword, new Vec3(-3 + 6 * (frame + 1) / 90, 1), new Quat());
            world.step(1.0 / 60.0);
            var e = world.events;
            for (i in 0...e.sensorBegins.count) {
                begins++;
                if (e.sensorBegins.shapeA(i) != blade || e.sensorBegins.shapeB(i) != hurtbox) throw 'sensor begin names the wrong shapes';
                near(e.sensorBegins.userDataA(i), 7, 'hitbox user value');
                near(e.sensorBegins.userDataB(i), 11, 'hurtbox user value');
            }
            ends += e.sensorEnds.count;
            if (e.contactBegins.count != 0) throw 'sensors generated a contact';
        }
        near(begins, 1, 'one hitbox begin (depth $depth)');
        near(ends, 1, 'one hitbox end (depth $depth)');
    }

    static function checkSensorEvents():Void {
        sweepHitbox(0);
        sweepHitbox(0.5);

        var world = new World(8, 8);
        var gate = world.createBody(BodyType.Kinematic, 0, 0);
        world.setShapeSensor(world.attachShape(gate, ShapeBuilder.makeBox(world.verts, 2, 2)), true);
        var ball = world.createBody(BodyType.Dynamic, 0, 3);
        world.attachShape(ball, ShapeBuilder.makeCircle(0.2));
        var overlapped = false;
        for (step in 0...60) {
            world.step(1.0 / 60.0);
            if (world.events.sensorBegins.count > 0) overlapped = true;
            near(world.velY[world.bodySlot(ball)], -9.81 * (step + 1) / 60.0, 'sensor leaves velocity alone', 1e-3);
        }
        if (!overlapped) throw 'falling ball never entered the sensor';
        var hit = world.rayCast(new Vec3(-5, 0), new Vec3(1, 0), 10);
        if (hit != null) throw 'ray cast stopped at a sensor';
    }

    static function checkContactEvents():Void {
        var world = new World(8, 8);
        var floor = world.createBody(BodyType.Static, 0, -0.5, 0);
        var floorShape = world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 5, 0.5, 4));
        world.setShapeUserData(floorShape, 3);
        var crate = world.createBody(BodyType.Dynamic, 0, 2.5, 0);
        var crateShape = world.attachShape(crate, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 1));
        world.setShapeUserData(crateShape, 9);
        var begins = 0, ends = 0, impacts = 0, impactSpeed = 0.0;
        for (_ in 0...300) {
            world.step(1.0 / 60.0);
            var e = world.events;
            begins += e.contactBegins.count;
            ends += e.contactEnds.count;
            for (i in 0...e.impacts.count) {
                impacts++;
                impactSpeed = e.impacts.speed(i);
                var crateIsA = e.impacts.shapeA(i) == crateShape;
                near(crateIsA ? e.impacts.userDataA(i) : e.impacts.userDataB(i), 9, 'impact user value');
                // The normal runs from shape A to shape B, so it points down when the crate is A.
                if ((crateIsA ? -1 : 1) * e.impacts.normalY(i) < 0.9) throw 'impact normal points the wrong way';
            }
        }
        near(begins, 1, 'crate touches the floor once');
        near(impacts, 1, 'crate lands with one impact');
        // The crate drops from 2 m above contact, so the approach speed is sqrt(2 * 9.81 * 2), less a
        // substep of gravity.
        near(impactSpeed, Math.sqrt(2 * 9.81 * 1.98), 'impact approach speed', 0.25);
        if (world.islands.isAwake[world.bodySlot(crate)] != 0) throw 'crate did not fall asleep';
        near(ends, 0, 'sleeping crate keeps touching the floor');
        world.destroyShape(crateShape);
        world.step(1.0 / 60.0);
        near(world.events.contactEnds.count, 1, 'destroyed crate ends its contact');
        near(world.events.contactEnds.userDataA(0) + world.events.contactEnds.userDataB(0), 12,
            'end event keeps the destroyed shape\'s user value');
    }

    static function checkBatchedJoints():Void {
        var world = new World(40, 40, 32);
        world.gravity = new Vec3(0, -9.81, 0);
        var spheres = [], hinges = [];
        for (i in 0...8) {
            var x = i * 2.0;
            var support = world.createBody(BodyType.Static, x, 4, 0);
            var bob = world.createBody(BodyType.Dynamic, x + 0.8, 4, 0.3);
            world.attachShape(bob, ShapeBuilder.makeBox(world.verts, 0.2, 0.2, 0.4));
            world.createSphericalJoint(support, bob, new Vec3(x, 4, 0), new Vec3(1, 0, 0), 1.2, -0.3, 0.3);
            spheres.push(bob);
            var wheel = world.createBody(BodyType.Dynamic, x, 0, 0);
            world.attachShape(wheel, ShapeBuilder.makeBox(world.verts, 0.5, 0.1));
            var axle = world.createBody(BodyType.Static, x, 0, 0);
            hinges.push({body: wheel, joint: world.createHingeJoint(axle, wheel, new Vec3(x, 0, 0), null,
                -0.5, 0.5, i % 2 == 0 ? 2.0 : 0.0, i % 2 == 0 ? 50.0 : 0.0)});
        }
        var batches = 0;
        for (_ in 0...120) {
            world.step(1.0 / 60.0);
            if (world.joints.packedBatches > batches) batches = world.joints.packedBatches;
        }
        #if (ash_simd && !solver_scalar_bench)
        if (batches == 0) throw 'independent joints were not batched';
        #end
        for (i in 0...8) {
            var bob = world.getBodyTransform(spheres[i]);
            var tip = Vec3.add(bob.position, Quat.rotate(bob.rotation, new Vec3(-0.8, 0, -0.3)));
            near(Math.sqrt(Vec3.lengthSq(Vec3.sub(tip, new Vec3(i * 2.0, 4, 0)))), 0, 'batched spherical anchor $i', 0.01);
            var wheel = world.getBodyTransform(hinges[i].body).rotation;
            var angle = 2 * Math.atan2(wheel.z, wheel.w);
            if (angle < -0.55 || angle > 0.55) throw 'batched hinge $i left its limits: $angle';
            if (i % 2 == 0) near(angle, 0.5, 'batched hinge motor $i reaches its limit', 0.06);
        }
    }

    static function checkQueryReach():Void {
        // The flat circle reaches a volumetric shape within its radius along Z, as it does in contacts.
        var world = new World(8, 8);
        var slab = world.createBody(BodyType.Static, 3, 0, 0.3);
        var slabShape = world.attachShape(slab, ShapeBuilder.makeBox(world.verts, 0.5, 1, 0.2));
        var hit = world.shapeCast(ShapeBuilder.makeCircle(0.5), new Vec3(0, 0, 0), new Quat(), new Vec3(6, 0, 0));
        if (hit == null || hit.shape != slabShape) throw 'flat circle cast missed a slab within its radius';
        near(hit.fraction, (3 - 0.5 - 0.01 - Math.sqrt(0.5 * 0.5 - 0.19 * 0.19)) / 6, 'flat circle reaches the slab edge', 0.02);
        var thin = world.rayCast(new Vec3(0, 0, 0), new Vec3(1, 0, 0), 6);
        if (thin != null) throw 'a ray at Z = 0 hit a slab above it';

        // Queries started from inside a region query's callback see their own candidates.
        var field = new World(32, 32);
        for (i in 0...10) field.attachShape(field.createBody(BodyType.Static, i * 2.0, 0), ShapeBuilder.makeCircle(0.4));
        var outer = 0, inner = 0, rays = 0;
        field.queryAABB(new Vec3(-1, -1, -1), new Vec3(19, 1, 1), -1, function(shape) {
            outer++;
            field.queryAABB(new Vec3(-1, -1, -1), new Vec3(5, 1, 1), -1, function(s) { inner++; return true; });
            if (field.rayCast(new Vec3(-2, 0, 0), new Vec3(1, 0, 0), 30) != null) rays++;
            return true;
        });
        near(outer, 10, 'outer region query visits every circle');
        near(inner, 30, 'nested region queries see their own circles');
        near(rays, 10, 'nested ray casts hit');
    }

    static function checkTouching3DStacks():Void {
        // Exactly touching rounded boxes start with touching cores, the EPA case.
        for (height in [3, 4]) {
            var world = new World(8, 8);
            var floor = world.createBody(BodyType.Static, 0, -0.5);
            world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 10, 0.5, 4));
            var boxes = [];
            for (level in 0...height) {
                var box = world.createBody(BodyType.Dynamic, 0, 0.5 + level);
                world.attachShape(box, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 1));
                boxes.push(box);
            }
            for (step in 0...240) world.step(1.0 / 60.0);
            for (level in 0...height) {
                var slot = world.bodySlot(boxes[level]);
                near(world.posY[slot], 0.51 + level * 1.02, '$height-high 3D stack level $level height', 0.03);
                near(world.posX[slot], 0, '$height-high 3D stack level $level x', 0.05);
                near(world.posZ[slot], 0, '$height-high 3D stack level $level z', 0.05);
            }
        }
    }

    static function checkMixedContactSolve():Void {
        var world = new World(8, 8);
        world.gravity = new Vec3();
        var planar = world.createBody(BodyType.Dynamic, 0, 0);
        world.attachShape(planar, ShapeBuilder.makeBox(world.verts, 0.5, 0.5));
        var solid = world.createBody(BodyType.Dynamic, 0, 0.95);
        world.attachShape(solid, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 0.5));
        world.velY[solid] = -2.0;
        world.step(1.0 / 60.0);
        if (world.contacts.count == 0 || world.velY[planar] >= -0.05)
            throw 'mixed-dimensional contact did not transfer momentum';
        near(world.velZ[planar], 0, 'mixed contact planar z lock');
        near(world.angVelX[planar], 0, 'mixed contact planar x rotation lock');
        near(world.angVelY[planar], 0, 'mixed contact planar y rotation lock');
    }

    static function checkContactFeatureCache():Void {
        var contacts = new ContactManifoldPool(64);
        var up = new Vec3(0, 1, 0), down = new Vec3(0, -1, 0), point = new Vec3();
        for (i in 0...64) {
            contacts.addContact(i, i + 1, i % 7, i % 11, i * 65537, up, point, 0.1);
            contacts.normalImpulse[i] = i + 0.25;
            contacts.tangentImpulse1[i] = i * 0.01;
            contacts.tangentImpulse2[i] = -i * 0.02;
        }
        contacts.beginStep();
        for (reverse in 0...64) {
            var i = 63 - reverse;
            contacts.addContact(i, i + 1, i % 7, i % 11, i * 65537, up, point, 0.1);
            near(contacts.normalImpulse[reverse], i + 0.25, 'feature cache normal impulse');
            near(contacts.tangentImpulse1[reverse], i * 0.01, 'feature cache tangent impulse 1');
            near(contacts.tangentImpulse2[reverse], -i * 0.02, 'feature cache tangent impulse 2');
        }
        contacts.beginStep();
        contacts.addContact(63, 64, 63 % 7, 63 % 11, 63 * 65537, down, point, 0.1);
        near(contacts.normalImpulse[0], 0, 'reversed normal clears cached impulse');
        contacts.beginStep();
        contacts.beginStep();
        contacts.addContact(63, 64, 63 % 7, 63 % 11, 63 * 65537, up, point, 0.1);
        near(contacts.normalImpulse[0], 0, 'stale feature is not reused');
    }

    /** Checks that the pool starts small, grows while a step adds contacts, keeps warm starts across growth, and stops at its limit. */
    static function checkContactGrowth():Void {
        var contacts = new ContactManifoldPool(1000, 8);
        var up = new Vec3(0, 1, 0), point = new Vec3();
        if (contacts.capacity != 8) throw 'contact pool starts at ${contacts.capacity}, not 8';
        for (i in 0...8) {
            contacts.addContact(i, i + 1, i, i + 1, i, up, point, 0.1);
            contacts.normalImpulse[i] = i + 0.5;
        }
        contacts.beginStep();
        // Adds new contacts first, so the storage grows while the contacts of the last step still wait
        // for lookup.
        for (i in 0...100) contacts.addContact(500 + i, 501 + i, 500 + i, 501 + i, i, up, point, 0.1);
        if (contacts.capacity < 108 || contacts.count != 100) throw 'contact pool grew to ${contacts.capacity} holding ${contacts.count}';
        for (i in 0...8) {
            contacts.addContact(i, i + 1, i, i + 1, i, up, point, 0.1);
            near(contacts.normalImpulse[100 + i], i + 0.5, 'warm start kept across growth');
        }
        var small = new ContactManifoldPool(16, 4);
        for (i in 0...20) small.addContact(i, i + 1, i, i + 1, i, up, point, 0.1);
        if (small.count != 16 || small.capacity != 16) throw 'a full pool should hold 16 and drop the rest, holds ${small.count} in ${small.capacity}';

        // Builds a world whose pile needs more contacts than its storage starts with.
        var world = new World(128, 128, 4);
        var floor = world.createBody(BodyType.Static, 0, -0.5, 0);
        world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 20, 0.5, 20, 0));
        var boxes = [];
        for (i in 0...100) {
            var box = world.createBody(BodyType.Dynamic, -4.5 + (i % 10), 0.26, -4.5 + Std.int(i / 10));
            world.attachShape(box, ShapeBuilder.makeBox(world.verts, 0.25, 0.25, 0.25));
            boxes.push(box);
        }
        var start = world.contacts.capacity;
        for (_ in 0...3) world.step(1 / 60);
        if (world.contacts.count <= start) throw 'the pile should need more than $start contacts, has ${world.contacts.count}';
        // Restoring into the grown storage replays a step exactly, while the pile is still settling.
        var snapshot = new hxn.me.physics.core.WorldSnapshot();
        snapshot.save(world);
        world.step(1 / 60);
        var y = world.posY[boxes[37]], v = world.velY[boxes[37]];
        snapshot.restore(world);
        world.step(1 / 60);
        if (world.posY[boxes[37]] != y || world.velY[boxes[37]] != v) throw 'restoring a grown pool does not replay the step';
        for (_ in 0...60) world.step(1 / 60);
        for (box in boxes) if (Math.abs(world.posY[box] - 0.25) > 0.02) throw 'a box in the pile sank or rose to ${world.posY[box]}';
    }

    /** Checks that shapes with no rounding, resting on each other, overlap at their cores every step, and that this path allocates nothing, in 3D or in the plane. */
    static function checkDeepContactsAllocateNothing():Void {
        for (planar in [false, true]) {
            var world = new World(8, 8, 2);
            var floor = planar ? world.createBody(BodyType.Static, 0, -0.25) : world.createBody(BodyType.Static, 0, -0.25, 0);
            world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 3, 0.25, planar ? 0.0 : 3.0, 0));
            var box = planar ? world.createBody(BodyType.Dynamic, 0, 0.3) : world.createBody(BodyType.Dynamic, 0, 0.3, 0);
            world.attachShape(box, ShapeBuilder.makeBox(world.verts, 0.3, 0.3, planar ? 0.0 : 0.6, 0));
            for (_ in 0...30) world.step(1.0 / 60.0);
            if (world.contacts.count == 0) throw 'a box with no rounding should rest on the floor (${planar ? "planar" : "3D"})';
            var allocated = Allocation.least(() -> for (_ in 0...20) { world.wakeBody(box); world.step(1.0 / 60.0); });
            if (allocated > 0) throw 'resting on core contact allocated $allocated bytes over 20 steps (${planar ? "planar" : "3D"})';
            if (Math.abs(world.posY[box] - 0.3) > 0.02) throw 'the box should rest at 0.3, is at ${world.posY[box]}';
        }
    }

    static function checkConstraintGraph():Void {
        var contacts = new ContactManifoldPool(32);
        var types = new hxn.Int32Buffer(32);
        for (body in 0...32) types[body] = BodyType.Dynamic;
        var normal = new Vec3(0, 1, 0), point = new Vec3();
        var graph = new ConstraintGraph(32, contacts.maxContacts);
        for (i in 0...25) contacts.addContact(0, i + 1, i, i + 1, i, normal, point, 0.1);
        graph.assign(contacts, types, 32);
        for (i in 0...23) near(graph.colors[i], i, 'hub contact color');
        near(graph.counts[ConstraintGraph.FALLBACK_COLOR], 2, 'hub scalar fallback count');
        near(graph.colors[23], ConstraintGraph.FALLBACK_COLOR, 'first hub fallback');
        near(graph.colors[24], ConstraintGraph.FALLBACK_COLOR, 'second hub fallback');
        var seenContact = new Array<Bool>();
        for (i in 0...25) seenContact.push(false);
        for (color in 0...ConstraintGraph.COLOR_COUNT) {
            var seenBody = new Array<Bool>();
            for (body in 0...32) seenBody.push(false);
            var previous = -1;
            for (position in graph.offsets[color]...graph.offsets[color] + graph.counts[color]) {
                var c = graph.indices[position];
                if (seenContact[c] || c <= previous) throw 'constraint graph order or duplicate';
                seenContact[c] = true;
                previous = c;
                if (color < ConstraintGraph.SIMD_COLORS) {
                    var a = contacts.bodyA[c], b = contacts.bodyB[c];
                    if (seenBody[a] || seenBody[b]) throw 'constraint color repeats a dynamic body';
                    seenBody[a] = seenBody[b] = true;
                }
            }
        }
        for (i in 0...25) if (!seenContact[i]) throw 'constraint graph lost a contact';

        contacts.beginStep();
        types[0] = BodyType.Static;
        for (i in 0...8) contacts.addContact(0, i + 1, i, i + 1, i, normal, point, 0.1);
        graph.assign(contacts, types, 32);
        near(graph.counts[0], 8, 'shared static color count');
        for (i in 0...8) near(graph.colors[i], 0, 'shared static contact color');
    }

    static function checkIslandsAndSleep():Void {
        var contacts = new ContactManifoldPool(8);
        var types = new hxn.Int32Buffer(5);
        var islands = new IslandManager(5);
        for (body in 0...4) {
            types[body] = BodyType.Dynamic;
            islands.addBody(body, BodyType.Dynamic);
        }
        types[4] = BodyType.Static;
        islands.addBody(4, BodyType.Static);
        var normal = new Vec3(1, 0, 0), point = new Vec3();
        contacts.addContact(0, 1, 0, 1, 1, normal, point, 0.1);
        contacts.addContact(1, 2, 1, 2, 2, normal, point, 0.1);
        contacts.addContact(3, 4, 3, 4, 3, normal, point, 0.1);
        islands.build(contacts, types, 5);
        near(islands.islandCount, 2, 'connected island count');
        if (islands.root(0) != islands.root(2) || islands.root(0) == islands.root(3)) throw 'island union';

        var vx = new Float32Buffer(5), vy = new Float32Buffer(5), vz = new Float32Buffer(5);
        var wx = new Float32Buffer(5), wy = new Float32Buffer(5), wz = new Float32Buffer(5);
        var px = new Float32Buffer(5), py = new Float32Buffer(5), pz = new Float32Buffer(5);
        var qx = new Float32Buffer(5), qy = new Float32Buffer(5), qz = new Float32Buffer(5), qw = new Float32Buffer(5);
        for (body in 0...5) qw[body] = 1.0;
        vz[2] = 0.05;
        for (step in 0...32) {
            pz[2] += vz[2] / 60.0;
            islands.updateSleep(1.0 / 60.0, types, 5, vx, vy, vz, wx, wy, wz,
                px, py, pz, qx, qy, qz, qw);
        }
        if (islands.isAwake[0] == 0 || islands.isAwake[1] == 0 || islands.isAwake[2] == 0)
            throw 'moving member let connected island sleep';
        if (islands.isAwake[3] != 0) throw 'independent island did not sleep';
        vz[2] = 0.0;
        for (step in 0...32) islands.updateSleep(1.0 / 60.0, types, 5, vx, vy, vz, wx, wy, wz,
            px, py, pz, qx, qy, qz, qw);
        if (islands.isAwake[0] != 0 || islands.isAwake[1] != 0 || islands.isAwake[2] != 0)
            throw 'connected island did not sleep together';
        islands.wakeBody(1, types, 5);
        if (islands.isAwake[0] == 0 || islands.isAwake[1] == 0 || islands.isAwake[2] == 0 || islands.isAwake[3] != 0)
            throw 'wake did not reach exactly one sleeping island';
        vz[2] = 0.05;
        for (step in 0...32) islands.updateSleep(1.0 / 60.0, types, 5, vx, vy, vz, wx, wy, wz,
            px, py, pz, qx, qy, qz, qw);
        if (islands.isAwake[0] != 0 || islands.isAwake[1] != 0 || islands.isAwake[2] != 0)
            throw 'stationary constrained island did not sleep';
        islands.wakeBody(1, types, 5);
        contacts.beginStep();
        contacts.addContact(0, 3, 0, 3, 4, normal, point, 0.1);
        islands.wakeBody(3, types, 5);
        islands.build(contacts, types, 5);
        near(islands.islandCount, 3, 'islands split after contact removal');
        if (islands.root(0) != islands.root(3) || islands.root(0) == islands.root(1)) throw 'islands did not rebuild';

        var world = new World(8, 8);
        world.gravity = new Vec3();
        var sleeper = world.createBody(BodyType.Dynamic, 0, 0);
        world.attachShape(sleeper, ShapeBuilder.makeCircle(0.5));
        var mover = world.createBody(BodyType.Kinematic, -3, 0);
        world.attachShape(mover, ShapeBuilder.makeCircle(0.5));
        for (step in 0...32) world.step(1.0 / 60.0);
        if (world.islands.isAwake[sleeper] != 0) throw 'world body did not sleep';
        var restingX = world.posX[sleeper];
        world.step(1.0 / 60.0);
        near(world.posX[sleeper], restingX, 'sleeping body integration');
        world.velX[mover] = 4.0;
        for (step in 0...50) world.step(1.0 / 60.0);
        if (world.islands.isAwake[sleeper] == 0) throw 'kinematic contact did not wake sleeping body';
    }

    static function checkDistanceJoints():Void {
        var world = new World(8, 8, 2);
        world.gravity = new Vec3();
        var fixed = world.createBody(BodyType.Static, 0, 0);
        var moving = world.createBody(BodyType.Dynamic, 2, 0);
        world.attachShape(moving, ShapeBuilder.makeCircle(0.25));
        var spring = world.createDistanceJoint(fixed, moving, 1.0, 5.0, 0.8);
        for (step in 0...120) world.step(1.0 / 60.0);
        near(world.posX[moving], 1.0, 'distance spring rest length', 0.05);
        world.destroyJoint(spring);
        near(world.joints.count, 0, 'distance joint destruction');
        var replacement = world.createDistanceJoint(fixed, moving, 1.0);
        near(replacement & ((1 << 20) - 1), spring & ((1 << 20) - 1), 'distance joint slot reuse');
        if (replacement == spring) throw 'destroyed joint handle was reused';
        try {
            world.destroyJoint(spring);
            throw 'stale joint handle was accepted';
        } catch (error:Dynamic) {
            if (error == 'stale joint handle was accepted') throw error;
        }
        world.velX[moving] = 3.0;
        for (step in 0...120) world.step(1.0 / 60.0);
        near(world.posX[moving], 1.0, 'rigid distance joint length', 0.05);

        var linked = new World(8, 8, 2);
        linked.gravity = new Vec3();
        var a = linked.createBody(BodyType.Dynamic, -1, 0);
        var b = linked.createBody(BodyType.Dynamic, 1, 0);
        linked.attachShape(a, ShapeBuilder.makeCircle(0.2));
        linked.attachShape(b, ShapeBuilder.makeCircle(0.2));
        linked.createDistanceJoint(a, b, 2.0);
        for (step in 0...32) linked.step(1.0 / 60.0);
        if (linked.islands.isAwake[a] != 0 || linked.islands.isAwake[b] != 0)
            throw 'joint island did not sleep together';
        linked.wakeBody(a);
        if (linked.islands.isAwake[a] == 0 || linked.islands.isAwake[b] == 0)
            throw 'joint island did not wake together';
        linked.velX[b] = 2.0;
        for (step in 0...60) linked.step(1.0 / 60.0);
        near(linked.posX[b] - linked.posX[a], 2.0, 'two-body joint distance', 0.05);

        var lever = new World(8, 8, 2);
        lever.gravity = new Vec3();
        var pivot = lever.createBody(BodyType.Static, 0, 0);
        var offsetBody = lever.createBody(BodyType.Dynamic, 2, 0);
        lever.attachShape(offsetBody, ShapeBuilder.makeCircle(0.3));
        lever.createDistanceJoint(pivot, offsetBody, 1.0, 0.0, 1.0, new Vec3(), new Vec3(0, 0.2));
        lever.step(1.0 / 60.0);
        // Pulling the joint shut turns the body about its off-center anchor.
        if (Math.abs(2 * Math.atan2(lever.rotZ[offsetBody], lever.rotW[offsetBody])) < 0.01) throw 'off-center joint anchor produced no torque';

        var mixed = new World(8, 8, 2);
        mixed.gravity = new Vec3();
        var planar = mixed.createBody(BodyType.Dynamic, 0, 0, 0);
        var spatial = mixed.createBody(BodyType.Dynamic, 0, 0, 2);
        mixed.attachShape(planar, ShapeBuilder.makeCircle(0.2));
        mixed.attachShape(spatial, ShapeBuilder.makeCircle(0.2, 0.4));
        mixed.createDistanceJoint(planar, spatial, 1.0);
        for (step in 0...120) mixed.step(1.0 / 60.0);
        near(mixed.posZ[planar], 0.0, 'planar joint Z lock');
        near(mixed.posZ[spatial], 1.0, 'mixed dimension joint length', 0.05);
    }

    static function checkHingeJoints():Void {
        var pendulum = new World(8, 8, 2);
        pendulum.gravity = new Vec3();
        var pivot = pendulum.createBody(BodyType.Static, 0, 0);
        var bob = pendulum.createBody(BodyType.Dynamic, 1, 0);
        pendulum.attachShape(bob, ShapeBuilder.makeCircle(0.2));
        var hinge = pendulum.createHingeJoint(pivot, bob, new Vec3());
        pendulum.velY[bob] = 2.0;
        for (step in 0...120) pendulum.step(1.0 / 60.0);
        var angle = 2.0 * Math.atan2(pendulum.rotZ[bob], pendulum.rotW[bob]);
        near(pendulum.posX[bob] - Math.cos(angle), 0.0, 'hinge anchor x', 0.04);
        near(pendulum.posY[bob] - Math.sin(angle), 0.0, 'hinge anchor y', 0.04);
        if (Math.abs(angle) < 0.2) throw 'free hinge did not rotate';
        pendulum.destroyJoint(hinge);
        near(pendulum.joints.count, 0, 'hinge destruction');

        var motor = new World(8, 8, 2);
        motor.gravity = new Vec3();
        var fixed = motor.createBody(BodyType.Static, 0, 0);
        var rotor = motor.createBody(BodyType.Dynamic, 0, 0);
        motor.attachShape(rotor, ShapeBuilder.makeCircle(0.2));
        motor.createHingeJoint(fixed, rotor, new Vec3(), null, -1.0e30, 1.0e30, 2.0, 10.0);
        for (step in 0...30) motor.step(1.0 / 60.0);
        near(motor.angVelZ[rotor], 2.0, 'hinge motor speed', 0.05);
        if (motor.rotZ[rotor] < 0.2) throw 'hinge motor did not rotate body';

        var limited = new World(8, 8, 2);
        limited.gravity = new Vec3();
        var stop = limited.createBody(BodyType.Static, 0, 0);
        var arm = limited.createBody(BodyType.Dynamic, 0, 0);
        limited.attachShape(arm, ShapeBuilder.makeCircle(0.2));
        limited.createHingeJoint(stop, arm, new Vec3(), null, -0.3, 0.3);
        limited.angVelZ[arm] = 5.0;
        for (step in 0...60) limited.step(1.0 / 60.0);
        var stoppedAngle = 2.0 * Math.atan2(limited.rotZ[arm], limited.rotW[arm]);
        if (stoppedAngle > 0.34 || stoppedAngle < -0.34) throw 'hinge angular limit failed: ' + stoppedAngle;
        limited.angVelZ[arm] = -5.0;
        for (step in 0...60) limited.step(1.0 / 60.0);
        stoppedAngle = 2.0 * Math.atan2(limited.rotZ[arm], limited.rotW[arm]);
        if (stoppedAngle < -0.34 || stoppedAngle > 0.34) throw 'hinge lower angular limit failed: ' + stoppedAngle;

        var spatial = new World(8, 8, 2);
        spatial.gravity = new Vec3();
        var base = spatial.createBody(BodyType.Static, 0, 0);
        var solid = spatial.createBody(BodyType.Dynamic, 0, 0);
        spatial.attachShape(solid, ShapeBuilder.makeBox(spatial.verts, 0.2, 0.3, 0.4));
        spatial.createHingeJoint(base, solid, new Vec3(), new Vec3(0, 0, 1));
        spatial.angVelX[solid] = 2.0;
        spatial.angVelZ[solid] = 1.0;
        for (step in 0...60) spatial.step(1.0 / 60.0);
        var axis = Quat.rotate(new Quat(spatial.rotX[solid], spatial.rotY[solid], spatial.rotZ[solid], spatial.rotW[solid]), new Vec3(0, 0, 1));
        near(axis.x, 0.0, '3D hinge tilt x', 0.05);
        near(axis.y, 0.0, '3D hinge tilt y', 0.05);
        if (spatial.rotZ[solid] < 0.1) throw '3D hinge blocked axial rotation';

        var sideways = new World(8, 8, 2);
        sideways.gravity = new Vec3();
        var support = sideways.createBody(BodyType.Static, 0, 0);
        var shaft = sideways.createBody(BodyType.Dynamic, 0, 0);
        sideways.attachShape(shaft, ShapeBuilder.makeBox(sideways.verts, 0.2, 0.3, 0.4));
        sideways.createHingeJoint(support, shaft, new Vec3(), new Vec3(0, 1, 0), -1.0e30, 1.0e30, 1.5, 10.0);
        sideways.angVelX[shaft] = 2.0;
        for (step in 0...60) sideways.step(1.0 / 60.0);
        var sidewaysAxis = Quat.rotate(new Quat(sideways.rotX[shaft], sideways.rotY[shaft], sideways.rotZ[shaft], sideways.rotW[shaft]), new Vec3(0, 1, 0));
        near(sidewaysAxis.x, 0.0, 'sideways hinge tilt x', 0.05);
        near(sidewaysAxis.z, 0.0, 'sideways hinge tilt z', 0.05);
        near(sideways.angVelY[shaft], 1.5, 'sideways hinge motor', 0.05);

        var mixed = new World(8, 8, 2);
        mixed.gravity = new Vec3();
        var flat = mixed.createBody(BodyType.Dynamic, 0, 0, 0);
        var volume = mixed.createBody(BodyType.Dynamic, 0, 0, 1);
        mixed.attachShape(flat, ShapeBuilder.makeCircle(0.2), 1, 0);
        mixed.attachShape(volume, ShapeBuilder.makeCircle(0.2, 0.4), 1, 0);
        mixed.createHingeJoint(flat, volume, new Vec3(0, 0, 0.5));
        mixed.velZ[volume] = 2.0;
        for (step in 0...60) mixed.step(1.0 / 60.0);
        near(mixed.posZ[flat], 0.0, 'mixed hinge planar Z lock');
        near(mixed.posZ[volume], 1.0, 'mixed hinge spatial Z anchor', 0.05);
    }

    static function checkPrismaticJoints():Void {
        var planar = new World(8, 8, 2);
        planar.gravity = new Vec3();
        var guide = planar.createBody(BodyType.Static, 0, 0);
        var cart = planar.createBody(BodyType.Dynamic, 0, 0);
        planar.attachShape(cart, ShapeBuilder.makeCircle(0.2));
        var slider = planar.createPrismaticJoint(guide, cart, new Vec3(), new Vec3(1, 0, 0));
        planar.velX[cart] = 2.0; planar.velY[cart] = 2.0; planar.angVelZ[cart] = 2.0;
        for (step in 0...60) planar.step(1.0 / 60.0);
        if (planar.posX[cart] < 1.5) throw 'planar slider blocked axial travel';
        near(planar.posY[cart], 0.0, 'planar slider transverse lock', 0.03);
        near(planar.rotZ[cart], 0.0, 'planar slider rotation lock', 0.03);
        planar.destroyJoint(slider);
        near(planar.joints.count, 0, 'slider destruction');
        var replacement = planar.createWeldJoint(guide, cart, new Vec3(planar.posX[cart], planar.posY[cart]));
        near(replacement & ((1 << 20) - 1), slider & ((1 << 20) - 1), 'joint kind slot reuse');
        if (replacement == slider) throw 'joint kind reused stale handle';

        var limited = new World(8, 8, 2);
        limited.gravity = new Vec3();
        var rail = limited.createBody(BodyType.Static, 0, 0);
        var carriage = limited.createBody(BodyType.Dynamic, 0, 0);
        limited.attachShape(carriage, ShapeBuilder.makeCircle(0.2));
        limited.createPrismaticJoint(rail, carriage, new Vec3(), new Vec3(1, 0, 0), -0.3, 0.3);
        limited.velX[carriage] = 5.0;
        for (step in 0...60) limited.step(1.0 / 60.0);
        if (limited.posX[carriage] > 0.35) throw 'slider upper limit failed: ' + limited.posX[carriage];
        limited.velX[carriage] = -5.0;
        for (step in 0...60) limited.step(1.0 / 60.0);
        if (limited.posX[carriage] < -0.35) throw 'slider lower limit failed: ' + limited.posX[carriage];

        var motor = new World(8, 8, 2);
        motor.gravity = new Vec3();
        var base = motor.createBody(BodyType.Static, 0, 0);
        var shuttle = motor.createBody(BodyType.Dynamic, 0, 0);
        motor.attachShape(shuttle, ShapeBuilder.makeCircle(0.2));
        motor.createPrismaticJoint(base, shuttle, new Vec3(), new Vec3(1, 0, 0), -1.0e30, 1.0e30, 2.0, 10.0);
        for (step in 0...30) motor.step(1.0 / 60.0);
        near(motor.velX[shuttle], 2.0, 'slider motor speed', 0.05);
        if (motor.posX[shuttle] < 0.5) throw 'slider motor did not translate body';

        var spatial = new World(8, 8, 2);
        spatial.gravity = new Vec3();
        var support = spatial.createBody(BodyType.Static, 0, 0);
        var block = spatial.createBody(BodyType.Dynamic, 0, 0);
        spatial.attachShape(block, ShapeBuilder.makeBox(spatial.verts, 0.2, 0.3, 0.4));
        spatial.createPrismaticJoint(support, block, new Vec3(), new Vec3(0, 1, 0));
        spatial.velX[block] = 2.0; spatial.velY[block] = 2.0; spatial.velZ[block] = 2.0;
        spatial.angVelX[block] = 1.0; spatial.angVelY[block] = 1.0; spatial.angVelZ[block] = 1.0;
        for (step in 0...60) spatial.step(1.0 / 60.0);
        near(spatial.posX[block], 0.0, '3D slider transverse X', 0.05);
        near(spatial.posZ[block], 0.0, '3D slider transverse Z', 0.05);
        if (spatial.posY[block] < 1.5) throw '3D slider blocked axial travel';
        near(spatial.rotX[block], 0.0, '3D slider rotation X', 0.05);
        near(spatial.rotY[block], 0.0, '3D slider rotation Y', 0.05);
        near(spatial.rotZ[block], 0.0, '3D slider rotation Z', 0.05);

        var rotating = new World(8, 8, 2);
        rotating.gravity = new Vec3();
        var movingGuide = rotating.createBody(BodyType.Dynamic, 0, 0);
        var follower = rotating.createBody(BodyType.Dynamic, 1, 0);
        rotating.attachShape(movingGuide, ShapeBuilder.makeBox(rotating.verts, 0.4, 0.4), 1, 0);
        rotating.attachShape(follower, ShapeBuilder.makeBox(rotating.verts, 0.4, 0.4), 1, 0);
        rotating.createPrismaticJoint(movingGuide, follower, new Vec3(1, 0, 0), new Vec3(1, 0, 0));
        rotating.velX[follower] = 1.0;
        for (step in 0...60) rotating.step(1.0 / 60.0);
        rotating.velX[follower] = rotating.velX[movingGuide] = 0.0;
        rotating.angVelZ[movingGuide] = rotating.angVelZ[follower] = 1.0;
        rotating.velY[follower] = rotating.posX[follower] - rotating.posX[movingGuide];
        rotating.step(1.0 / 60.0);
        near(rotating.angVelZ[movingGuide], 1.0, 'rotating slider guide speed', 0.15);
        near(rotating.angVelZ[follower], 1.0, 'rotating slider follower speed', 0.15);
    }

    static function checkWeldJoints():Void {
        var planar = new World(8, 8, 2);
        planar.gravity = new Vec3();
        var base = planar.createBody(BodyType.Static, 0, 0);
        var link = planar.createBody(BodyType.Dynamic, 1, 0);
        planar.attachShape(link, ShapeBuilder.makeCircle(0.2));
        var weld = planar.createWeldJoint(base, link, new Vec3(0.5, 0, 0));
        planar.velX[link] = 2.0; planar.velY[link] = 2.0; planar.angVelZ[link] = 2.0;
        for (step in 0...120) planar.step(1.0 / 60.0);
        near(planar.posX[link], 1.0, 'planar weld relative X', 0.05);
        near(planar.posY[link], 0.0, 'planar weld relative Y', 0.05);
        near(planar.rotZ[link], 0.0, 'planar weld angle', 0.05);
        planar.destroyJoint(weld);
        near(planar.joints.count, 0, 'weld destruction');

        var spatial = new World(8, 8, 2);
        spatial.gravity = new Vec3();
        var support = spatial.createBody(BodyType.Static, 0, 0);
        var block = spatial.createBody(BodyType.Dynamic, 1, 0);
        spatial.rotY[block] = Math.sin(0.2); spatial.rotW[block] = Math.cos(0.2);
        spatial.attachShape(block, ShapeBuilder.makeBox(spatial.verts, 0.2, 0.3, 0.4));
        spatial.createWeldJoint(support, block, new Vec3(0.5, 0, 0));
        spatial.velX[block] = 2.0; spatial.velY[block] = 2.0; spatial.velZ[block] = 2.0;
        spatial.angVelX[block] = 1.0; spatial.angVelY[block] = 1.0; spatial.angVelZ[block] = 1.0;
        for (step in 0...120) spatial.step(1.0 / 60.0);
        near(spatial.posX[block], 1.0, '3D weld relative X', 0.06);
        near(spatial.posY[block], 0.0, '3D weld relative Y', 0.06);
        near(spatial.posZ[block], 0.0, '3D weld relative Z', 0.06);
        near(spatial.rotX[block], 0.0, '3D weld rotation X', 0.06);
        near(spatial.rotY[block], Math.sin(0.2), '3D weld rotation Y', 0.06);
        near(spatial.rotZ[block], 0.0, '3D weld rotation Z', 0.06);

        var mixed = new World(8, 8, 2);
        mixed.gravity = new Vec3();
        var flat = mixed.createBody(BodyType.Dynamic, 0, 0, 0);
        var volume = mixed.createBody(BodyType.Dynamic, 0, 0, 1);
        mixed.attachShape(flat, ShapeBuilder.makeCircle(0.2), 1, 0);
        mixed.attachShape(volume, ShapeBuilder.makeCircle(0.2, 0.4), 1, 0);
        mixed.createWeldJoint(flat, volume, new Vec3(0, 0, 0.5));
        mixed.velZ[volume] = 2.0;
        for (step in 0...120) mixed.step(1.0 / 60.0);
        near(mixed.posZ[flat], 0.0, 'mixed weld planar Z lock');
        near(mixed.posZ[volume], 1.0, 'mixed weld spatial Z', 0.06);
    }


    static function checkClipTopology():Void {
        var vertices = new VertexPool(64);
        var planar = ShapeBuilder.makeBox(vertices, 1, 1);
        var solid = ShapeBuilder.makeBox(vertices, 1, 1, 2);
        var points:Array<Vec3> = [];
        for (x in 0...2) for (y in 0...2) for (z in 0...2)
            points.push(new Vec3(x == 0 ? -1 : 1, y == 0 ? -1 : 1, z == 0 ? -1 : 1));
        var hull = ShapeBuilder.makeHull(vertices, points);
        var origin = new Vec3(), shifted = new Vec3(1.5, 0, 0), normal = new Vec3(1, 0, 0);
        var identity = new Quat(), pitched = new Quat(0, Math.sin(0.2), 0, Math.cos(0.2));
        var workspace = new ClipWorkspace();
        for (shape in [planar, solid, hull]) {
            var rotation = shape == planar ? identity : pitched;
            var plain = ManifoldClipper.generate(vertices, shape, origin, rotation, shape, shifted, identity, normal);
            var topology = ManifoldClipper.buildTopology(vertices, shape);
            var cached = ManifoldClipper.generate(vertices, shape, origin, rotation, shape, shifted, identity, normal,
                topology, topology);
            var reused = ManifoldClipper.generate(vertices, shape, origin, rotation, shape, shifted, identity, normal,
                topology, topology, workspace);
            near(cached.length, plain.length, 'cached clip contact count');
            near(reused.length, plain.length, 'reused clip contact count');
            if (plain.length == 0) throw 'cached clip fixture has no contacts';
            for (i in 0...plain.length) {
                near(cached[i].feature, plain[i].feature, 'cached clip feature');
                near(cached[i].penetration, plain[i].penetration, 'cached clip depth', 0.001);
                near(cached[i].point.x, plain[i].point.x, 'cached clip x', 0.001);
                near(cached[i].point.y, plain[i].point.y, 'cached clip y', 0.001);
                near(cached[i].point.z, plain[i].point.z, 'cached clip z', 0.001);
                near(reused[i].feature, plain[i].feature, 'reused clip feature');
                near(reused[i].penetration, plain[i].penetration, 'reused clip depth', 0.001);
                near(reused[i].point.x, plain[i].point.x, 'reused clip x', 0.001);
                near(reused[i].point.y, plain[i].point.y, 'reused clip y', 0.001);
                near(reused[i].point.z, plain[i].point.z, 'reused clip z', 0.001);
            }
        }
    }

    static function checkManifolds():Void {
        var vertices = new VertexPool(64);
        var flat = ShapeBuilder.makeBox(vertices, 1, 1);
        var solid = ShapeBuilder.makeBox(vertices, 1, 1, 2);
        var contacts = new ContactManifoldPool(16);
        var origin = new Vec3();
        var identity = new Quat();
        var shifted = new Vec3(1.5, 0, 0);
        if (!NarrowPhase.collidePair(vertices, flat, 0, origin, identity,
            flat, 1, shifted, identity, contacts, 0, 1)) throw 'planar overlap missed';
        near(contacts.normalX[0], 1, 'planar overlap normal', 0.001);
        near(contacts.penetration[0], 0.52, 'planar EPA depth', 0.002);
        near(contacts.count, 2, 'planar face contacts');
        var sharp = ShapeBuilder.makeBox(vertices, 1, 1, 0, 0);
        var sharpContacts = new ContactManifoldPool(4);
        if (!NarrowPhase.collidePair(vertices, sharp, 0, origin, identity,
            sharp, 1, shifted, identity, sharpContacts, 8, 9)) throw 'coplanar sharp overlap missed';
        near(sharpContacts.penetration[0], 0.5, 'coplanar sharp depth', 0.002);
        contacts.normalImpulse[0] = 1.25;
        contacts.tangentImpulse1[0] = 0.3;
        contacts.tangentImpulse2[0] = -0.1;
        var feature = contacts.featureId[0];
        contacts.beginStep();
        NarrowPhase.collidePair(vertices, flat, 0, origin, identity,
            flat, 1, shifted, identity, contacts, 0, 1);
        var matched = false;
        for (i in 0...contacts.count) if (contacts.featureId[i] == feature) {
            near(contacts.normalImpulse[i], 1.25, 'normal warm start');
            near(contacts.tangentImpulse1[i], 0.3, 'first tangent warm start');
            near(contacts.tangentImpulse2[i], -0.1, 'second tangent warm start');
            matched = true;
        }
        if (!matched) throw 'contact feature changed without motion';
        contacts.normalImpulse[0] = 0.7;
        var movingFeature = contacts.featureId[0];
        contacts.beginStep();
        NarrowPhase.collidePair(vertices, flat, 0, origin, identity,
            flat, 1, new Vec3(1.5, 0.01), identity, contacts, 0, 1);
        matched = false;
        for (i in 0...contacts.count) if (contacts.featureId[i] == movingFeature) {
            near(contacts.normalImpulse[i], 0.7, 'moving feature warm start');
            matched = true;
        }
        if (!matched) throw 'small motion lost contact feature';
        contacts.beginStep();
        if (NarrowPhase.collidePair(vertices, flat, 0, origin, identity,
            flat, 1, new Vec3(3, 0, 0), identity, contacts, 0, 1)) throw 'separated pair collided';
        near(contacts.count, 0, 'separated contact count');
        if (!NarrowPhase.collidePair(vertices, flat, 0, origin, identity,
            flat, 1, new Vec3(2.01, 0, 0), identity, contacts, 0, 1)) throw 'skin contact missed';
        near(contacts.penetration[0], 0.01, 'skin depth', 0.002);
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, flat, 0, origin, identity,
            flat, 1, new Vec3(0, 0, 0.01), identity, contacts, 0, 1)) throw 'out of plane skin contact missed';
        near(contacts.count, 1, 'out of plane contact count');
        near(contacts.normalZ[0], 1, 'out of plane contact normal');
        near(contacts.penetration[0], 0.01, 'out of plane skin depth', 0.002);
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, solid, 0, origin, identity,
            solid, 1, shifted, identity, contacts, 2, 3)) throw 'solid overlap missed';
        near(contacts.normalX[0], 1, 'solid overlap normal', 0.001);
        near(contacts.penetration[0], 0.52, 'solid EPA depth', 0.002);
        near(contacts.count, 4, 'solid face contacts');
        contacts.normalImpulse[0] = 0.9;
        var solidFeature = contacts.featureId[0];
        contacts.beginStep();
        NarrowPhase.collidePair(vertices, solid, 0, origin, identity,
            solid, 1, new Vec3(1.5, 0.01, 0), identity, contacts, 2, 3);
        matched = false;
        for (i in 0...contacts.count) if (contacts.featureId[i] == solidFeature) {
            near(contacts.normalImpulse[i], 0.9, 'moving solid warm start');
            matched = true;
        }
        if (!matched) throw 'small solid motion lost contact feature';
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, solid, 1, shifted, identity,
            solid, 0, origin, identity, contacts, 3, 2)) throw 'reversed solid overlap missed';
        near(contacts.normalX[0], -1, 'reversed solid normal', 0.001);
        near(contacts.penetration[0], 0.52, 'reversed solid depth', 0.002);
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, flat, 0, origin, identity,
            solid, 1, shifted, identity, contacts, 0, 3)) throw 'mixed overlap missed';
        for (i in 0...contacts.count) if (!Math.isFinite(contacts.penetration[i])) throw 'nonfinite mixed contact';
        var circle = ShapeBuilder.makeCircle(1);
        var segment = ShapeBuilder.makeSegment(vertices, -1, 0, 1, 0);
        for (pair in [[circle, circle], [segment, segment], [circle, segment]]) {
            for (offset in [0.0, 0.1]) {
                contacts.beginStep();
                NarrowPhase.collidePair(vertices, pair[0], 0, origin, identity,
                    pair[1], 1, new Vec3(offset, 0, 0), identity, contacts, 4, 5);
                for (i in 0...contacts.count) {
                    if (!Math.isFinite(contacts.normalX[i]) || !Math.isFinite(contacts.normalY[i])
                        || !Math.isFinite(contacts.normalZ[i]) || !Math.isFinite(contacts.penetration[i])
                        || !Math.isFinite(contacts.pointX[i]) || !Math.isFinite(contacts.pointY[i])
                        || !Math.isFinite(contacts.pointZ[i])) throw 'nonfinite degenerate contact';
                }
            }
        }
        var yaw = new Quat(0, 0, Math.sin(0.2), Math.cos(0.2));
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, flat, 0, origin, yaw,
            flat, 1, shifted, identity, contacts, 0, 1)) throw 'rotated overlap missed';
        if (contacts.count < 1 || contacts.count > 2 || contacts.normalX[0] < 0.8
            || contacts.penetration[0] <= 0) throw 'rotated planar contact invalid';
        var rotatedDepth = Math.cos(0.4) + Math.sin(0.4) - 0.48;
        var planarMaxDepth = 0.0;
        for (i in 0...contacts.count) planarMaxDepth = Math.max(planarMaxDepth, contacts.penetration[i]);
        near(planarMaxDepth, rotatedDepth, 'rotated planar EPA depth', 0.003);
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, solid, 0, origin, yaw,
            solid, 1, shifted, identity, contacts, 2, 3)) throw 'rotated solid overlap missed';
        if (contacts.count < 2 || contacts.count > 4 || contacts.normalX[0] < 0.8
            || !Math.isFinite(contacts.penetration[0])) throw 'rotated solid contact invalid';
        var solidMaxDepth = 0.0;
        for (i in 0...contacts.count) solidMaxDepth = Math.max(solidMaxDepth, contacts.penetration[i]);
        near(solidMaxDepth, rotatedDepth, 'rotated solid EPA depth', 0.003);
        for (turn in 1...12) {
            var angle = turn * 0.1;
            var qTurn = new Quat(0, 0, Math.sin(angle * 0.5), Math.cos(angle * 0.5));
            var projection = Math.cos(angle) + Math.sin(angle);
            var expected = Math.min(projection - 0.5,
                Math.min(1 + projection - 1.5 * Math.cos(angle), 1 + projection - 1.5 * Math.sin(angle))) + 0.02;
            contacts.beginStep();
            if (!NarrowPhase.collidePair(vertices, flat, 0, origin, qTurn,
                flat, 1, shifted, identity, contacts, 0, 1)) throw 'rotated sweep missed';
            var maximum = 0.0;
            for (i in 0...contacts.count) maximum = Math.max(maximum, contacts.penetration[i]);
            near(maximum, expected, 'rotated sweep depth $turn', 0.01);
        }
        var pitch = new Quat(0, Math.sin(0.2), 0, Math.cos(0.2));
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, solid, 0, origin, pitch,
            solid, 1, shifted, identity, contacts, 2, 3)) throw 'pitched solid overlap missed';
        if (contacts.count < 2 || contacts.count > 4 || contacts.normalX[0] < 0.8)
            throw 'pitched solid contact invalid';
        var pitchedMaxDepth = 0.0;
        for (i in 0...contacts.count) pitchedMaxDepth = Math.max(pitchedMaxDepth, contacts.penetration[i]);
        near(pitchedMaxDepth, rotatedDepth, 'pitched solid EPA depth', 0.003);
        var hullPoints:Array<Vec3> = [];
        for (x in 0...2) for (y in 0...2) for (z in 0...2)
            hullPoints.push(new Vec3(x == 0 ? -1 : 1, y == 0 ? -1 : 1, z == 0 ? -1 : 1));
        hullPoints.push(new Vec3(1, 0, 0));
        var hull = ShapeBuilder.makeHull(vertices, hullPoints);
        contacts.beginStep();
        if (!NarrowPhase.collidePair(vertices, hull, 0, origin, identity,
            hull, 1, shifted, identity, contacts, 6, 7)) throw 'hull overlap missed';
        near(contacts.count, 4, 'hull face contacts');
        near(contacts.penetration[0], 0.52, 'hull EPA depth', 0.002);

        var stack = new World(8, 8);
        var floor = stack.createBody(BodyType.Static, 0, 0);
        stack.attachShape(floor, ShapeBuilder.makeBox(stack.verts, 2, 0.5));
        var box = stack.createBody(BodyType.Dynamic, 0, 1.05);
        stack.attachShape(box, ShapeBuilder.makeBox(stack.verts, 0.5, 0.5));
        var stableFrames = 0;
        for (step in 0...120) {
            stack.step(1.0 / 60.0);
            if (stack.contacts.count == 2 && stack.contacts.normalImpulse[0] > 0
                && stack.contacts.normalImpulse[1] > 0) stableFrames++;
        }
        if (stableFrames < 30) throw 'stack did not retain two loaded contacts';
        near(stack.posY[box], 1.0, 'stack resting height', 0.05);
        var upper = stack.createBody(BodyType.Dynamic, 0, 2.07);
        stack.attachShape(upper, ShapeBuilder.makeBox(stack.verts, 0.5, 0.5));
        var loadedPairs = 0;
        for (step in 0...120) {
            stack.step(1.0 / 60.0);
            if (stack.contacts.count == 4) {
                var allLoaded = true;
                for (i in 0...4) if (stack.contacts.normalImpulse[i] <= 0) allLoaded = false;
                if (allLoaded) loadedPairs++;
            }
        }
        if (loadedPairs < 30) throw 'two-box stack lost its contact manifold';
        near(stack.posY[upper], 2.0, 'upper stack resting height', 0.08);
    }

    /** Checks that hull faces are counted once each, against the exact volumes, centroids and triangle counts of turned boxes and octahedra. */
    static function checkHullVolumes():Void {
        var seed = 3;
        inline function next():Float {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
            return (seed % 100000) / 100000;
        }
        for (round in 0...500) {
            var hx = 0.01 + next() * 2, hy = 0.01 + next() * 2, hz = 0.01 + next() * 2;
            var q = new Quat(next() - 0.5, next() - 0.5, next() - 0.5, next() - 0.5);
            var l = Math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
            q = new Quat(q.x / l, q.y / l, q.z / l, q.w / l);
            var cx = next() - 0.5, cy = next() - 0.5, cz = next() - 0.5;
            var octahedron = round % 5 == 4;
            var corners = octahedron ? [new Vec3(hx, 0, 0), new Vec3(-hx, 0, 0), new Vec3(0, hy, 0), new Vec3(0, -hy, 0), new Vec3(0, 0, hz), new Vec3(0, 0, -hz)]
                : [for (k in 0...8) new Vec3(k & 1 != 0 ? hx : -hx, k & 2 != 0 ? hy : -hy, k & 4 != 0 ? hz : -hz)];
            var points = [for (p in corners) { var r = Quat.rotate(q, p); new Vec3(r.x + cx, r.y + cy, r.z + cz); }];
            var triangles = hxn.me.physics.geom.ConvexHull.triangles(points);
            var expectedTriangles = octahedron ? 8 : 12;
            if (Std.int(triangles.length / 3) != expectedTriangles) throw 'hull $round: ${Std.int(triangles.length / 3)} triangles, expected $expectedTriangles';
            var pool = new VertexPool(16);
            var o = pool.allocateBlock(points.length);
            for (i in 0...points.length) { pool.vx[o + i] = points[i].x; pool.vy[o + i] = points[i].y; pool.vz[o + i] = points[i].z; }
            var m = MassProperties.hull(pool, o, points.length, 0, 1);
            // Points are stored as 32-bit values, so allow for their rounding.
            var volume = octahedron ? 4.0 / 3.0 * hx * hy * hz : 8 * hx * hy * hz;
            if (Math.abs(m.mass - volume) > volume * 1e-4) throw 'hull $round: volume ${m.mass}, expected $volume';
            var size = Math.max(hx, Math.max(hy, hz));
            if (Math.abs(m.centroidX - cx) > size * 1e-4 || Math.abs(m.centroidY - cy) > size * 1e-4 || Math.abs(m.centroidZ - cz) > size * 1e-4)
                throw 'hull $round: centroid (${m.centroidX}, ${m.centroidY}, ${m.centroidZ}), expected ($cx, $cy, $cz)';
        }
    }

    /** Checks that nearly coplanar points with rounding jitter, as EPA meets them, still make a hull with every face outward, and that a box foot rests on a box floor wherever it stands. */
    static function checkHullRobustness():Void {
        var text = "-1.910000086,0.000408561,2.119999886 | 2.209999800,-1.079592109,-2.120000124 | -1.910000205,0.000408069,-2.120000124 | 2.210000038,0.000408425,-1.880000234 | 2.210000038,-0.999591589,-1.880000234 | -1.910000324,-1.079591990,-2.119999886 | -1.910000086,0.000408560,-1.880000114 | -1.790000319,-1.079592109,-2.120000124 | -1.910000086,-1.079591393,2.120000124 | -1.790000200,-0.999592066,-2.120000124";
        var pts = [for (p in text.split(" | ")) { var c = p.split(","); new Vec3(Std.parseFloat(c[0]), Std.parseFloat(c[1]), Std.parseFloat(c[2])); }];
        var tris = hxn.me.physics.geom.ConvexHull.triangles(pts);
        for (t in 0...Std.int(tris.length / 3)) {
            var a = pts[tris[t * 3]], b = pts[tris[t * 3 + 1]], c = pts[tris[t * 3 + 2]];
            var n = Vec3.cross(Vec3.sub(b, a), Vec3.sub(c, a));
            if (Vec3.dot(n, a) < 0) throw 'hull triangle $t faces inward';
        }
        function box(hx:Float, hy:Float, hz:Float):Array<Vec3> return [for (k in 0...8) new Vec3(k & 1 != 0 ? hx : -hx, k & 2 != 0 ? hy : -hy, k & 4 != 0 ? hz : -hz)];
        for (x in [0.0, -0.15, 0.15, -0.3, 0.37]) {
            var w = new World(8, 64, 4);
            var floor = w.createBody(BodyType.Static, 0, -0.5, 0);
            w.attachShape(floor, ShapeBuilder.makeHull(w.verts, box(2, 0.5, 2), 0.0));
            var foot = w.createBody(BodyType.Dynamic, x, 0.04, 0);
            w.attachShape(foot, ShapeBuilder.makeHull(w.verts, box(0.06, 0.04, 0.12), 0.0, 0.0, 1000));
            var s = w.bodySlot(foot);
            for (_ in 0...60) {
                w.step(1 / 60);
                var speed = Math.sqrt(w.velX[s] * w.velX[s] + w.velY[s] * w.velY[s] + w.velZ[s] * w.velZ[s]);
                if (speed > 0.1 || w.posY[s] < 0.03) throw 'a box foot at x $x should rest on the floor, moving $speed at height ${w.posY[s]}';
            }
        }
    }

    static function main():Void {
        checkHullRobustness();
        checkHullVolumes();
        var pool = new VertexPool(8);
        pool.pushVertex(0, 0);
        pool.pushVertex(2, 0);
        pool.pushVertex(0, 1);
        var p = MassProperties.polygon(pool, 0, 3, 0, 0, 1);
        near(p.mass, 1, 'triangle mass');
        near(p.centroidX, 2.0 / 3.0, 'triangle cx');
        near(p.centroidY, 1.0 / 3.0, 'triangle cy');
        near(p.ixx, 1.0 / 6.0, 'triangle Ixx');
        near(p.iyy, 2.0 / 3.0, 'triangle Iyy');
        near(p.izz, 5.0 / 6.0, 'triangle Izz');
        var prism = MassProperties.polygon(pool, 0, 3, 2, 1, 1);
        near(prism.mass, 2, 'prism mass');
        near(prism.ixx, 3, 'prism Ixx');
        near(prism.iyy, 4, 'prism Iyy');
        near(prism.izz, 5.0 / 3.0, 'prism Izz');
        var reverse = ShapeBuilder.makePolygon(pool, [new Vec3(0, 1), new Vec3(2, 0), new Vec3(0, 0)]);
        var reversed = MassProperties.polygon(pool, reverse.vertOffset, reverse.vertCount, 0, 0, 1);
        near(reversed.mass, 1, 'reversed polygon mass');
        near(reversed.izz, 5.0 / 6.0, 'reversed polygon inertia');
        var capPool = new VertexPool(8);
        capPool.pushVertex(-1, 0);
        capPool.pushVertex(1, 0);
        var capsule = MassProperties.capsule(capPool, 0, 0.5, 0, 0, 1);
        near(capsule.mass, 2 + Math.PI / 4, 'capsule mass');
        near(capsule.centroidX, 0, 'capsule cx');
        capPool.pushVertex(0, -1);
        capPool.pushVertex(0, 1);
        var vertical = MassProperties.capsule(capPool, 2, 0.5, 0, 0, 1);
        near(vertical.ixx, capsule.iyy, 'rotated capsule inertia x');
        near(vertical.iyy, capsule.ixx, 'rotated capsule inertia y');
        var point3D = MassProperties.point(1, 2, 0, 1);
        near(point3D.mass, 2 * Math.PI + 4 * Math.PI / 3, '3D point mass');
        near(point3D.izz, 23.0 * Math.PI / 15.0, '3D point axial inertia');
        var plate = MassProperties.capsule(capPool, 0, 0.5, 1, 0, 1);
        near(plate.mass, 2 + 11.0 * Math.PI / 12.0, 'rounded plate mass');
        var verticalPlate = MassProperties.capsule(capPool, 2, 0.5, 1, 0, 1);
        near(verticalPlate.ixx, plate.iyy, 'rounded plate rotated Ixx');
        near(verticalPlate.iyy, plate.ixx, 'rounded plate rotated Iyy');
        var capsuleDef = ShapeBuilder.makeCapsule(capPool, 0, 0, 0, 0, 2, 1);
        var capsuleAsPoint = MassProperties.capsule(capPool, capsuleDef.vertOffset, 1, 2, 0, 1);
        near(capsuleAsPoint.mass, point3D.mass, 'zero-length 3D capsule mass');
        near(capsuleAsPoint.ixx, point3D.ixx, 'zero-length 3D capsule inertia');
        var hullPool = new VertexPool(16);
        var tetra = ShapeBuilder.makeHull(hullPool, [
            new Vec3(0, 0, 0), new Vec3(1, 0, 0),
            new Vec3(0, 1, 0), new Vec3(0, 0, 1)
        ], 0);
        var tetraMass = MassProperties.hull(hullPool, tetra.vertOffset, tetra.vertCount, 0, 1);
        near(tetraMass.mass, 1.0 / 6.0, 'tetra volume');
        near(tetraMass.centroidX, 0.25, 'tetra cx');
        near(tetraMass.ixx, 1.0 / 30.0, 'tetra Ixx');
        near(tetraMass.ixy, -1.0 / 120.0, 'tetra Ixy');
        var cubeVertices:Array<Vec3> = [];
        for (x in -1...1) for (y in -1...1) for (z in -1...1)
            cubeVertices.push(new Vec3(x == -1 ? -1 : 1, y == -1 ? -1 : 1, z == -1 ? -1 : 1));
        var cube = ShapeBuilder.makeHull(hullPool, cubeVertices, 0);
        var cubeMass = MassProperties.hull(hullPool, cube.vertOffset, cube.vertCount, 0, 1);
        near(cubeMass.mass, 8, 'cube volume');
        near(cubeMass.ixx, 16.0 / 3.0, 'cube Ixx');
        near(cubeMass.ixy, 0, 'cube Ixy');
        var shiftedCube = MassProperties.hull(hullPool, cube.vertOffset, cube.vertCount, 2, 1);
        near(shiftedCube.centroidZ, 2, 'shifted cube cz');
        near(shiftedCube.ixx, 16.0 / 3.0 + 32, 'shifted cube Ixx');
        var cloud = cubeVertices.copy();
        cloud.reverse();
        cloud.push(new Vec3());
        var cloudPool = new VertexPool(16);
        var cloudShape = ShapeBuilder.makeHull(cloudPool, cloud, 0);
        near(MassProperties.hull(cloudPool, cloudShape.vertOffset, cloudShape.vertCount, 0, 1).mass,
            8, 'unordered hull with interior vertex');
        var oldCount = cloudPool.count;
        var rejected = false;
        try {
            ShapeBuilder.makeHull(cloudPool,
                [new Vec3(0, 0), new Vec3(1, 0), new Vec3(0, 1), new Vec3(1, 1)], 0);
        } catch (_:Dynamic) {
            rejected = true;
        }
        if (!rejected || cloudPool.count != oldCount) throw 'invalid hull changed the vertex pool';

        var q = new Quat(0, 0, Math.sqrt(0.5), Math.sqrt(0.5));
        var rotated = Mat3.rotatedDiagonal(q, 2, 3, 4);
        near(rotated.xx, 3, 'rotated Ixx');
        near(rotated.yy, 2, 'rotated Iyy');
        near(rotated.xy, 0, 'rotated Ixy');
        var tetraCentered = new Mat3(1.0 / 80.0, 1.0 / 80.0, 1.0 / 80.0,
            1.0 / 480.0, 1.0 / 480.0, 1.0 / 480.0);
        var identityColumn = tetraCentered.inverse().multiply(tetraCentered.multiply(new Vec3(1, 0, 0)));
        near(identityColumn.x, 1, 'full tensor inverse x');
        near(identityColumn.y, 0, 'full tensor inverse y');

        var world = new World(8, 8);
        world.gravity = new Vec3();
        var body = world.createBody(BodyType.Dynamic, 0, 0);
        world.attachShape(body, ShapeBuilder.makeBox(world.verts, 1, 0.5));
        near(1.0 / world.invInertiaZ[body], 2.0 * (4.0 + 1.0) / 12.0, 'world box inertia');
        world.angVelZ[body] = 2.0;
        for (i in 0...60) world.step(1.0 / 60.0);
        near(world.rotZ[body], Math.sin(1), 'angular integration', 0.0002);
        near(world.rotW[body], Math.cos(1), 'angular integration w', 0.0002);
        near(world.rotX[body] * world.rotX[body] + world.rotY[body] * world.rotY[body]
            + world.rotZ[body] * world.rotZ[body] + world.rotW[body] * world.rotW[body], 1, 'unit quaternion');

        var centered = new World(8, 8);
        centered.gravity = new Vec3();
        var offCenter = centered.createBody(BodyType.Dynamic, 0, 0);
        centered.attachShape(offCenter, ShapeBuilder.makePolygon(centered.verts,
            [new Vec3(0, 0), new Vec3(2, 0), new Vec3(0, 1)]));
        near(centered.localCenterX[offCenter], 2.0 / 3.0, 'body local cx');
        near(centered.localCenterY[offCenter], 1.0 / 3.0, 'body local cy');
        near(1.0 / centered.invInertiaZ[offCenter], 5.0 / 6.0 - 5.0 / 9.0, 'body centered Izz');
        var worldCx = centered.worldCenterX[offCenter], worldCy = centered.worldCenterY[offCenter];
        centered.angVelZ[offCenter] = 1.0;
        centered.step(0.1);
        near(centered.worldCenterX[offCenter], worldCx, 'rotating center x');
        near(centered.worldCenterY[offCenter], worldCy, 'rotating center y');
        var hullWorld = new World(8, 8);
        var hullBody = hullWorld.createBody(BodyType.Dynamic, 0, 0);
        hullWorld.attachShape(hullBody, ShapeBuilder.makeHull(hullWorld.verts,
            [new Vec3(0, 0, 0), new Vec3(1, 0, 0), new Vec3(0, 1, 0), new Vec3(0, 0, 1)], 0));
        if (Math.abs(hullWorld.invInertiaXY[hullBody]) < 0.001)
            throw 'off-axis hull inverse tensor lost its cross term';
        var compound = new World(8, 8);
        compound.gravity = new Vec3();
        var mixed = compound.createBody(BodyType.Dynamic, 0, 0);
        compound.attachShape(mixed, ShapeBuilder.makePolygon(compound.verts,
            [new Vec3(0, 0), new Vec3(1, 0), new Vec3(1, 1), new Vec3(0, 1)]));
        compound.attachShape(mixed, ShapeBuilder.makePolygon(compound.verts,
            [new Vec3(2, 0), new Vec3(3, 0), new Vec3(3, 1), new Vec3(2, 1)], 0, 0, 2));
        near(compound.localCenterX[mixed], 1.5, 'compound cx');
        near(compound.localCenterY[mixed], 0.5, 'compound cy');
        near(compound.localCenterZ[mixed], 1, 'compound cz');
        var compoundInertia = new Mat3(13.0 / 6.0, 25.0 / 6.0, 7.0 / 3.0, 0, -2, 0);
        var compoundInverse = new Mat3(compound.invInertiaX[mixed], compound.invInertiaY[mixed],
            compound.invInertiaZ[mixed], compound.invInertiaXY[mixed], compound.invInertiaXZ[mixed], compound.invInertiaYZ[mixed]);
        var recovered = compoundInverse.multiply(compoundInertia.multiply(new Vec3(1, 0, 0)));
        near(recovered.x, 1, 'compound tensor inverse x');
        near(recovered.y, 0, 'compound tensor inverse y');
        near(recovered.z, 0, 'compound tensor inverse z');
        var compoundCx = compound.worldCenterX[mixed];
        var compoundCy = compound.worldCenterY[mixed];
        var compoundCz = compound.worldCenterZ[mixed];
        compound.angVelY[mixed] = 1;
        compound.step(0.1);
        near(compound.worldCenterX[mixed], compoundCx, 'compound rotating center x');
        near(compound.worldCenterY[mixed], compoundCy, 'compound rotating center y');
        near(compound.worldCenterZ[mixed], compoundCz, 'compound rotating center z');

        var collision = new World(8, 8);
        collision.gravity = new Vec3();
        var ground = collision.createBody(BodyType.Static, 0, 0);
        collision.attachShape(ground, ShapeBuilder.makeBox(collision.verts, 10, 0.5));
        var falling = collision.createBody(BodyType.Dynamic, 0, 1.0);
        collision.attachShape(falling, ShapeBuilder.makeBox(collision.verts, 0.5, 0.5));
        collision.rotZ[falling] = Math.sin(0.1);
        collision.rotW[falling] = Math.cos(0.1);
        collision.velY[falling] = -2;
        collision.step(1.0 / 60.0);
        if (Math.abs(collision.angVelZ[falling]) < 0.001)
            throw 'off-center impact produced no angular impulse';
        near(collision.angVelX[falling], 0, 'planar angular lock x');
        near(collision.angVelY[falling], 0, 'planar angular lock y');
        near(collision.posZ[falling], 0, 'planar translation lock z');

        var collision3D = new World(8, 8);
        collision3D.gravity = new Vec3();
        var ground3D = collision3D.createBody(BodyType.Static, 0, 0);
        collision3D.attachShape(ground3D, ShapeBuilder.makeBox(collision3D.verts, 10, 0.5, 5));
        var falling3D = collision3D.createBody(BodyType.Dynamic, 0, 1);
        collision3D.attachShape(falling3D, ShapeBuilder.makeBox(collision3D.verts, 0.5, 0.5, 1));
        collision3D.rotX[falling3D] = Math.sin(0.1);
        collision3D.rotW[falling3D] = Math.cos(0.1);
        collision3D.velY[falling3D] = -2;
        collision3D.step(1.0 / 60.0);
        if (Math.abs(collision3D.angVelX[falling3D]) < 0.001)
            throw 'off-center 3D impact produced no X angular impulse';

        var filtered = new World(8, 8);
        filtered.gravity = new Vec3();
        var fa = filtered.createBody(BodyType.Dynamic, 0, 0);
        var fb = filtered.createBody(BodyType.Dynamic, 0, 0);
        filtered.attachShape(fa, ShapeBuilder.makeCircle(1), 1, 1);
        filtered.attachShape(fb, ShapeBuilder.makeCircle(1), 2, 2);
        filtered.step(1.0 / 60.0);
        near(filtered.broadPhase.pairCount, 0, 'filtered pair');
        var grouped = new World(8, 8);
        grouped.gravity = new Vec3();
        var ga = grouped.createBody(BodyType.Dynamic, 0, 0);
        var gb = grouped.createBody(BodyType.Dynamic, 0, 0);
        grouped.attachShape(ga, ShapeBuilder.makeCircle(1), 1, 0, 7);
        grouped.attachShape(gb, ShapeBuilder.makeCircle(1), 2, 0, 7);
        grouped.step(1.0 / 60.0);
        near(grouped.broadPhase.pairCount, 1, 'positive group override');
        var excluded = new World(8, 8);
        excluded.gravity = new Vec3();
        var ea = excluded.createBody(BodyType.Dynamic, 0, 0);
        var eb = excluded.createBody(BodyType.Dynamic, 0, 0);
        excluded.attachShape(ea, ShapeBuilder.makeCircle(1), 1, -1, -7);
        excluded.attachShape(eb, ShapeBuilder.makeCircle(1), 1, -1, -7);
        excluded.step(1.0 / 60.0);
        near(excluded.broadPhase.pairCount, 0, 'negative group exclusion');
        checkBroadPhaseTree();
        checkLifecycle();
        checkQueries();
        checkCCD();
        checkKinematicTargets();
        checkKinematicBulk();
        checkBodyTypeSwitch();
        checkSoftStepMaterials();
        checkIndependentContactBatch();
        check3DStack();
        checkTouching3DStacks();
        checkLocalContactInvalidation();
        checkShapeToggle();
        checkShapeReshape();
        checkSensorEvents();
        checkContactEvents();
        checkBatchedJoints();
        checkQueryReach();
        checkMixedContactSolve();
        checkContactFeatureCache();
        checkContactGrowth();
        checkDeepContactsAllocateNothing();
        checkConstraintGraph();
        checkIslandsAndSleep();
        checkDistanceJoints();
        checkHingeJoints();
        HingedChainChecks.run();
        checkPrismaticJoints();
        checkWeldJoints();
        SphericalChecks.run();
        DriveChecks.run();
        CollisionFilterChecks.run();
        RagdollStability.run();
        SnapshotChecks.check();
        ValidationChecks.check();
        checkClipTopology();
        checkManifolds();
        WaterChecks.run();
        BalanceChecks.run();
        Sys.println('Physics checks passed');
    }
}
