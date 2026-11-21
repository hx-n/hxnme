package hxn.me.physics.collision;

import hxn.me.physics.geom.ShapeDef;
import hxn.me.math.Quat;
import hxn.me.math.Vec3;
import hxn.me.physics.collision.ManifoldClipper.ClipWorkspace;
import hxn.me.physics.collision.NarrowPhase.NarrowPhaseWorkspace;

/** Per-thread inputs and workspaces for testing candidate pairs; overwritten for each pair. */
class PairScratch {
	public var shapeA:ShapeDef = new ShapeDef(ShapeKind.Point);
	public var shapeB:ShapeDef = new ShapeDef(ShapeKind.Point);
	public var posA:Vec3 = new Vec3();
	public var posB:Vec3 = new Vec3();
	public var rotA:Quat = new Quat();
	public var rotB:Quat = new Quat();
	public var narrow:NarrowPhaseWorkspace = new NarrowPhaseWorkspace();
	public var clip:ClipWorkspace = new ClipWorkspace();

	public function new() {}
}
