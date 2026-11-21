import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyId;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.core.Handles.JointId;

private typedef BonePose = {
    var position:Vec3;
    var rotation:Quat;
    var tip:Vec3;
}

private typedef JointFrame = {
    var axisA:Vec3;
    var axisB:Vec3;
    var refA:Vec3;
    var refB:Vec3;
}

private typedef RagdollMetrics = {
    var anchor:Float;
    var swingError:Float;
    var twistError:Float;
    var maxSwing:Float;
    var maxTwist:Float;
    var floorContacts:Int;
    var sleepFrames:Int;
    var wakes:Int;
    var checksum:Float;
    var finalLinear:Float;
    var finalAngular:Float;
    var swingFrame:Int;
    var twistFrame:Int;
    var windowMove:Float;
    var windowAngle:Float;
    var checkpoint:Float;
    var massRatio:Float;
}

class RagdollStability {
    static inline var DT:Single = 1.0 / 60.0;
    static inline var SWING_LIMIT:Single = 0.7;
    static inline var TWIST_LIMIT:Single = 0.5;
    static var lengths:Array<Float> = [0.9, 0.7, 0.7];

    static function mul(a:Quat, b:Quat):Quat {
        return new Quat(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z);
    }

    static function rotateZ(angle:Float):Quat
        return new Quat(0, 0, Math.sin(angle * 0.5), Math.cos(angle * 0.5));

    static function rotateX(angle:Float):Quat
        return new Quat(Math.sin(angle * 0.5), 0, 0, Math.cos(angle * 0.5));

    static function poseAt(time:Float):Array<BonePose> {
        var anchor = new Vec3(0.15 * Math.sin(2 * time), 3.4 + 0.05 * Math.sin(3 * time),
            0.08 * Math.sin(1.3 * time));
        var parent = new Quat();
        var poses:Array<BonePose> = [];
        for (i in 0...3) {
            var local = mul(rotateZ(0.12 * Math.sin(2 * time + i * 0.7)),
                rotateX(0.10 * Math.sin(1.5 * time + i * 0.5)));
            var rotation = mul(parent, local);
            var half = Quat.rotate(rotation, new Vec3(0, -lengths[i] * 0.5, 0));
            var tip = Vec3.add(anchor, Vec3.scale(half, 2));
            poses.push({position: Vec3.add(anchor, half), rotation: rotation, tip: tip});
            anchor = tip;
            parent = rotation;
        }
        return poses;
    }

    static function attachBone(world:World, body:BodyId, index:Int, density:Float):Void {
        var radius = index == 0 ? 0.17 : (index == 1 ? 0.12 : 0.10);
        var depth = index == 0 ? 0.34 : 0.22;
        world.attachShape(body, ShapeBuilder.makeCapsule(world.verts,
            0, -lengths[index] * 0.5 + radius, 0, lengths[index] * 0.5 - radius,
            depth, radius, 0, density));
    }

    static function jointFrame(a:Quat, b:Quat):JointFrame {
        var axis = new Vec3(0, 1, 0), reference = new Vec3(1, 0, 0);
        return {axisA: Quat.invRotate(a, axis), axisB: Quat.invRotate(b, axis),
            refA: Quat.invRotate(a, reference), refB: Quat.invRotate(b, reference)};
    }

    static function limitAngles(a:Quat, b:Quat, frame:JointFrame):Vec3 {
        var axisA = Quat.rotate(a, frame.axisA), axisB = Quat.rotate(b, frame.axisB);
        var cross = Vec3.cross(axisA, axisB);
        var dot = Math.max(-1.0, Math.min(1.0, Vec3.dot(axisA, axisB)));
        var swing = Math.atan2(Math.sqrt(Vec3.lengthSq(cross)), dot);
        var twist = 0.0;
        if (dot > -0.9999) {
            var align = Vec3.cross(axisB, axisA);
            var inverse = 1.0 / Math.sqrt(2 * (1 + dot));
            var q = new Quat(align.x * inverse, align.y * inverse, align.z * inverse,
                (1 + dot) * inverse);
            var refA = Quat.rotate(a, frame.refA);
            var refB = Quat.rotate(q, Quat.rotate(b, frame.refB));
            twist = Math.atan2(Vec3.dot(axisA, Vec3.cross(refA, refB)), Vec3.dot(refA, refB));
        }
        return new Vec3(swing, twist, 0);
    }

    static function anchorError(world:World, a:BodyId, b:BodyId, lengthA:Float, lengthB:Float):Float {
        var pa = world.getBodyTransform(a), pb = world.getBodyTransform(b);
        var jointA = Vec3.add(pa.position, Quat.rotate(pa.rotation, new Vec3(0, -lengthA * 0.5, 0)));
        var jointB = Vec3.add(pb.position, Quat.rotate(pb.rotation, new Vec3(0, lengthB * 0.5, 0)));
        return Math.sqrt(Vec3.lengthSq(Vec3.sub(jointA, jointB)));
    }

    static function poseChecksum(world:World, bones:Array<BodyId>):Float {
        var sum = 0.0;
        for (body in bones) {
            var pose = world.getBodyTransform(body);
            sum += pose.position.x + 3 * pose.position.y + 7 * pose.position.z
                + 11 * pose.rotation.x + 13 * pose.rotation.y + 17 * pose.rotation.z;
        }
        return sum;
    }

    static function runCase(densities:Array<Float>):RagdollMetrics {
        var world = new World(8, 8, 4);
        var floor = world.createBody(BodyType.Static, 0, -0.25, 0);
        world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 8, 0.25, 4, 0));
        var animated:Array<BodyId> = [];
        var initial = poseAt(0);
        for (i in 0...3) {
            var body = world.createBody(BodyType.Kinematic,
                initial[i].position.x, initial[i].position.y, initial[i].position.z);
            attachBone(world, body, i, 1);
            world.teleportBody(body, initial[i].position, initial[i].rotation);
            animated.push(body);
        }
        for (frame in 0...45) {
            var next = poseAt((frame + 1) * DT);
            for (i in 0...3) world.setKinematicTarget(animated[i], next[i].position, next[i].rotation);
            world.step(DT);
        }
        var before = poseAt(44 * DT), handoff = poseAt(45 * DT);
        for (i in 0...3) {
            var pose = world.getBodyTransform(animated[i]);
            var positionError = Math.sqrt(Vec3.lengthSq(Vec3.sub(pose.position, handoff[i].position)));
            var rotationDot = Math.abs(pose.rotation.x * handoff[i].rotation.x
                + pose.rotation.y * handoff[i].rotation.y + pose.rotation.z * handoff[i].rotation.z
                + pose.rotation.w * handoff[i].rotation.w);
            if (positionError > 0.001 || rotationDot < 0.9999)
                throw 'Kinematic pose did not reach handoff target';
        }
        for (body in animated) world.destroyBody(body);
        var bones:Array<BodyId> = [];
        for (i in 0...3) {
            var pose = handoff[i];
            var body = world.createBody(BodyType.Dynamic, pose.position.x, pose.position.y, pose.position.z);
            attachBone(world, body, i, densities[i]);
            world.teleportBody(body, pose.position, pose.rotation);
            var slot = world.bodySlot(body);
            var velocity = Vec3.scale(Vec3.sub(pose.position, before[i].position), 1.0 / DT);
            var angular = Quat.angularVelocity(before[i].rotation, pose.rotation, DT);
            world.velX[slot] = velocity.x; world.velY[slot] = velocity.y; world.velZ[slot] = velocity.z;
            world.angVelX[slot] = angular.x; world.angVelY[slot] = angular.y; world.angVelZ[slot] = angular.z;
            bones.push(body);
        }
        var joints:Array<JointId> = [];
        var frames:Array<JointFrame> = [];
        for (i in 0...2) {
            var joint = world.createSphericalJoint(bones[i], bones[i + 1], handoff[i].tip,
                new Vec3(0, 1, 0), SWING_LIMIT, -TWIST_LIMIT, TWIST_LIMIT);
            world.setJointCollideConnected(joint, false);
            joints.push(joint);
            frames.push(jointFrame(handoff[i].rotation, handoff[i + 1].rotation));
        }
        world.angVelY[world.bodySlot(bones[2])] += 1.5;
        world.velZ[world.bodySlot(bones[2])] += 0.6;
        var minimumMass = 1.0e30, maximumMass = 0.0;
        for (body in bones) {
            var mass = 1.0 / world.invMassX[world.bodySlot(body)];
            minimumMass = Math.min(minimumMass, mass);
            maximumMass = Math.max(maximumMass, mass);
        }
        var metrics:RagdollMetrics = {anchor: 0, swingError: 0, twistError: 0,
            maxSwing: 0, maxTwist: 0, floorContacts: 0, sleepFrames: 0, wakes: 0, checksum: 0,
            finalLinear: 0, finalAngular: 0, swingFrame: -1, twistFrame: -1,
            windowMove: 0, windowAngle: 0, checkpoint: 0, massRatio: maximumMass / minimumMass};
        var floorSlot = world.bodySlot(floor);
        var restPositions:Array<Vec3> = [];
        var restRotations:Array<Quat> = [];
        for (frame in 0...1200) {
            var activation = frame == 360 || frame == 720 || frame == 960;
            if (activation) {
                for (body in bones)
                    if (world.islands.isAwake[world.bodySlot(body)] != 0)
                        throw 'Ragdoll failed to sleep before activation at frame $frame';
            }
            if (frame < 24 || frame >= 360 && frame < 378
                || frame >= 720 && frame < 738 || frame >= 960 && frame < 978) {
                var target = 0.14 * Math.sin(frame * 0.11);
                for (joint in joints) world.setSphericalDrive(joint, rotateZ(target), 10, 1, 16);
            } else if (frame == 24 || frame == 378 || frame == 738 || frame == 978) {
                for (joint in joints) world.setSphericalDrive(joint, new Quat(), 0, 1, 0);
            }
            if (activation) {
                for (body in bones)
                    if (world.islands.isAwake[world.bodySlot(body)] == 0)
                        throw 'Drive activation did not wake the ragdoll at frame $frame';
                metrics.wakes++;
            }
            world.step(DT);
            if (frame == 60) metrics.checkpoint = poseChecksum(world, bones);
            if (frame == 1140) for (body in bones) {
                var pose = world.getBodyTransform(body);
                restPositions.push(pose.position); restRotations.push(pose.rotation);
            }
            if (frame > 1140) for (i in 0...bones.length) {
                var pose = world.getBodyTransform(bones[i]);
                metrics.windowMove = Math.max(metrics.windowMove,
                    Math.sqrt(Vec3.lengthSq(Vec3.sub(pose.position, restPositions[i]))));
                var dot = Math.abs(pose.rotation.x * restRotations[i].x + pose.rotation.y * restRotations[i].y
                    + pose.rotation.z * restRotations[i].z + pose.rotation.w * restRotations[i].w);
                metrics.windowAngle = Math.max(metrics.windowAngle,
                    2 * Math.acos(Math.min(1, dot)));
            }
            for (body in bones) {
                var slot = world.bodySlot(body), pose = world.getBodyTransform(body);
                for (value in [pose.position.x, pose.position.y, pose.position.z,
                    pose.rotation.x, pose.rotation.y, pose.rotation.z, pose.rotation.w,
                    world.velX[slot], world.velY[slot], world.velZ[slot],
                    world.angVelX[slot], world.angVelY[slot], world.angVelZ[slot]]) {
                    if (!Math.isFinite(value)) throw 'Ragdoll state became non-finite';
                }
            }
            for (i in 0...2) {
                var pa = world.getBodyTransform(bones[i]);
                var pb = world.getBodyTransform(bones[i + 1]);
                var angles = limitAngles(pa.rotation, pb.rotation, frames[i]);
                metrics.anchor = Math.max(metrics.anchor,
                    anchorError(world, bones[i], bones[i + 1], lengths[i], lengths[i + 1]));
                var swingError = Math.max(0, angles.x - SWING_LIMIT);
                var twistError = Math.max(0, Math.abs(angles.y) - TWIST_LIMIT);
                if (swingError > metrics.swingError) { metrics.swingError = swingError; metrics.swingFrame = frame; }
                if (twistError > metrics.twistError) { metrics.twistError = twistError; metrics.twistFrame = frame; }
                metrics.maxSwing = Math.max(metrics.maxSwing, angles.x);
                metrics.maxTwist = Math.max(metrics.maxTwist, Math.abs(angles.y));
            }
            for (i in 0...world.contacts.count)
                if (world.contacts.bodyA[i] == floorSlot || world.contacts.bodyB[i] == floorSlot)
                    metrics.floorContacts++;
            var asleep = true;
            for (body in bones) if (world.islands.isAwake[world.bodySlot(body)] != 0) asleep = false;
            if (asleep) metrics.sleepFrames++;
        }
        metrics.checksum = poseChecksum(world, bones);
        for (body in bones) {
            var slot = world.bodySlot(body);
            metrics.finalLinear = Math.max(metrics.finalLinear, Math.sqrt(
                world.velX[slot] * world.velX[slot] + world.velY[slot] * world.velY[slot]
                + world.velZ[slot] * world.velZ[slot]));
            metrics.finalAngular = Math.max(metrics.finalAngular, Math.sqrt(
                world.angVelX[slot] * world.angVelX[slot] + world.angVelY[slot] * world.angVelY[slot]
                + world.angVelZ[slot] * world.angVelZ[slot]));
        }
        return metrics;
    }

    public static function run():Void {
        var expectedCheckpoints = [-43.2309, 28.2887, 33.0143];
        var caseIndex = 0;
        for (densities in [[3.0, 2.0, 1.0], [0.2, 2.0, 8.0], [1.0, 1.5, 3.4]]) {
            var result = runCase(densities);
            if (!Math.isFinite(result.anchor) || result.anchor > 0.015
                || !Math.isFinite(result.swingError) || result.swingError > 0.09
                || !Math.isFinite(result.twistError) || result.twistError > 0.09)
                throw 'Ragdoll joint errors exceeded tolerance';
            var minimumRatio = caseIndex == 2 ? 1 : 8;
            var maximumRatio = caseIndex == 2 ? 3 : 15;
            if (result.massRatio < minimumRatio || result.massRatio > maximumRatio || result.floorContacts < 100
                || result.maxSwing < 0.3 || result.maxTwist < 0.2)
                throw 'Ragdoll impact or permitted motion was not exercised';
            if (result.sleepFrames < 500 || result.wakes != 3
                || result.finalLinear != 0 || result.finalAngular != 0)
                throw 'Ragdoll failed repeated sleep and wake';
            if (!Math.isFinite(result.checkpoint)
                || Math.abs(result.checkpoint - expectedCheckpoints[caseIndex]) > 0.1)
                throw 'Ragdoll trajectory checkpoint changed: ${result.checkpoint}';
            Sys.println('ragdoll ${densities[0]}/${densities[1]}/${densities[2]}: '
                + 'anchor=${result.anchor}, swing error=${result.swingError}, twist error=${result.twistError}, '
                + 'swing=${result.maxSwing}, twist=${result.maxTwist}, floor=${result.floorContacts}, '
                + 'sleep=${result.sleepFrames}, wakes=${result.wakes}, checksum=${result.checksum}, '
                + 'linear=${result.finalLinear}, angular=${result.finalAngular}, '
                + 'swingFrame=${result.swingFrame}, twistFrame=${result.twistFrame}, '
                + 'windowMove=${result.windowMove}, windowAngle=${result.windowAngle}, '
                + 'checkpoint=${result.checkpoint}, massRatio=${result.massRatio}');
            caseIndex++;
        }
    }

    static function main():Void run();
}
