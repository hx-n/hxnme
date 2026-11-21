import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyId;
import hxn.me.physics.core.Handles.BodyType;

class SphericalChecks {
    static function volume(world:World, body:BodyId, density:Float = 1):Void {
        world.attachShape(body, ShapeBuilder.makeCircle(0.15, 0.3, 0, density));
    }

    static function angle(a:Vec3, b:Vec3):Float {
        return Math.acos(Math.max(-1.0, Math.min(1.0, Vec3.dot(a, b))));
    }

    static function anchorError(world:World, a:BodyId, b:BodyId, localA:Vec3, localB:Vec3):Float {
        var pa = world.getBodyTransform(a), pb = world.getBodyTransform(b);
        var wa = Vec3.add(pa.position, Quat.rotate(pa.rotation, localA));
        var wb = Vec3.add(pb.position, Quat.rotate(pb.rotation, localB));
        return Math.sqrt(Vec3.lengthSq(Vec3.sub(wa, wb)));
    }

    public static function run():Void {
        var free = new World(4, 4, 2);
        free.gravity = new Vec3();
        var root = free.createBody(BodyType.Static, 0, 0);
        var end = free.createBody(BodyType.Dynamic, 0, -1);
        volume(free, end);
        var socket = free.createSphericalJoint(root, end, new Vec3(0, -0.5));
        free.angVelX[free.bodySlot(end)] = 2;
        free.angVelZ[free.bodySlot(end)] = 2;
        for (_ in 0...120) free.step(1.0 / 60.0);
        var freePose = free.getBodyTransform(end);
        if (anchorError(free, root, end, new Vec3(0, -0.5), new Vec3(0, 0.5)) > 0.05
            || Math.abs(freePose.rotation.x) + Math.abs(freePose.rotation.z) < 0.1)
            throw 'Free spherical anchor or rotation failed';
        free.destroyJoint(socket);
        var replacement = free.createSphericalJoint(root, end, new Vec3(0, -0.5));
        if (replacement == socket) throw 'Spherical joint handle reused its generation';
        var staleRejected = false;
        try free.destroyJoint(socket) catch (_:Dynamic) staleRejected = true;
        if (!staleRejected) throw 'Stale spherical joint was accepted';

        var cone = new World(4, 4, 2);
        cone.gravity = new Vec3();
        var fixed = cone.createBody(BodyType.Static, 0, 0);
        var swinging = cone.createBody(BodyType.Dynamic, 0, 0);
        volume(cone, swinging);
        cone.createSphericalJoint(fixed, swinging, new Vec3(), new Vec3(0, 1, 0), 0.3);
        cone.angVelZ[cone.bodySlot(swinging)] = 5;
        for (_ in 0...120) cone.step(1.0 / 60.0);
        var swing = angle(new Vec3(0, 1, 0), Quat.rotate(cone.getBodyTransform(swinging).rotation, new Vec3(0, 1, 0)));
        if (!Math.isFinite(swing) || swing > 0.36 || swing < 0.1) throw 'Swing limit failed: $swing';

        var twistWorld = new World(4, 4, 2);
        twistWorld.gravity = new Vec3();
        fixed = twistWorld.createBody(BodyType.Static, 0, 0);
        var twisting = twistWorld.createBody(BodyType.Dynamic, 0, 0);
        volume(twistWorld, twisting);
        twistWorld.createSphericalJoint(fixed, twisting, new Vec3(), new Vec3(0, 1, 0),
            3.14159265, -0.25, 0.25);
        twistWorld.angVelY[twistWorld.bodySlot(twisting)] = 5;
        var maxTwist = 0.0;
        for (_ in 0...120) {
            twistWorld.step(1.0 / 60.0);
            var current = twistWorld.getBodyTransform(twisting).rotation;
            var currentTwist = 2 * Math.atan2(current.y, current.w);
            maxTwist = Math.max(maxTwist, Math.abs(currentTwist));
        }
        var q = twistWorld.getBodyTransform(twisting).rotation;
        var twist = 2 * Math.atan2(q.y, q.w);
        if (!Math.isFinite(twist) || maxTwist > 0.36 || maxTwist < 0.2)
            throw 'Twist limit failed: final=$twist, max=$maxTwist';
        twistWorld.teleportBody(twisting, new Vec3(), new Quat());
        twistWorld.angVelY[twistWorld.bodySlot(twisting)] = -5;
        var minTwist = 0.0;
        for (_ in 0...120) {
            twistWorld.step(1.0 / 60.0);
            var current = twistWorld.getBodyTransform(twisting).rotation;
            minTwist = Math.min(minTwist, 2 * Math.atan2(current.y, current.w));
        }
        if (minTwist < -0.36 || minTwist > -0.2) throw 'Lower twist limit failed: $minTwist';

        var combined = new World(4, 4, 2);
        combined.gravity = new Vec3();
        fixed = combined.createBody(BodyType.Static, 0, 0);
        var turning = combined.createBody(BodyType.Dynamic, 0, 0);
        volume(combined, turning);
        combined.createSphericalJoint(fixed, turning, new Vec3(), new Vec3(0, 1, 0), 0.4, -0.3, 0.3);
        combined.angVelY[combined.bodySlot(turning)] = 4;
        combined.angVelZ[combined.bodySlot(turning)] = 4;
        var maxSwing = 0.0, maxCombinedTwist = 0.0;
        for (_ in 0...120) {
            combined.step(1.0 / 60.0);
            var pose = combined.getBodyTransform(turning);
            maxSwing = Math.max(maxSwing, angle(new Vec3(0, 1, 0), Quat.rotate(pose.rotation, new Vec3(0, 1, 0))));
            maxCombinedTwist = Math.max(maxCombinedTwist, Math.abs(2 * Math.atan2(pose.rotation.y, pose.rotation.w)));
        }
        if (!Math.isFinite(maxSwing) || !Math.isFinite(maxCombinedTwist)
            || maxSwing > 0.5 || maxCombinedTwist > 0.4
            || maxSwing < 0.2 || maxCombinedTwist < 0.2)
            throw 'Combined swing/twist limit failed: $maxSwing, $maxCombinedTwist';

        var chain = new World(6, 6, 4);
        var support = chain.createBody(BodyType.Static, 0, 0);
        var upper = chain.createBody(BodyType.Dynamic, 0, -1);
        var lower = chain.createBody(BodyType.Dynamic, 0, -2);
        volume(chain, upper, 4);
        volume(chain, lower, 1);
        chain.createSphericalJoint(support, upper, new Vec3(0, -0.5), new Vec3(0, 1, 0), 0.6, -0.5, 0.5);
        chain.createSphericalJoint(upper, lower, new Vec3(0, -1.5), new Vec3(0, 1, 0), 0.6, -0.5, 0.5);
        chain.velX[chain.bodySlot(lower)] = 1.5;
        for (_ in 0...240) chain.step(1.0 / 60.0);
        var firstError = anchorError(chain, support, upper, new Vec3(0, -0.5), new Vec3(0, 0.5));
        var secondError = anchorError(chain, upper, lower, new Vec3(0, -0.5), new Vec3(0, 0.5));
        if (!Math.isFinite(firstError) || !Math.isFinite(secondError)
            || firstError > 0.1 || secondError > 0.1)
            throw 'Unequal-mass chain anchors diverged: $firstError, $secondError';

        var driven = new World(4, 4, 2);
        driven.gravity = new Vec3();
        var mover = driven.createBody(BodyType.Kinematic, 0, 0);
        var passenger = driven.createBody(BodyType.Dynamic, 0, 1);
        volume(driven, passenger);
        driven.createSphericalJoint(mover, passenger, new Vec3(0, 0.5));
        driven.setKinematicTarget(mover, new Vec3(0.5, 0, 0), new Quat());
        driven.step(1.0 / 60.0);
        driven.step(1.0 / 60.0);
        var drivenError = anchorError(driven, mover, passenger, new Vec3(0, 0.5), new Vec3(0, -0.5));
        if (drivenError > 0.1) throw 'Kinematic spherical anchor failed: $drivenError';
        driven.destroyBody(passenger);
        if (driven.joints.count != 0) throw 'Body destruction retained a spherical joint';

        var planar = new World(4, 4, 2);
        var planarBase = planar.createBody(BodyType.Static, 0, 0);
        var planarBody = planar.createBody(BodyType.Dynamic, 0, 0);
        planar.attachShape(planarBody, ShapeBuilder.makeCircle(0.2));
        var planarRejected = false;
        try planar.createSphericalJoint(planarBase, planarBody, new Vec3())
        catch (_:Dynamic) planarRejected = true;
        if (!planarRejected) throw 'Spherical joint accepted a planar-only pair';

        var mixed = new World(4, 4, 2);
        mixed.gravity = new Vec3();
        var flat = mixed.createBody(BodyType.Dynamic, 0, 0);
        var solid = mixed.createBody(BodyType.Dynamic, 0, 1);
        mixed.attachShape(flat, ShapeBuilder.makeCircle(0.15));
        volume(mixed, solid);
        mixed.createSphericalJoint(flat, solid, new Vec3(0, 0.5));
        mixed.velZ[mixed.bodySlot(solid)] = 2;
        for (_ in 0...60) mixed.step(1.0 / 60.0);
        if (Math.abs(mixed.getBodyTransform(flat).position.z) > 1e-5
            || Math.abs(mixed.angVelX[mixed.bodySlot(flat)]) > 1e-5
            || Math.abs(mixed.angVelY[mixed.bodySlot(flat)]) > 1e-5
            || anchorError(mixed, flat, solid, new Vec3(0, 0.5), new Vec3(0, -0.5)) > 0.1)
            throw 'Mixed planar/3D spherical joint broke locked axes';
        Sys.println('Spherical checks passed');
    }

    static function main():Void run();
}
