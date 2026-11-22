# hxnme

The kernel of hxnme. The package `hxn.me.math` contains:

- `Vec3`, `Quat` and `Mat3`: vectors, quaternions and 3×3 matrices.
- `FloatBuffer`, `IntBuffer` and `DoubleBuffer`: fixed-length arrays of 32-bit
  floats, 32-bit integers and 64-bit floats.
- `SimdBatch`: velocity and position integration for the physics, 4 bodies per
  iteration with `-D ash_simd`, and a scalar loop without it.
- `Grow`: static functions that copy an array or a buffer into one with a
  larger capacity.

## App metadata

An app declares its metadata as defines in its program file, the `.hxml`
file that `hxn run` and `hxn check` compile:

```
-lib hxnme
-main Main
-D hxnme_preset=game
```

`hxnme_preset` selects the Ash preset for the kind of app: `game`, `server`,
`application` or one of the others that `ash --help` lists. The preset sets
when Ash's hybrid and JIT modes compile a function, as in
`hxn run hl --vm ash`. hxn gives it to every Ash command that it runs for the
app. A `--preset` in the `--ash` or `--vm` command overrides the app's.

hxnme reads the defines in a build hook of the hxn command, and hxn passes
the options to Ash.
