# hxnme-physics

The rigid-body physics plugin of hxnme, in `hxn.me.physics`. One API covers
2D and 3D games.

## Features

- A world is always 3D. If every shape of a body has zero depth, the body
  moves only in its plane: it moves along X and Y, and turns about Z. Other
  bodies move freely in 3D. A 2D game and a 3D game use the same classes.
- Shapes are circles, capsules, segments, boxes and polygons, each with an
  optional depth, and convex hulls in 3D. `ShapeBuilder` makes them.
- Bodies are static, kinematic or dynamic. Their state is stored as
  struct-of-arrays in the `World`, one array for each property, and handles
  are checked against reuse.
- The solver is a soft-step solver with substeps. Contacts are found with a
  dynamic AABB tree, then with GJK, EPA and face clipping. Fast bodies use
  continuous collision.
- Joints are distance, hinge, prismatic, spherical and weld joints. Hinge,
  prismatic and spherical joints have limits. Hinge and spherical joints
  also have drives.
- Bodies at rest form islands that sleep. Islands can be solved on worker
  threads (`World.enableParallelIslands`), and `WorldBatch` steps many worlds
  on a pool of workers.
- Queries: AABB queries and ray casts.
- `Water` adds buoyancy, drag, currents and waves.
- `WorldSnapshot` saves and restores a world. A restored world steps the same
  way, bit for bit.
- `FixedStep` runs physics at a fixed rate under frames of any length.
- After the first steps, a step allocates nothing.

## Runtimes

The physics stores its arrays in `hl.NativeArray`, and in its own
`FloatBuffer` over `hl.Bytes`. These are HashLink types, so the physics runs
only on HashLink and Ash at present, natively and on wasm.

It does not use the hxn typed buffers yet, because they are slower than
`hl.NativeArray` on Ash at present. This is an exception for the physics
only. Other hxnme code stores its data in hxn typed buffers.

## Checks and benchmarks

`tests/` holds the checks, and `bench/` the hinged chain benchmark. The
benchmark takes the number of chains and the contact mode (`on`, `off` or
`gap`), and prints one JSON line with the time of each sample, the best time
and the final energy.

## Credits

The engine started as the physics of Chimpmonk.
