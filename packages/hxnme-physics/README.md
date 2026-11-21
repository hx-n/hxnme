# hxnme-physics

Rigid-body physics for hxnme, in `hxn.me.physics`.

- 2D and 3D bodies in one world. Each body's degrees of freedom follow from
  its shapes.
- Deterministic stepping, and snapshots that restore the full solver state.
- Zero-allocation steps once storage has grown to the scene's size.
- Soft-step contact solver with 4-wide SIMD contact and joint batches.
- Parallel stepping of islands, and of independent worlds.

```haxe
import hxn.me.physics.core.Handles.BodyType;
import hxn.me.physics.core.World;
import hxn.me.physics.geom.ShapeBuilder;

class Main {
	static function main() {
		// Initial capacity: 8 bodies and 8 shapes. Gravity is (0, -9.81, 0).
		var world = new World(8, 8);

		// A static floor: half-extents 3 and 0.25, depth 2 (z from -1 to 1).
		// Polygon vertices go into the world's vertex pool, `world.verts`.
		var floor = world.createBody(BodyType.Static, 0, -0.25);
		world.attachShape(floor, ShapeBuilder.makeBox(world.verts, 3, 0.25, 2, 0));

		// A disc of radius 0.25 with no depth: it moves in the XY plane at z = 0.
		var disc = world.createBody(BodyType.Dynamic, -1, 2);
		world.attachShape(disc, ShapeBuilder.makeCircle(0.25));

		// A box with depth 0.5: it moves in 3D.
		var box = world.createBody(BodyType.Dynamic, 1, 2);
		world.attachShape(box, ShapeBuilder.makeBox(world.verts, 0.25, 0.25, 0.5, 0));

		for (_ in 0...120)
			world.step(1 / 60);
		var d = world.getBodyTransform(disc).position;
		var b = world.getBodyTransform(box).position;
		Sys.println('disc ${d.x} ${d.y} ${d.z}');
		Sys.println('box ${b.x} ${b.y} ${b.z}');
	}
}
```

Output on Ash:

```
disc -1.000000000 0.247930959 0.000000000
box 0.999957323 0.247930959 0.000030563
```

## 2D and 3D bodies

A world is always 3D. A body whose shapes all have zero depth is planar: it
has 3 degrees of freedom (X and Y translation, Z rotation). A body with any
depth or a convex hull has 6. A planar shape lies in the plane of its body's
Z. It collides with planar shapes in the same plane, and with 3D shapes
whose Z extent contains that plane. 2D, 3D and mixed scenes use the same
API. A shape's depth is its full extent along Z, centered on its `localZ`.

`ShapeBuilder` makes circles, capsules, segments, boxes and convex polygons,
each with an optional depth and corner radius, and convex hulls from 3D
points.

## Determinism and snapshots

Stepping is deterministic for a given runtime, build and number of island
workers.
`WorldSnapshot` saves the complete state that a
step depends on: warm-starting impulses of contacts and joints, sleep
timers, the last axes of joint drives, and the broad-phase tree, which
fixes the order of contact pairs. A world restored from a snapshot produces bit-identical
results to the world it was saved from. The snapshot checks in `tests/`
compare the state after a restore bit for bit, with and without island
workers. A snapshot can also be restored
into another world that was built with the same calls. After the first
save, save and restore do not allocate, and they copy only the bodies,
shapes and joints in use.

## Batched worlds

`WorldBatch` steps independent worlds on a worker pool. A world gives the
same results on any worker as it gives when it is stepped alone. With
snapshots, this supports reinforcement learning and other workloads that
reset and step many copies of one environment.

## Memory

`World.step` allocates only when a scene needs more capacity than before.
Scratch buffers for contacts and events grow to the peak size and are not
shrunk. Body, shape and joint storage doubles when it is full, up to
1,048,576 of each. `World.reserve` grows it ahead of time. Once storage
fits the scene, a step does not allocate, continuous collision included.

## Solver

- Soft-step solver with 4 substeps. Contacts are soft constraints, with a
  stiffer constraint against static and kinematic bodies. Separation speed
  is capped at 3 m/s.
- A relax pass after integration removes the velocity that the solver added
  to separate overlapping shapes, so resting bodies do not drift and loaded
  contacts do not jitter.
- Warm starting for contacts and joints.
- `world.jointSweeps` sets the joint iterations per contact iteration, for
  long joint chains such as ragdolls.
- Broad phase: dynamic AABB tree. Narrow phase: GJK, EPA and manifold
  clipping. Continuous collision by time of impact.
- Union-find islands with sleeping.

## Data layout and SIMD

Body state is struct-of-arrays, with one buffer for each component. Contacts
and joints are graph-colored, so that no dynamic body appears twice in a
color. With `-D ash_simd`, the solver processes 4 contacts or 4 joints per
batch in SIMD registers, from constraint rows that it prepares once per
substep in solve order. Without it, the same rows go through a scalar path. `World.enableParallelIslands` solves independent islands on
worker threads.

## Joints

Distance, hinge, prismatic, spherical and weld joints.

- Hinge: angle limits, motor, and a drive to a target angle.
- Prismatic: limits and motor.
- Spherical: swing and twist limits, and a drive to a target orientation.
  The drive's torque limit is shared by its 3 axes.

## Water

`Water` applies buoyancy at the center of the displaced volume. Boxes,
extruded polygons and hulls are clipped exactly at the surface. Planar
shapes use their area. Rounded shapes are
clipped through a tessellation. Drag acts on the submerged part of each
shape, and pressure on inclined faces applies a lateral force. Waves are
sine waves with an amplitude and a length. The surface height is a function
of position and time only, so the simulation stays deterministic and the
renderer can sample the same surface.

## Other features

- Sensors and per-step events: overlap begin and end, contact begin and end,
  and impacts with approach speed.
- `queryAABB`, `rayCast` and `shapeCast`.
- `setBullet` for continuous collision on a chosen body.
- Kinematic targets, teleports, impulses, and body type changes.
- `FixedStep` for a fixed timestep, and `getInterpolatedTransform` for
  rendering between steps.
- Collision filtering by category, mask and group. Friction, restitution and
  density for each shape.
- Generational handles. Using a handle to a destroyed body throws.
- `World.validate`, which reports invalid state with a fault code and a
  path.

## Runtimes

hxnme-physics stores its data in `hl.NativeArray` and `hl.Bytes`, and
requires the HashLink target. Its checks run on
[Ash](https://ash.rayzor.tech/). The stock HashLink VM is not tested. hxcpp
and CPPIA are not supported.

## Checks and benchmarks

`tests/` holds the checks. `bench/` holds a benchmark that steps chains of
10 hinged links. Its arguments are the chain count and a contact mode: `on`
(adjacent links collide), `off` (no link collisions) or `gap` (narrower
links that do not touch). It prints one JSON line with the sample times, the
best time and the final energy. The energy is the same on every run of the
same build.

## Credits

hxnme-physics is derived from the physics engine of Chimpmonk.
