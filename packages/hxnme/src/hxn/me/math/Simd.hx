package hxn.me.math;

import hl.Bytes;
import hxn.Float32Buffer;
#if (ash_simd && hl)
import ash.simd.Float32x4;
#end

class Simd {}

class SimdBatch {
	/** Adds gravity to the velocity of every active body with mass along that axis. */
	public static inline function integrateVelocities(count:Int, velX:Float32Buffer, velY:Float32Buffer, velZ:Float32Buffer, invMassX:Float32Buffer,
			invMassY:Float32Buffer, invMassZ:Float32Buffer, gx:Single, gy:Single, gz:Single, dt:Single, integrationMask:Float32Buffer = null,
			constants:Bytes = null):Void {
		var i = 0;

		#if (ash_simd && hl)
		// Lane constants go through a caller-owned buffer: Float32x4.splat allocates a fresh vector per call.
		if (constants == null)
			constants = new Bytes(80);
		for (lane in 0...4) {
			var o = lane << 2;
			constants.setF32(o, dt);
			constants.setF32(16 + o, gx * dt);
			constants.setF32(32 + o, gy * dt);
			constants.setF32(48 + o, gz * dt);
			constants.setF32(64 + o, 0.0);
		}
		var vGxDt = Float32x4.load(constants, 16);
		var vGyDt = Float32x4.load(constants, 32);
		var vGzDt = Float32x4.load(constants, 48);
		var vZero = Float32x4.load(constants, 64);

		var simdLimit = count & ~3;
		while (i < simdLimit) {
			var at = Float32Buffer.hlOffset(i);
			// Gravity only where the body is active and has mass along the axis.
			var agx = Float32x4.select(Float32x4.load(invMassX.hlBytes(), at).gt(vZero), vGxDt, vZero);
			var agy = Float32x4.select(Float32x4.load(invMassY.hlBytes(), at).gt(vZero), vGyDt, vZero);
			var agz = Float32x4.select(Float32x4.load(invMassZ.hlBytes(), at).gt(vZero), vGzDt, vZero);
			if (integrationMask != null) {
				var active = Float32x4.load(integrationMask.hlBytes(), at).gt(vZero);
				agx = Float32x4.select(active, agx, vZero);
				agy = Float32x4.select(active, agy, vZero);
				agz = Float32x4.select(active, agz, vZero);
			}
			(Float32x4.load(velX.hlBytes(), at) + agx).store(velX.hlBytes(), at);
			(Float32x4.load(velY.hlBytes(), at) + agy).store(velY.hlBytes(), at);
			(Float32x4.load(velZ.hlBytes(), at) + agz).store(velZ.hlBytes(), at);
			i += 4;
		}
		#end

		while (i < count) {
			if (integrationMask != null && integrationMask[i] == 0.0) {
				i++;
				continue;
			}
			if (invMassX[i] > 0.0)
				velX[i] += gx * dt;
			if (invMassY[i] > 0.0)
				velY[i] += gy * dt;
			if (invMassZ[i] > 0.0)
				velZ[i] += gz * dt;
			i++;
		}
	}

	/** Moves every active body by its velocity over `dt`. */
	public static inline function integratePositions(count:Int, posX:Float32Buffer, posY:Float32Buffer, posZ:Float32Buffer, velX:Float32Buffer, velY:Float32Buffer,
			velZ:Float32Buffer, dt:Single, integrationMask:Float32Buffer = null, constants:Bytes = null):Void {
		var i = 0;

		#if (ash_simd && hl)
		if (constants == null)
			constants = new Bytes(80);
		for (lane in 0...4) {
			var o = lane << 2;
			constants.setF32(o, dt);
			constants.setF32(64 + o, 0.0);
		}
		var vDt = Float32x4.load(constants, 0);
		var vZero = Float32x4.load(constants, 64);

		var simdLimit = count & ~3;
		while (i < simdLimit) {
			var at = Float32Buffer.hlOffset(i);
			var dx = Float32x4.load(velX.hlBytes(), at) * vDt;
			var dy = Float32x4.load(velY.hlBytes(), at) * vDt;
			var dz = Float32x4.load(velZ.hlBytes(), at) * vDt;
			if (integrationMask != null) {
				var active = Float32x4.load(integrationMask.hlBytes(), at).gt(vZero);
				dx = Float32x4.select(active, dx, vZero);
				dy = Float32x4.select(active, dy, vZero);
				dz = Float32x4.select(active, dz, vZero);
			}
			(Float32x4.load(posX.hlBytes(), at) + dx).store(posX.hlBytes(), at);
			(Float32x4.load(posY.hlBytes(), at) + dy).store(posY.hlBytes(), at);
			(Float32x4.load(posZ.hlBytes(), at) + dz).store(posZ.hlBytes(), at);
			i += 4;
		}
		#end

		while (i < count) {
			if (integrationMask != null && integrationMask[i] == 0.0) {
				i++;
				continue;
			}
			posX[i] += velX[i] * dt;
			posY[i] += velY[i] * dt;
			posZ[i] += velZ[i] * dt;
			i++;
		}
	}
}
