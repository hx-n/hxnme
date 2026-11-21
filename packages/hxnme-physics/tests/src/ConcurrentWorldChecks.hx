import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.physics.core.World;
import hxn.me.physics.core.Handles.BodyId;
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.WorkerPool;

class ConcurrentWorldChecks {
    static inline var WORLD_COUNT = 16;
    static inline var FRAMES = 20;

    static function makeWorld():World {
        var world = new World(9, 9);
        var floor = world.createBody(BodyType.Static, 0, -0.25);
        world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 2, 0.25, 0, 0));
        var chain:Array<BodyId> = [];
        for (row in 0...8) {
            var body = world.createBody(BodyType.Dynamic, 0, 0.49 + row * 0.98);
            world.attachShape(body, ShapeBuilder.makeBox(world.verts, 0.5, 0.5, 0, 0));
            if (chain.length > 0) world.createDistanceJoint(chain[chain.length - 1], body, 0.98);
            chain.push(body);
        }
        return world;
    }

    public static function run():Void {
        var serial = [for (_ in 0...WORLD_COUNT) makeWorld()];
        var concurrent = [for (_ in 0...WORLD_COUNT) makeWorld()];
        var dt = 1.0 / 60.0;
        for (_ in 0...FRAMES) for (world in serial) world.step(dt);

        // Each of 4 workers steps every fourth world. The pool's shutdown waits
        // for its threads, so none is still running when the program exits.
        var pool = new WorkerPool(4);
        var job = function(worker:Int) {
            var i = worker;
            while (i < WORLD_COUNT) {
                concurrent[i].step(dt);
                i += 4;
            }
        };
        for (_ in 0...FRAMES)
            pool.run(4, job);
        pool.shutdown();

        for (i in 0...WORLD_COUNT) {
            var expected = serial[i], actual = concurrent[i];
            for (body in 0...expected.bodyCount) {
                if (Math.abs(expected.posX[body] - actual.posX[body]) > 1e-5
                    || Math.abs(expected.posY[body] - actual.posY[body]) > 1e-5
                    || Math.abs(expected.velX[body] - actual.velX[body]) > 1e-5
                    || Math.abs(expected.velY[body] - actual.velY[body]) > 1e-5)
                    throw 'Concurrent world state diverged at world $i body $body: expected y=${expected.posY[body]} vy=${expected.velY[body]}, actual y=${actual.posY[body]} vy=${actual.velY[body]}';
            }
        }
    }

    static function main():Void {
        run();
        Sys.println('Concurrent world checks passed');
    }
}
