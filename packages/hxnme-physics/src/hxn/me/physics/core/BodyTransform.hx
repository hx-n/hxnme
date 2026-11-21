package hxn.me.physics.core;

import hxn.me.math.Vec3;
import hxn.me.math.Quat;

class BodyTransform {
	public var position:Vec3;
	public var rotation:Quat;

	public function new(position:Vec3, rotation:Quat) {
		this.position = position;
		this.rotation = rotation;
	}
}
