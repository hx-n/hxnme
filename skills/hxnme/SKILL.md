---
name: hxnme
description: Build apps and plugins on the hxnme haxelib (package `hxn.me`), the kernel of the hxn media engine, on HashLink, Ash, hxcpp, CPPIA and wasm. Use when an app selects hxnme plugins or sets its metadata in hxnme.toml. Also use when it runs or packages through the hxn command, or when writing a plugin or changing the kernel.
---

# hxnme

The hxn media engine (hxnme) kernel is intentionally lightweight. Engine
features such as rendering, audio, input, ECS, UI and physics ship as
plugins, each a haxelib, composed at compile time.

## Setup

An app is an hxn program file that selects the kernel, with `hxnme.toml`
beside it:

```
-lib hxnme
-main Main
```

```toml
plugins = ["hxnme-physics"]

[app]
preset = "game"
```

| Key | Effect |
|---|---|
| `plugins` | Haxelibs added to the build with their dependencies, as `-lib` adds them. `-lib` in the program file also selects a plugin. |
| `app.preset` | The Ash preset (`game`, `server`, `application`, ...), passed to every Ash command hxn runs for the app. A `--preset` in `--ash` or `--vm` overrides it. |

```
hxn run hl app.hxml --vm ash     # Ash hybrid: starts at once, for development
hxn build hl app.hxml            # Ash AOT executable, for distribution
hxn package hl app.hxml --out dist
hxn package cpp app.hxml --target x86_64-apple-darwin --out dist-x86_64
```

hxnme reads `hxnme.toml` in a build hook of the hxn command. The hook uses
only hxn's existing hook replies (`haxe_args`, `ash_args`). Extend it through
those, not with new protocol.

## Kernel API

- `hxn.me.math`: `Vec3`, `Quat` and `Mat3`, and storage helpers:
  - `Float32Bytes`: float records addressed by byte offset. On HashLink it
    is `hl.Bytes`, which `ash.simd` reads directly.
  - `BufferArray`: arrays of typed buffers without boxing.
  - `Simd`: body integration, 4 lanes at a time with `-D ash_simd`.
  - `Grow`: larger copies of buffers, for storage that grows.
- `hxn.me.WorkerPool`: a fixed set of worker threads. `run` starts a job on
  each worker without allocating. Without threads, and under Emscripten, it
  runs the job for each index on the calling thread.
- `hxn.me.project.Toml`: the reader for `hxnme.toml`. It refuses dates,
  arrays of tables and multi-line strings, naming the file and line.

## Rules for engine and plugin code

- Data-oriented: store components and engine state as struct-of-arrays in
  hxn typed buffers (`hxn.Float32Buffer` and the others), so Rust libraries
  and the GPU read them without a copy.
- GPU first: the GPU draws everything every frame. Use the CPU only where
  the GPU cannot do the work, and document each such case.
- Compose plugins at compile time. Never look up plugins, systems or
  components by name at run time.
- Do not allocate in a frame. Store callbacks in fields, because a closure
  made per call allocates.
- Never write a compound assignment to a `Single` with a `Float` operand,
  such as `s /= f`. HashLink computes it in single precision, and hxcpp in
  double. Cast first: `s = (s : Float) / f`.
- Record each third-party dependency in the package's
  `third-party/NOTICES.md`, with its license texts unchanged, in the commit
  that adds it.
- Keep each package's skill in `skills/<package>/SKILL.md` current with its
  API, with absolute HTTPS links.

## Checks

Each package's checks are program files in its `tests` directory. Run them
under a timeout on every runtime the code supports:

```
hxn check hl cpp cppia toml-checks.hxml --vm ash
hxn build hl toml-checks.hxml
hxn run hl --wasm toml-checks.hxml
hxn run cpp --wasm toml-checks.hxml
```

Report each runtime that was not run. Follow the
[hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md), the
[kernel README](https://github.com/hx-n/hxnme/blob/main/packages/hxnme/README.md)
and the [hxn conventions](https://github.com/hx-n/hxn/blob/main/docs/conventions.md).
Issues are in hxn's git-bug tracker under `area:me`. No AI attribution in
commits or issues.
