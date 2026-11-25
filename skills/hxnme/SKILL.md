---
name: hxnme
description: Build apps and plugins on the hxnme haxelib (package `hxn.me`), the kernel of the hxn media engine, on HashLink, Ash, hxcpp, CPPIA and wasm. Use when an app selects hxnme plugins or sets its metadata in hxnme.toml. Also use when it runs or packages through the hxn command, or when writing a plugin or changing the kernel.
---

# hxnme

The hxn media engine (hxnme) kernel is lightweight on purpose. Engine
features such as rendering, audio, input, ECS, UI and physics ship as
plugins. Each plugin is a haxelib, and the kernel composes the plugins at
compile time.

## Creating an app

`hxn me new <name>` creates a small game (window, input, GPU and 2D plugins,
an atlas and a font declared in `GameAssets`) in `<name>/`. Run it with
`hxn run hl app.hxml`, or with `hxn me dev` to reload it on Ash while its
sources change. `app.frames` in `hxnme.toml` stops an app after that
many frames, for unattended checks.

## Setup

Each app is an hxn program file that selects the kernel, with `hxnme.toml`
colocated with it:

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
| `plugins` | Haxelibs that the app compiles with, together with their dependencies, as `-lib` adds them, or paths of plugin directories in the project (`"./plugins/tilemap"`). `-lib` in the program file also selects a plugin. |
| `app.preset` | The Ash preset (`game`, `server`, `application`, ...). hxn passes it to every Ash command that it runs for the app. The `--preset` flag in `--ash` or `--vm` overrides it. |
| `app.step` | Fixed steps in a second, 60 by default. |
| `app.step_snap` | Tolerance, as a part of a step, within which a frame runs a whole number of steps. So vsync timing does not alternate frames between zero and two steps. 0.1 by default, and 0 turns it off. |
| `app.rate` | Frames in a second without a window, 60 by default. |
| `display.width`, `display.height`, `display.scale` | The display without a window: 1280, 720 and 1 by default. |

Read a key at compile time with `hxn.me.Project.text`, `number`, `integer`
or `flag`, as in `Project.text("window.title", "App")`. Each call becomes a
constant. Each plugin keeps its keys in a table of its own.

```
hxn run hl app.hxml --vm ash     # Ash hybrid: starts at once, for development
hxn build hl app.hxml            # Ash AOT executable, for distribution
hxn package hl app.hxml --out dist
hxn package cpp app.hxml --target x86_64-apple-darwin --out dist-x86_64
```

hxnme reads `hxnme.toml` in a build hook of the hxn command. The hook uses
only hxn's existing hook replies (`haxe_args`, `ash_args`, `page_files`).
It also runs the build hook of each haxelib that `hxnme.toml` brings in, and
returns what that hook returns. Extend the hook through those replies, and
do not add a new protocol.

## Plugins

Each plugin is a haxelib with three parts: an `hxnme` section in
`haxelib.json`, a class marked `@:plugin("<haxelib name>")` with the
methods of `hxn.me.Plugin`, and an `extraParams.hxml` with
`--macro hxn.me.macro.Registry.add("<haxelib name>")`. The `hxnme` section
has these fields:

- `plugin`: the class.
- `requires`: plugin names.
- `platforms`: `hl`, `cpp`, `cppia`, `desktop`, `wasm`, `android`, `ios`.
- `libraries`: an array of `{triple, use}`. The first entry whose `triple`
  is part of the target triple adds the haxelibs in `use`.
  `[libraries.<plugin>]` in hxnme.toml replaces a list by fragment of a
  triple.

The class can add `implements hxn.me.Plugin` or leave it out. Either way,
the kernel checks the constructor and each method by type, and calls the
class directly. The kernel generates `hxn.me.Plugins` at compile time.
`Plugins.start()` creates and starts each plugin after the plugins it
requires, and `Plugins.names` lists them in that order. Missing
requirements, cycles, unsupported targets, a wrong `@:plugin` and a missing
or mistyped method are compile errors. Give each plugin a description with
`@:plugin("<haxelib name>", description = "...")`.

## Systems

Systems are static functions with `@:system(Phase, after = ..., before = ...,
description = "...")`. The phases run in the order `Start` (once), `Begin`
(once a frame, where plugins turn platform events into state), `Fixed`
(once for each fixed step), `Update` and `Render`. `after` and `before` take
one name or an array of names. Each name is a system (`move`,
`Movement.move`) or a class of systems (`Movement`). For a class, the
constraint applies to its systems in the same phase. Give each system a
`description` of what it does.

Each parameter of a system is a resource. `Res<T>` reads `T`, and
`ResMut<T>` writes it. Both forward the fields of `T` and convert to `T`.
`T` is a class whose constructor takes no arguments, or an abstract with a
static macro `create()`. That `create()` reads its type parameters from
the expected type. The app has one instance of `T`. The kernel derives each system's
reads and writes from these types. So if the system writes a resource,
declare it as `ResMut<T>`.

`hxn.me.Events<T>` is a resource that holds a queue. Writers take
`ResMut<Events<T>>` and call `push`. Readers take `Res<Events<T>>` and loop
over it. The schedule clears every queue after `Render`, so order the
readers after the writers in the same frame.

```haxe
@:system(Update, after = Physics, description = "Moves each body by its velocity")
static function move(time:Res<Time>, bodies:ResMut<Bodies>) {}
```

The app passes its classes of systems one time, with
`var schedule = hxn.me.App.schedule(Movement, Scoring);`. Each plugin lists
its own with `@:systems(Broadphase, Solver)` on its plugin class, whose
static functions can also be systems. The generated `hxn.me.Schedule` has
`start()`, `fixed()`, `update()` and `render()`, and each calls its systems
directly in the resolved order. Cycles, unknown names, constraints across
phases, ambiguous names and parameters that are not resources are compile
errors at the annotation.

## App loop

`hxn.me.App.run(Movement, Scoring)` in `main` starts the plugins, makes the
schedule and runs its frames. The first frame runs `Start`. Each frame runs
`Fixed` once for each completed fixed step, then `Update` and `Render`.
While the app is suspended, a frame runs no phase. Systems stop the app
with `lifecycle.quit()`. `App.schedule` returns the schedule instead, for a
loop of your own. Make `App.run` the last statement of `main`. Under
Emscripten, it returns before the frames run, and browser callbacks then
run the frames.

Every schedule has three kernel resources. Take them as `Res<T>` or
`ResMut<T>`:

- `hxn.me.Time`: `delta`, `elapsed`, `frame`, `step`, `steps`,
  `fixedElapsed`, `alpha`.
- `hxn.me.Lifecycle`: `running`, `suspended`, `visible`, `focused`,
  `quit()`.
- `hxn.me.Display`: `width`, `height`, `scale`, `refresh`, `vsync`.

The host paces the frames and calls `loop.frame(seconds)` on the
`hxn.me.AppLoop`. It is the service `hxn.me.Host`. Plugins provide it with
`@:provides(hxn.me.Host)` on a plugin class with the method
`run(loop:hxn.me.AppLoop):Void`, with or without `implements hxn.me.Host`.
Each service has one provider in an app at most. If the app has no host
plugin, it runs on `hxn.me.HeadlessHost` at `app.rate` frames a second.
`hxn.me.Plugins` has a field for each plugin instance, named after its
haxelib.

`-D hxnme_dump` writes the generated `Plugins` and `Schedule` classes to
`hxnme-generated.hx`, with the order, reads, writes and description of each
system. Read the file to see the order that the kernel chose.

## Kernel API

- `hxn.me.math` has `Vec3`, `Quat` and `Mat3`, and these storage helpers:
  - `Float32Bytes` stores float records at byte offsets. On HashLink it is
    `hl.Bytes`, which `ash.simd` reads directly.
  - `BufferArray` holds arrays of typed buffers without boxing them.
  - `Simd` integrates bodies, 4 lanes at a time with `-D ash_simd`.
  - `Grow` makes larger copies of buffers, for storage that grows.
- `hxn.me.WorkerPool` runs jobs on a fixed set of worker threads. `run`
  starts a job on each worker without allocating. Without threads, and
  under Emscripten, it runs the job for each index on the calling thread.
- `hxn.me.project.Toml` reads `hxnme.toml`. It refuses dates, arrays of
  tables and multi-line strings, with the file and line in the error.
- `hxn.me.Assets` is the resource that loads assets. Declare assets on
  `@:build(hxn.me.Assets.build()) class GameAssets { @:asset("ui/sheet.json") public static var Sheet:AssetRef<Atlas>; }`.
  The macro also runs hxn-assets' macro. `assets.load(GameAssets.Sheet)`
  returns `Future<Asset<T>>`. Loads of one asset share one value, and
  `release()` on the last handle closes it. `T` with `@:assetType(expr)` on
  its class (or the field) is an engine type. Any other `T` is data that
  hxn-assets decodes. Fields of other types are hxn-assets fields, such as
  data embedded at compile time. hxn-assets bundles only declared files.
  Make an asset type with
  `new AssetType<T>(name, (bytes, context) -> future, ?close)`.
  `context.load` holds what the value depends on.

## Rules for engine and plugin code

- Keep the code data-oriented. Store components and engine state as
  struct-of-arrays in hxn typed buffers (`hxn.Float32Buffer` and the
  others), so Rust libraries and the GPU read them without a copy.
- Put the GPU first. The GPU draws everything every frame. Use the CPU only
  where the GPU cannot do the work, and document each such case.
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
under a timeout on every runtime that the code supports:

```
hxn check hl cpp cppia toml-checks.hxml --vm ash
hxn build hl toml-checks.hxml
hxn run hl --wasm toml-checks.hxml
hxn run cpp --wasm toml-checks.hxml
cd plugins && hxn check hl cpp cppia app.hxml --vm ash
cd systems && hxn check hl cpp cppia app.hxml --vm ash
cd loop && hxn check hl cpp cppia app.hxml --vm ash
cd headless && hxn check hl cpp cppia app.hxml --vm ash
haxe plugin-errors.hxml
haxe system-errors.hxml
```

The checks in `plugins`, `systems`, `loop` and `headless` select the kernel
with `-lib hxnme`. Before the first run, run
`haxelib dev hxnme <hxnme checkout>/packages/hxnme` one time.

Report each runtime that you did not run. Follow the
[hxnme agent rules](https://github.com/hx-n/hxnme/blob/main/AGENTS.md), the
[kernel guides](https://github.com/hx-n/hxnme/tree/main/packages/hxnme/docs)
and the [hxn conventions](https://github.com/hx-n/hxn/blob/main/docs/conventions.md).
The issues are in hxn's git-bug tracker under `area:me`. Do not put AI
attribution in commits or issues.
