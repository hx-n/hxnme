import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyType;

class DriveChecks {
    static function twist(q:Quat):Float return 2.0 * Math.atan2(q.y, q.w);
    static function aroundY(angle:Float):Quat return new Quat(0, Math.sin(angle * 0.5), 0, Math.cos(angle * 0.5));
    static function aroundX(angle:Float):Quat return new Quat(Math.sin(angle * 0.5), 0, 0, Math.cos(angle * 0.5));
    static function addVolume(world:World, body:Int):Void
        world.attachShape(body, ShapeBuilder.makeCircle(0.15, 0.3));

    public static function run():Void {
        var world = new World(4, 4, 2);
        world.gravity = new Vec3();
        var root = world.createBody(BodyType.Static, 0, 0);
        var arm = world.createBody(BodyType.Dynamic, 0, 0);
        addVolume(world, arm);
        var joint = world.createSphericalJoint(root, arm, new Vec3(), new Vec3(0, 1, 0), 0.5, -0.3, 0.3);
        world.setSphericalDrive(joint, aroundY(0.2), 12, 1, 20);
        var tailError = 0.0;
        for (frame in 0...120) {
            world.step(1.0 / 60.0);
            if (frame >= 90) tailError = Math.max(tailError, Math.abs(twist(world.getBodyTransform(arm).rotation) - 0.2));
        }
        var settled = twist(world.getBodyTransform(arm).rotation);
        if (Math.abs(settled - 0.2) > 0.03 || tailError > 0.03)
            throw 'Drive failed to settle: $settled, tail=$tailError';
        world.setSphericalDrive(joint, aroundY(1.0), 12, 1, 20);
        for (_ in 0...120) world.step(1.0 / 60.0);
        var limited = twist(world.getBodyTransform(arm).rotation);
        if (Math.abs(limited - 0.3) > 0.04) throw 'Drive exceeded twist limit: $limited';
        world.setSphericalDrive(joint, aroundY(-1.0), 12, 1, 20);
        for (_ in 0...120) world.step(1.0 / 60.0);
        limited = twist(world.getBodyTransform(arm).rotation);
        if (Math.abs(limited + 0.3) > 0.04) throw 'Drive missed lower twist limit: $limited';
        world.setSphericalDrive(joint, aroundX(1.0), 12, 1, 20);
        for (_ in 0...120) world.step(1.0 / 60.0);
        var pose = world.getBodyTransform(arm).rotation;
        var swing = 2.0 * Math.atan2(pose.x, pose.w);
        if (Math.abs(swing - 0.5) > 0.05) throw 'Drive missed swing boundary: $swing';
        world.setSphericalDrive(joint, new Quat(), 0, 1, 0);
        world.angVelY[world.bodySlot(arm)] = 2;
        world.step(1.0 / 60.0);
        if (world.angVelY[world.bodySlot(arm)] < 1.0) throw 'Disabled drive resisted passive motion';
        var rejected = false;
        try world.setSphericalDrive(joint, new Quat(), -1, 1, 1) catch (_:Dynamic) rejected = true;
        if (!rejected) throw 'Invalid drive gain accepted';
        world.destroyJoint(joint);
        rejected = false;
        try world.setSphericalDrive(joint, new Quat(), 1, 1, 1) catch (_:Dynamic) rejected = true;
        if (!rejected) throw 'Stale drive joint accepted';

        var sleeping = new World(4, 4, 2);
        sleeping.gravity = new Vec3();
        var restRoot = sleeping.createBody(BodyType.Static, 0, 0);
        var restArm = sleeping.createBody(BodyType.Dynamic, 0, 0);
        addVolume(sleeping, restArm);
        var restJoint = sleeping.createSphericalJoint(restRoot, restArm, new Vec3());
        for (_ in 0...40) sleeping.step(1.0 / 60.0);
        if (sleeping.islands.isAwake[sleeping.bodySlot(restArm)] != 0) throw 'Resting joint failed to sleep';
        sleeping.setSphericalDrive(restJoint, aroundY(0.2), 12, 1, 20);
        if (sleeping.islands.isAwake[sleeping.bodySlot(restArm)] == 0) throw 'Target change did not wake joint';

        var chain = new World(6, 6, 4);
        chain.gravity = new Vec3();
        var base = chain.createBody(BodyType.Static, 0, 0);
        var upper = chain.createBody(BodyType.Dynamic, 0, -1);
        var lower = chain.createBody(BodyType.Dynamic, 0, -2);
        addVolume(chain, upper); addVolume(chain, lower);
        var shoulder = chain.createSphericalJoint(base, upper, new Vec3(0, -0.5));
        var elbow = chain.createSphericalJoint(upper, lower, new Vec3(0, -1.5));
        var maxError = 0.0;
        for (frame in 0...240) {
            var target = 0.18 * Math.sin(frame * 0.03);
            chain.setSphericalDrive(shoulder, aroundY(target), 12, 1, 20);
            chain.setSphericalDrive(elbow, aroundY(-target), 12, 1, 20);
            chain.step(1.0 / 60.0);
            if (frame > 60) {
                var qa = chain.getBodyTransform(upper).rotation;
                var qb = chain.getBodyTransform(lower).rotation;
                maxError = Math.max(maxError, Math.abs(twist(qa) - target));
                maxError = Math.max(maxError, Math.abs(twist(qb) - twist(qa) + target));
            }
        }
        if (!Math.isFinite(maxError) || maxError > 0.15) throw 'Moving chain drive error: $maxError';

        var capped = new World(4, 4, 2);
        capped.gravity = new Vec3();
        var support = capped.createBody(BodyType.Static, 0, 0);
        var rotor = capped.createBody(BodyType.Dynamic, 0, 0);
        addVolume(capped, rotor);
        var drive = capped.createSphericalJoint(support, rotor, new Vec3());
        capped.setSphericalDrive(drive, aroundY(1), 12, 1, 0.01);
        capped.step(1.0 / 60.0);
        var speed = capped.angVelY[capped.bodySlot(rotor)];
        if (speed <= 0 || speed > capped.invIyy[capped.bodySlot(rotor)] * 0.01 / 60.0 * 1.1)
            throw 'Torque cap failed: $speed';

        var hingeWorld = new World(4, 4, 2);
        hingeWorld.gravity = new Vec3();
        var hingeRoot = hingeWorld.createBody(BodyType.Static, 0, 0);
        var hingeArm = hingeWorld.createBody(BodyType.Dynamic, 0, 0);
        hingeWorld.attachShape(hingeArm, ShapeBuilder.makeCircle(0.2));
        var hinge = hingeWorld.createHingeJoint(hingeRoot, hingeArm, new Vec3(),
            new Vec3(0, 0, 1), -0.25, 0.25);
        hingeWorld.setHingeDrive(hinge, 0.15, 12, 1, 20);
        for (_ in 0...120) hingeWorld.step(1.0 / 60.0);
        var hingeAngle = 2.0 * Math.atan2(hingeWorld.getBodyTransform(hingeArm).rotation.z,
            hingeWorld.getBodyTransform(hingeArm).rotation.w);
        if (Math.abs(hingeAngle - 0.15) > 0.03) throw 'Hinge drive failed to settle: $hingeAngle';
        hingeWorld.setHingeDrive(hinge, 1.0, 12, 1, 20);
        for (_ in 0...120) hingeWorld.step(1.0 / 60.0);
        var hingePose = hingeWorld.getBodyTransform(hingeArm).rotation;
        hingeAngle = 2.0 * Math.atan2(hingePose.z, hingePose.w);
        if (Math.abs(hingeAngle - 0.25) > 0.04) throw 'Hinge drive missed limit: $hingeAngle';
        hingeWorld.setHingeDrive(hinge, 0, 0, 1, 0);
        hingeWorld.angVelZ[hingeWorld.bodySlot(hingeArm)] = -2;
        hingeWorld.step(1.0 / 60.0);
        if (hingeWorld.angVelZ[hingeWorld.bodySlot(hingeArm)] > -1)
            throw 'Disabled hinge drive resisted passive motion';
        checkSlenderSwing();
        Sys.println('Drive checks passed');
    }

    /** A long, thin forearm driven to a swing between two axes settles on it; its weak twist axis does not drift. */
    static function checkSlenderSwing():Void {
        for (stiffness in [5.0, 20.0]) {
            var world = new World(4, 4, 2);
            world.gravity = new Vec3();
            var upper = world.createBody(BodyType.Kinematic, 0.15, 1.5, 0);
            world.attachShape(upper, ShapeBuilder.makeBox(world.verts, 0.15, 0.04, 0.04, 0));
            var fore = world.createBody(BodyType.Dynamic, 0.45, 1.5, 0);
            world.attachShape(fore, ShapeBuilder.makeBox(world.verts, 0.15, 0.04, 0.04, 0));
            var elbow = world.createSphericalJoint(upper, fore, new Vec3(0.3, 1.5, 0), new Vec3(1, 0, 0));
            world.setJointCollideConnected(elbow, false);
            var half = 25 * Math.PI / 180, s = Math.sin(half) / Math.sqrt(2);
            var target = new Quat(0, s, s, Math.cos(half));
            world.setSphericalDrive(elbow, target, stiffness, 1, 50);
            for (_ in 0...240) world.step(1.0 / 60.0);
            var q = world.getBodyTransform(fore).rotation;
            var dot = Math.abs(q.x * target.x + q.y * target.y + q.z * target.z + q.w * target.w);
            var error = 2 * Math.acos(Math.min(1.0, dot));
            if (error > 0.01) throw 'slender spherical drive at stiffness $stiffness missed by $error rad';
        }
    }

    static function main():Void run();
}
