import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.core.Handles.ShapeId;

class CollisionFilterChecks {
    static function touches(world:World, a:ShapeId, b:ShapeId):Bool {
        var sa = world.shapeSlot(a), sb = world.shapeSlot(b);
        for (i in 0...world.contacts.count) {
            if (world.contacts.shapeA[i] == sa && world.contacts.shapeB[i] == sb
                || world.contacts.shapeA[i] == sb && world.contacts.shapeB[i] == sa) return true;
        }
        return false;
    }

    static function pairOrder(world:World):String {
        var order = '';
        for (i in 0...world.broadPhase.pairCount) {
            var offset = 2 * i;
            order += '${world.broadPhase.pairs[offset]}:${world.broadPhase.pairs[offset + 1]},';
        }
        return order;
    }

    public static function run():Void {
        var world = new World(6, 6, 6);
        world.gravity = new Vec3();
        var root = world.createBody(BodyType.Static, 0, 0);
        var middle = world.createBody(BodyType.Dynamic, 0, 0);
        var tip = world.createBody(BodyType.Dynamic, 0, 0);
        var rootShape = world.attachShape(root, ShapeBuilder.makeCircle(0.5));
        var middleShape = world.attachShape(middle, ShapeBuilder.makeCircle(0.5));
        var tipShape = world.attachShape(tip, ShapeBuilder.makeCircle(0.5));
        var rootJoint = world.createDistanceJoint(root, middle, 0);
        var tipJoint = world.createDistanceJoint(middle, tip, 0);
        world.setJointCollideConnected(rootJoint, false);
        world.setJointCollideConnected(rootJoint, false);
        world.setJointCollideConnected(tipJoint, false);
        world.step(1.0 / 60.0);
        if (touches(world, rootShape, middleShape) || touches(world, middleShape, tipShape)
            || !touches(world, rootShape, tipShape)) throw 'Selective connected-pair filtering failed';
        var order = pairOrder(world);
        world.setJointCollideConnected(rootJoint, true);
        world.step(1.0 / 60.0);
        if (!touches(world, rootShape, middleShape) || touches(world, middleShape, tipShape)
            || !touches(world, rootShape, tipShape)) throw 'Reenabled joint collision failed';
        if (pairOrder(world) != order) throw 'Joint filtering reordered broad-phase pairs';

        var secondJoint = world.createDistanceJoint(root, middle, 0);
        world.setJointCollideConnected(secondJoint, false);
        world.step(1.0 / 60.0);
        if (touches(world, rootShape, middleShape)) throw 'Parallel joint exclusion failed';
        world.destroyJoint(secondJoint);
        world.step(1.0 / 60.0);
        if (!touches(world, rootShape, middleShape)) throw 'Destroyed joint left an exclusion';
        var recycledJoint = world.createDistanceJoint(root, tip, 0);
        if (recycledJoint == secondJoint) throw 'Joint generation was not advanced';
        world.step(1.0 / 60.0);
        if (!touches(world, rootShape, tipShape)) throw 'Reused joint inherited collision exclusion';
        var staleRejected = false;
        try world.setJointCollideConnected(secondJoint, false) catch (_:Dynamic) staleRejected = true;
        if (!staleRejected) throw 'Stale joint changed collision filtering';
        world.destroyJoint(recycledJoint);
        world.destroyJoint(tipJoint);
        world.step(1.0 / 60.0);
        if (!touches(world, middleShape, tipShape)) throw 'Destroyed tip joint left an exclusion';

        world.setJointCollideConnected(rootJoint, false);
        var middleSlot = world.bodySlot(middle);
        world.destroyBody(middle);
        var replacement = world.createBody(BodyType.Dynamic, 0, 0);
        if (world.bodySlot(replacement) != middleSlot) throw 'Body slot was not reused';
        var replacementShape = world.attachShape(replacement, ShapeBuilder.makeCircle(0.5));
        world.step(1.0 / 60.0);
        if (!touches(world, rootShape, replacementShape)) throw 'Body slot retained an exclusion';
        staleRejected = false;
        try world.setJointCollideConnected(rootJoint, false) catch (_:Dynamic) staleRejected = true;
        if (!staleRejected) throw 'Stale joint changed collision filtering';
        Sys.println('Collision filter checks passed: pair order=$order');
    }

    static function main():Void run();
}
