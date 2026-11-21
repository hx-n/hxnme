import hxn.me.physics.geom.ShapeBuilder;
import hxn.me.math.Vec3;
import hxn.me.physics.core.World;

/** Hanging rectangular links with an analytic mass and inertia reference. */
class HingeChain {
	public final world:World;
	public final bodies:Array<Int> = [];
	public final spatial:Bool;
	public final mass:Float;
	public final scale:Float;
	final halfWidth:Float;

	public function new(spatial:Bool = true, collide:Bool = true, chains:Int = 1,
		halfWidth:Float = 0.25, supplied:World = null) {
		this.spatial = spatial; this.halfWidth = halfWidth;
		world = supplied == null ? new World(chains * 11 + 8, chains * 10 + 8, chains * 10 + 8) : supplied;
		mass = 2 * halfWidth * 0.1 * (spatial ? 0.1 : 1);
		scale = chains * 10 * mass * 9.81 * 2.5;
		for (c in 0...chains) {
			var previous = world.createBody(Static, 0, 10, c);
			for (k in 0...10) {
				var body = world.createBody(Dynamic, (k + 1) * 0.5, 10, c);
				world.attachShape(body, ShapeBuilder.makeBox(world.verts, halfWidth, 0.05, spatial ? 0.1 : 0, 0.01));
				var hinge = world.createHingeJoint(previous, body, new Vec3(k * 0.5 + 0.25, 10, c), new Vec3(0, 0, 1));
				if (!collide) world.setJointCollideConnected(hinge, false);
				bodies.push(world.bodySlot(body)); previous = body;
			}
		}
	}

	/** Rectangle/cuboid kinetic energy plus gravitational potential relative to release height. */
	public function energy(gravity:Float = 9.81):Float {
		var w = world, sum = 0.0, width = 2 * halfWidth;
		var ix = mass * 0.02 / 12, iy = mass * (width * width + 0.01) / 12;
		var iz = mass * (width * width + 0.01) / 12;
		for (b in bodies) {
			var vx:Float = w.velX[b], vy:Float = w.velY[b], vz:Float = w.velZ[b];
			var ax:Float = w.angVelX[b], ay:Float = w.angVelY[b], az:Float = w.angVelZ[b];
			var qx:Float = w.rotX[b], qy:Float = w.rotY[b], qz:Float = w.rotZ[b], qw:Float = w.rotW[b];
			var x = (1 - 2 * (qy*qy + qz*qz))*ax + 2*(qx*qy + qz*qw)*ay + 2*(qx*qz - qy*qw)*az;
			var y = 2*(qx*qy - qz*qw)*ax + (1 - 2*(qx*qx + qz*qz))*ay + 2*(qy*qz + qx*qw)*az;
			var z = 2*(qx*qz + qy*qw)*ax + 2*(qy*qz - qx*qw)*ay + (1 - 2*(qx*qx + qy*qy))*az;
			sum += 0.5 * mass * (vx*vx + vy*vy + vz*vz) + 0.5 * (ix*x*x + iy*y*y + iz*z*z)
				+ mass * gravity * (w.worldCenterY[b] - 10);
		}
		return sum;
	}
}
