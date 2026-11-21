# hxnme-physics

Rigid-body physics for hxnme, in `hxn.me.physics`. One API covers 2D and 3D.
A world is always 3D. If every shape of a body has zero depth, the body
moves in its plane only.

The code comes from Chimpmonk, with its checks in `tests/` and its benchmark
in `bench/`.

## Runtimes

The physics stores its arrays in `hl.NativeArray`, and in the `FloatBuffer`
of Chimpmonk over `hl.Bytes`. These are HashLink types, so the physics runs
only on HashLink and Ash at present, natively and on wasm.

It does not use the hxn typed buffers yet, because they are slower than
`hl.NativeArray` on Ash at present. This is an exception for the physics
only. Other hxnme code stores its data in hxn typed buffers.
