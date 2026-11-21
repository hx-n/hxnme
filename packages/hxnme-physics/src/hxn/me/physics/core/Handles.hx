package hxn.me.physics.core;

class Handles {}
abstract BodyId(Int) from Int to Int {}
abstract ShapeId(Int) from Int to Int {}
abstract JointId(Int) from Int to Int {}

enum abstract BodyType(Int) from Int to Int {
	var Static = 0;
	var Kinematic = 1;
	var Dynamic = 2;
}

enum abstract DoFMask(Int) from Int to Int {
	var Locked = 0;
	var Planar = (1 << 0) | (1 << 1) | (1 << 5); // X, Y linear + Z angular (Box2D)
	var Full3D = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5); // 6-DoF (Box3D)
}
