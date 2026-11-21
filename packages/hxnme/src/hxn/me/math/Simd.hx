package hxn.me.math;

import hl.Bytes;
#if ash_simd
import ash.simd.Float32x4;
#end

class Simd {}

/**
 * Zero-cost SoA float buffer backed directly by `hl.Bytes`.
 * Supports standard `buf[i]` indexing AND passes directly to `ash.simd.Float32x4` without casting.
 */
abstract FloatBuffer(Bytes) from Bytes to Bytes {
	public inline function new(count:Int) {
		var byteLen = count << 2;
		var b = new Bytes(byteLen);
		b.fill(0, byteLen, 0);
		this = b;
	}

	@:arrayAccess
	public inline function get(i:Int):Single {
		return this.getF32(i << 2);
	}

	@:arrayAccess
	public inline function set(i:Int, v:Single):Single {
		this.setF32(i << 2, v);
		return v;
	}
}

/** SoA 32-bit integer buffer backed by `hl.Bytes`. */
abstract IntBuffer(Bytes) from Bytes to Bytes {
	public inline function new(count:Int) {
		var byteLen = count << 2;
		var b = new Bytes(byteLen);
		b.fill(0, byteLen, 0);
		this = b;
	}

	@:arrayAccess
	public inline function get(i:Int):Int {
		return this.getI32(i << 2);
	}

	@:arrayAccess
	public inline function set(i:Int, v:Int):Int {
		this.setI32(i << 2, v);
		return v;
	}
}

/** SoA double buffer backed by `hl.Bytes`, for values composed in long dependency chains. */
abstract DoubleBuffer(Bytes) from Bytes to Bytes {
	public inline function new(count:Int) {
		var byteLen = count << 3;
		var b = new Bytes(byteLen);
		b.fill(0, byteLen, 0);
		this = b;
	}

	@:arrayAccess
	public inline function get(i:Int):Float {
		return this.getF64(i << 3);
	}

	@:arrayAccess
	public inline function set(i:Int, v:Float):Float {
		this.setF64(i << 3, v);
		return v;
	}
}

class SimdBatch {
	/** Adds gravity to the velocity of every active body with mass along that axis. */
	public static inline function integrateVelocities(count:Int, velX:FloatBuffer, velY:FloatBuffer, velZ:FloatBuffer, invMassX:FloatBuffer,
			invMassY:FloatBuffer, invMassZ:FloatBuffer, gx:Single, gy:Single, gz:Single, dt:Single, integrationMask:FloatBuffer = null,
			constants:Bytes = null):Void {
		var i = 0;

		#if ash_simd
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
			var byteOff = i << 2;
			// Gravity only where the body is active and has mass along the axis.
			var agx = Float32x4.select(Float32x4.load(invMassX, byteOff).gt(vZero), vGxDt, vZero);
			var agy = Float32x4.select(Float32x4.load(invMassY, byteOff).gt(vZero), vGyDt, vZero);
			var agz = Float32x4.select(Float32x4.load(invMassZ, byteOff).gt(vZero), vGzDt, vZero);
			if (integrationMask != null) {
				var active = Float32x4.load(integrationMask, byteOff).gt(vZero);
				agx = Float32x4.select(active, agx, vZero);
				agy = Float32x4.select(active, agy, vZero);
				agz = Float32x4.select(active, agz, vZero);
			}
			(Float32x4.load(velX, byteOff) + agx).store(velX, byteOff);
			(Float32x4.load(velY, byteOff) + agy).store(velY, byteOff);
			(Float32x4.load(velZ, byteOff) + agz).store(velZ, byteOff);
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
	public static inline function integratePositions(count:Int, posX:FloatBuffer, posY:FloatBuffer, posZ:FloatBuffer, velX:FloatBuffer, velY:FloatBuffer,
			velZ:FloatBuffer, dt:Single, integrationMask:FloatBuffer = null, constants:Bytes = null):Void {
		var i = 0;

		#if ash_simd
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
			var byteOff = i << 2;
			var dx = Float32x4.load(velX, byteOff) * vDt;
			var dy = Float32x4.load(velY, byteOff) * vDt;
			var dz = Float32x4.load(velZ, byteOff) * vDt;
			if (integrationMask != null) {
				var active = Float32x4.load(integrationMask, byteOff).gt(vZero);
				dx = Float32x4.select(active, dx, vZero);
				dy = Float32x4.select(active, dy, vZero);
				dz = Float32x4.select(active, dz, vZero);
			}
			(Float32x4.load(posX, byteOff) + dx).store(posX, byteOff);
			(Float32x4.load(posY, byteOff) + dy).store(posY, byteOff);
			(Float32x4.load(posZ, byteOff) + dz).store(posZ, byteOff);
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
