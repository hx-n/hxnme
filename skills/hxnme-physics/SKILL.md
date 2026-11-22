---
name: hxnme-physics
description: Simulate rigid bodies in Haxe with the hxnme-physics haxelib (package `hxn.me.physics`), the physics plugin of the hxn media engine, on HashLink, Ash, hxcpp, CPPIA and wasm. Use when a program needs 2D or 3D bodies in one world, shapes, joints, sensors and contact events, ray and shape casts, buoyancy, deterministic stepping with snapshots, batched worlds, or when changing the plugin itself.
---

# hxnme-physics

## Setup

List the plugin in the app's `hxnme.toml`, or select it with `-lib` in the
program file:

```toml
plugins = ["hxnme-physics"]
```

```
-lib hxnme
-main Main
```

Run with `hxn run hl app.hxml --vm ash` while developing. Build for
distribution with `hxn build hl app.hxml` (Ash AOT) or `hxn build cpp app.hxml`.
Add `-D ash_simd` to the program file for the 4-wide SIMD solver on Ash. The
scalar solver runs everywhere else, with the same API.

## Use

```haxe
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.core.World;
import hxn.me.physics.geom.ShapeBuilder;

var world = new World(8, 8); // capacity for 8 bodies and 8 shapes
var floor = world.createBody(BodyType.Static, 0, -0.25);
world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 3, 0.25, 2, 0));
var disc = world.createBody(BodyType.Dynamic, -1, 2);
world.attachShape(disc, ShapeBuilder.makeCircle(0.25));
world.step(1 / 60);
var p = world.getBodyTransform(disc).position;
```

- Worlds are 3D, and each body's degrees of freedom follow from its shapes.
  Planar bodies, whose shapes all have zero depth, move in X and Y and rotate
  about Z. Depth or a convex hull gives 6 degrees of freedom. 2D, 3D and
  mixed scenes use the same calls.
- `ShapeBuilder` makes circles, capsules, segments, boxes and convex polygons
  with optional depth and corner radius, and hulls from 3D points. Polygon
  vertices live in `world.verts`.
- Joints: `createDistanceJoint`, `createHingeJoint` (limits, motor,
  `setHingeDrive`), `createPrismaticJoint`, `createSphericalJoint` (swing and
  twist limits, `setSphericalDrive`) and `createWeldJoint`.
- Queries: `queryAABB`, `rayCast`, `shapeCast`. Sensors and per-step contact,
  overlap and impact events come from the world's events.
- `FixedStep` runs a fixed timestep, and `getInterpolatedTransform` gives
  the transform between steps for rendering. `World.reserve` grows storage ahead of time.
- `WorldSnapshot` saves and restores the full solver state, bit for bit.
  `WorldBatch` steps independent worlds on a worker pool with the same
  results as stepping each alone. `World.enableParallelIslands` solves
  islands on worker threads.
- Handles are generational: a handle to a destroyed body throws.
  `World.validate` reports invalid state with a fault code and a path.

The [README](https://github.com/hx-n/hxnme/blob/main/packages/hxnme-physics/README.md)
describes the solver, memory, water and determinism in full.

## Rules

- Once storage fits the scene, `World.step` does not allocate. Keep it that
  way. Store jobs in fields, because a closure made per call allocates.
- Body, shape and joint state is struct-of-arrays in hxn typed buffers
  (`hxn.Float32Buffer`, `hxn.Int32Buffer`). Do not add per-body objects.
- Stepping is deterministic for a given runtime, build and worker count.
  Never write a compound assignment to a `Single` with a `Float` operand,
  such as `s /= f`. HashLink computes it in single precision, and hxcpp in
  double. Cast first: `s = (s : Float) / f`.
- hxcpp builds compile with `-ffp-contract=off`, so hxcpp and HashLink round
  each operation the same way.

## Checks

Run the checks in `packages/hxnme-physics/tests` with the hxn command, under
a timeout:

```
hxn run hl checks-simd.hxml --vm "ash --mode jit"
hxn check hl cpp checks.hxml --vm "ash --no-fma"
hxn run cppia checks.hxml
hxn run hl --wasm --threads checks.hxml
hxn build hl checks-simd.hxml
```

Each program has a `<name>.hxml` for every runtime and a `<name>-simd.hxml`
for Ash. `hxn check` with `ash --no-fma` compares Ash and hxcpp output
exactly. CPPIA keeps `Single` in double precision, and wasm's math library
differs from the native one: compare those with their own earlier output.
Set `ASH_GC_TLAB=0` on Ash, or the allocation checks count only whole 32 KiB
regions. Benchmarks in `bench/` run on Ash with `--preset game`, on the Mac
and the NUC. Results go in the issue, not in code.

Follow the [hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md)
and the [hxn conventions](https://github.com/hx-n/hxn/blob/main/docs/conventions.md).
Issues are in hxn's git-bug tracker under `area:me`. Keep the
[third-party notices](https://github.com/hx-n/hxnme/blob/main/packages/hxnme-physics/third-party/NOTICES.md)
with redistributed apps.
