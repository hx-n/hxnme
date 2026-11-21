# hxnme

The kernel of hxnme. The package `hxn.me.math` contains:

- `Vec3`, `Quat` and `Mat3`: vectors, quaternions and 3×3 matrices, in plain
  Haxe.
- `FloatBuffer`, `IntBuffer` and `DoubleBuffer`: fixed-length arrays of 32-bit
  floats, 32-bit integers and 64-bit floats over `hl.Bytes`.
- `SimdBatch`: velocity and position integration for the physics, 4 bodies per
  iteration with `-D ash_simd`, and a scalar loop without it.
- `Grow`: static functions that copy an array or a buffer into one with a
  larger capacity.

The buffers, `SimdBatch` and `Grow` use HashLink types and require the
HashLink target.
