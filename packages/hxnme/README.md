# hxnme

The hxn media engine (hxnme) kernel provides the app loop, the frame
scheduler, the plugin registry and math. It also provides the asset and
file layer, which uses hxn-assets and hxn-file. The kernel is lightweight
on purpose. Everything else ships as plugins, including the window,
rendering, audio, text, input, ECS, UI, physics and the features of each
platform. The kernel composes the plugins at compile time, with no
discovery or lookup at run time. Each app compiles only the plugins that it
needs. So the plugin system keeps the architecture flexible and costs no
performance.

## Creating an app

`hxn me new <name>` creates a small game in a new directory called `<name>`.
It lists the window, input, GPU and 2D plugins in its `hxnme.toml`, and
declares an atlas and a font in `GameAssets`. The player moves with WASD,
the arrow keys or the left stick of a gamepad and collects gems, and a
screen camera draws the score:

```
hxn me new my-game
cd my-game
hxn run hl app.hxml
```

To run the game in a web page, compile it to wasm with Ash or with hxcpp:

```
hxn run hl app.hxml --wasm --threads --browser
hxn run cpp app.hxml --wasm --browser
```

The template keeps the license of its font in `licenses/`. Keep it with
the game, or replace the font. The check in `tests/new` creates a game with
the command and checks the files that it writes.

## Project file

Each app keeps its plugins and its metadata in `hxnme.toml`. The file is
colocated with the program file of the app, which is the `.hxml` file that
`hxn run`, `hxn build` and `hxn package` compile. The program file selects
the kernel with `-lib hxnme`:

```
-lib hxnme
-main Main
```

```toml
plugins = ["hxnme-physics"]

[app]
preset = "game"
```

The kernel reads these keys:

| Key | Effect |
|---|---|
| `plugins` | The plugins of the app. Each name adds that haxelib and the haxelibs it depends on, the same way as `-lib`. Each path, such as `"./plugins/tilemap"`, adds the plugin in that directory, relative to `hxnme.toml`. The program file can also select a plugin with `-lib`. |
| `app.preset` | The Ash preset for the kind of app: `game`, `server`, `application`, or another preset that `ash --help` lists. The preset sets when Ash compiles a function to machine code in its hybrid and JIT modes, for example in `hxn run hl --vm ash`. The `--preset` flag in the `--ash` or `--vm` option of the hxn command overrides it. |
| `app.step` | The number of fixed steps in a second. The default is 60. |
| `app.step_snap` | The tolerance for a whole number of fixed steps in a frame, as a part of one step. The default is 0.1, and 0 turns the correction off. |
| `app.rate` | The number of frames in a second on `HeadlessHost`, the host of an app without a window. The default is 60. |
| `app.id` | The name of the app's storage, for its bundled files and saves. The default is `hxnme`. |
| `app.frames` | The number of frames after which the app stops, for checks that run an app unattended. The default is 0, which runs the app until it quits. |
| `display.width`, `display.height`, `display.scale` | The display on `HeadlessHost`. The defaults are 1280, 720 and 1. |
| `display.refresh` | If the host does not set the refresh rate of the display, this key sets it, in frames a second. The default is 60. |
| `libraries.<plugin>` | Replaces the haxelibs that the plugin's manifest lists for some targets. Each key is part of a target triple, such as `linux`, and its value is the list for every target whose triple contains it. The longest key that matches applies. Paths are relative to `hxnme.toml`. |

Each plugin keeps its keys in its own table, such as `[window]`. Code reads
a key at compile time with `hxn.me.Project.text`, `number`, `integer` or
`flag`, and each call becomes a constant. For example,
`Project.text("window.title", "App")` becomes the title from the file. If
the file does not set a title, the call becomes `"App"`.

## Plugins

Each plugin is a haxelib with three parts:

- The `hxnme` section of its `haxelib.json`, which specifies the plugin class.
- The plugin class, which has `@:plugin` with the haxelib name, and the
  methods of `hxn.me.Plugin`.
- The `extraParams.hxml` file, which adds the plugin to the registry.

```json
{
  "name": "hxnme-tilemap",
  "classPath": "src",
  "hxnme": {
    "plugin": "hxn.me.tilemap.TilemapPlugin",
    "requires": ["hxnme-render"],
    "platforms": ["desktop", "wasm"]
  }
}
```

```
--macro hxn.me.macro.Registry.add("hxnme-tilemap")
```

```haxe
@:plugin("hxnme-tilemap")
class TilemapPlugin {
	public function new() {}

	public function start():Void {}
}
```

The metadata declares the plugin, so the class does not need
`implements hxn.me.Plugin`. The kernel checks that the class has a public
constructor that takes no arguments, and each method of `hxn.me.Plugin`
with the same type. Then the generated code calls the class directly. The
class can also implement the interface, for example to let an IDE complete
the methods, and the kernel checks it the same way:

```haxe
@:plugin("hxnme-tilemap")
class TilemapPlugin implements hxn.me.Plugin { ... }
```

The kernel reads the manifest before it compiles any code, so that it can
check the requirements and the platforms first. `@:plugin` ties the class
back to its haxelib. The line in `extraParams.hxml` adds the plugin to the
registry, whether the app lists it in `hxnme.toml` or selects it with
`-lib`.

| Field | Meaning |
|---|---|
| `plugin` | The plugin class. |
| `requires` | The plugins that must be in the app. They start before this plugin. `requires` does not add a plugin to the app: list it in `plugins`, or in the `dependencies` of the haxelib. |
| `platforms` | The runtimes (`hl`, `cpp`, `cppia`) and the platforms (`desktop`, `wasm`, `android`, `ios`) that the plugin supports. If the list has no runtime, the plugin supports every runtime. If it has no platform, the plugin supports every platform. |
| `libraries` | The haxelibs that the plugin brings for each target, as an array of `{triple, use}`. The first entry whose `triple` is part of the target triple applies. The kernel adds each haxelib in its `use` the same way as `-lib`. Paths are relative to the plugin's directory. |

hxn runs the build hooks of the haxelibs that the program file selects
with `-lib`. For each haxelib that `hxnme.toml` brings in, the kernel's
hook runs the build hook of that haxelib for the same phase. It adds what
that hook returns to its own reply. So if the app lists the plugins of
hxn-window and of the GPU drivers in `hxnme.toml`, their files reach the
web page.

`libraries` lets a plugin bring the native libraries that suit each
target. For a native build, the target triple is the host's, such as
`aarch64-apple-darwin`. For a cross or wasm build, hxn sets it, such as
`wasm32-unknown-emscripten`. Order the entries from the most specific
fragment to the least, for example `android` before `linux`:

```json
"hxnme": {
  "plugin": "hxn.me.gpu.GpuPlugin",
  "libraries": [
    {"triple": "wasm32", "use": ["hxn-gpu-webgpu", "hxn-gpu-webgl2"]},
    {"triple": "apple", "use": ["hxn-gpu-metal"]},
    {"triple": "windows", "use": ["hxn-gpu-d3d12"]},
    {"triple": "android", "use": ["hxn-gpu-vulkan", "hxn-gpu-gles"]},
    {"triple": "linux", "use": ["hxn-gpu-vulkan", "hxn-gpu-gles"]}
  ]
}
```

If a plugin's list does not fit a target, the app replaces it for that
target in `hxnme.toml`:

```toml
[libraries.hxnme-gpu]
windows = ["hxn-gpu-d3d12", "hxn-gpu-gles"]
```

`hxn.me.Plugin` has one method, `start()`. At compile time, the kernel
generates the class `hxn.me.Plugins`. Its `start()` creates each plugin of
the app and calls its `start()`, with a direct call. Each plugin starts
after the plugins that it requires. `App.run` calls `Plugins.start()`.
`Plugins` also has a static field for each plugin. The field has the
haxelib name, with an underscore for each character that Haxe does not
permit in a name, for example `Plugins.hxnme_window`.

`@:plugin` can also describe the plugin:
`@:plugin("hxnme-tilemap", description = "Draws tile maps")`. The kernel
records the description. If the app compiles with `-D hxnme_dump`, the
compiler writes the generated classes to `hxnme-generated.hx` in its
working directory, with each description. If the define has a value, the
compiler writes them to that path.

Each of these is a compile error that reports the plugin:

- The app lacks a required plugin.
- Plugins require each other in a cycle.
- The app compiles for a runtime or a platform that a plugin does not
  support.
- The plugin class lacks the matching `@:plugin`.
- The plugin class lacks a method of `hxn.me.Plugin`, or of a
  service it provides, or the method has another type.

## Systems

Systems are static functions with `@:system`. The annotation specifies
the phase of the system, and it can specify the systems that run before or
after it. In this example, `Physics` is a class of systems, and `Bodies` is a
resource class of the app:

```haxe
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

class Movement {
	@:system(Update, after = Physics, description = "Moves each body by its velocity")
	static function move(time:Res<Time>, bodies:ResMut<Bodies>) {
		for (i in 0...bodies.count)
			bodies.x[i] += bodies.vx[i] * time.delta;
	}
}
```

Each frame runs its phases in this order:

| Phase | Runs |
|---|---|
| `Start` | One time, after the plugins start. |
| `Begin` | One time in each frame, before `Fixed`. Plugins turn the events of the platform into state here, such as the state of the keys. |
| `Fixed` | One time for each fixed step. Each fixed step is a constant interval of time, `app.step` times a second. One frame can run this phase zero or more times. |
| `Update` | One time in each frame. |
| `Render` | One time in each frame, after `Update`. Rendering plugins draw the frame in this phase. |

| Key | Meaning |
|---|---|
| `after`, `before` | One name, or an array of names. Each name is a system (`move`, `Movement.move`) or a class of systems (`Movement`, `game.Movement`). For a class, the constraint applies to each of its systems in the same phase. |
| `description` | What the system does. The kernel records it with the system. |

Systems get their resources as parameters. Each resource is the one
instance of a type that all systems of an app share. The type is a class
with a constructor that takes no arguments, or an abstract with a static
`create()`. The schedule calls `create()` with the resource type as the
expected type, so the abstract can read its type parameters at compile time.
`Res<T>` reads `T`. `ResMut<T>` reads and writes `T`. Both forward the
fields of `T`, and convert to `T`. The kernel records the reads and the
writes of each system from these parameter types, and the dump shows them.

`hxn.me.Events<T>` is a resource that holds a queue of events of type `T`.
Systems with `ResMut<Events<T>>` push events, and systems with
`Res<Events<T>>` read them, for example with a `for` loop. The schedule
clears each queue at the end of the frame, after `Render`. So an event
stays readable until the end of the frame in which a system pushes it.
Order the readers after the writers with `after` or `before`.

The app passes the classes that hold its systems to `App.run`. Each plugin
lists its classes of systems on its plugin class, with
`@:systems(Broadphase, Solver)`. The static functions of the plugin class
can also be systems.

At compile time, the kernel generates the class `hxn.me.Schedule`. Its
constructor creates the resources, and its fields `time`, `lifecycle` and
`display` hold the kernel resources. It has one method for each phase:
`start()`, `fixed()`, `update()` and `render()`. Each method calls every
system of its phase one time, with a direct call. The order obeys every
`after` and `before`. Where no constraint applies, the systems of the
plugins come first, in the order that the plugins start. The systems of the
app come next, in the order that the app passes their classes. The dump also
shows this class, with the reads, the writes and the description of each
system.

Each of these is a compile error that points at the annotation:

- The constraints make a cycle.
- The constraint refers to no system, or to a system in another phase.
- The name matches more than one class or system.
- The phase does not exist.
- The parameter is not a resource.
- The resource type is not a class with a constructor that takes no
  arguments, and not an abstract with a static `create()`.

## Running an app

`hxn.me.App.run` starts the plugins, makes the schedule and gives it to the
host. The host paces the frames. The frames stop after a system calls
`quit` on `Lifecycle`, or after the platform closes the app:

```haxe
class Main {
	static function main()
		hxn.me.App.run(Movement, Scoring);
}
```

The host calls `frame(seconds)` on an `hxn.me.AppLoop` for each frame, with
the seconds since the previous frame. The first frame runs `Start`. Then
each frame does these steps:

1. It runs `Begin`.
2. It advances the clock.
3. It runs `Fixed` one time for each fixed step that the frame completes.
4. It runs `Update` and `Render`.
5. It clears the event queues.

Vsync paces frames at the refresh rate of the display, and their timing
varies a little from frame to frame. If the refresh rate is close to the
step rate, frames can alternate between zero and two fixed steps. The loop
prevents that. If the steps that a frame owes are within `app.step_snap` of
a whole number, the loop rounds them to that number. It carries the
difference to the next frame.

While `Lifecycle.suspended` is true, a frame runs no phase, and the clock
does not advance. At the start of each frame, the loop calls
`hxn.Loop.sync`, which delivers the results of native libraries. On
HashLink, in `hxn run` and `hxn check`, each frame also calls
`hl.Api.checkReload()` for hot reload.

Make `App.run` the last statement of `main`. Under Emscripten, the host
returns from `App.run` before the frames run, and the browser runs the
frames from callbacks. Code after `App.run` then runs before the frames.

To run the phases from its own loop, the app calls `App.schedule` instead
of `App.run`, and gives the schedule to an `AppLoop`:

```haxe
hxn.me.Plugins.start();
var schedule = hxn.me.App.schedule(Movement, Scoring);
var loop = new hxn.me.AppLoop(schedule, schedule.time, schedule.lifecycle, schedule.display);
while (loop.frame(1 / 60)) {}
```

The schedule has three kernel resources. Systems take them in the same way
as other resources:

| Resource | Fields |
|---|---|
| `hxn.me.Time` | `delta`, the seconds of the last frame. `elapsed`, the seconds of all frames. `frame`, the number of frames. `step`, the seconds of a fixed step. `steps`, the fixed steps of this frame. `fixedElapsed`, the seconds of all fixed steps. `alpha`, the fraction of a fixed step, from 0 to 1, that the clock counted and did not run yet. |
| `hxn.me.Lifecycle` | `running`, `suspended`, `visible` and `focused`. `quit()` stops the app after the current frame. |
| `hxn.me.Display` | `width` and `height`, in physical pixels. `scale`, the physical pixels for each logical pixel. `refresh`, the frames that the display shows in a second. `vsync`, whether presenting a frame waits for the refresh. |

The host reads the events of the platform, and it sets `Lifecycle` and
`Display`. `hxn.me.Host` is a service. Each service is an interface with
`@:service`. Plugins provide a service with `@:provides` on the plugin
class, and the class has the methods of the interface. As with
`hxn.me.Plugin`, `implements` is optional, and the kernel checks the
methods either way. `App.run` calls the host's `run` with the loop:

```haxe
@:plugin("hxnme-window")
@:provides(hxn.me.Host)
class WindowPlugin {
	public function new() {}

	public function start():Void {}

	public function run(loop:hxn.me.AppLoop):Void {
		// Wait for the next frame, then call loop.frame(seconds).
	}
}
```

Each service has one provider in an app at most. Two providers of one
service are a compile error. If no plugin provides `Host`, the app runs on
`hxn.me.HeadlessHost`. That host runs `app.rate` frames a second without a
window, with the display that the `display` keys set.

## Assets

The kernel resource `hxn.me.Assets` loads the app's assets with
[hxn-assets](https://github.com/hx-n/hxn-assets). The app declares its assets
on a class built with `@:build(hxn.me.Assets.build())`, as hxn-assets fields:

```haxe
typedef LevelData = {name:String, lives:Int};

@:build(hxn.me.Assets.build())
class GameAssets {
	@:asset("ui/sheet.png") public static var SheetImage:AssetRef<Texture>;
	@:asset("ui/sheet.json") public static var Sheet:AssetRef<Atlas>;
	@:asset("levels/start.json") public static var Start:LevelData;
}
```

The macro runs hxn-assets' macro on the class, which checks each path at
compile time, makes the catalog and bundles the files. Each field of type
`AssetRef<T>` becomes a reference that `assets.load` takes:

```haxe
static var sheet:Null<Asset<Atlas>>;

@:system(Start)
static function setup(assets:ResMut<Assets>) {
	assets.load(GameAssets.Sheet).then(a -> sheet = a);
}
```

The future gives an `Asset` handle, whose `value` is the decoded value. Loads
of one asset share one value. When the app no longer needs the handle, call
`release()`. After the app releases the last handle to it, the kernel
closes the value and unloads its bytes.

The type `T` selects the decoder:

- Each engine type specifies its asset type with `@:assetType(expr)` on its
  class, such as `Texture` and `Atlas` of hxnme-2d. `@:assetType` on the
  field overrides it. Plugins can also give a field a more exact type, such
  as an atlas with a property for each region. The plugin makes that type
  from the file at compile time. It registers a function with
  `hxn.me.macro.AssetFields.refine` from an init macro.
- Any other type is data, which hxn-assets decodes as it decodes a dynamic
  field: `String` from text, `haxe.io.Bytes` as is, and JSON checked against
  the declared type. `@:assetFormat` and `@:assetDecode` apply as in
  hxn-assets.

Fields of other types keep their hxn-assets meaning. hxn-assets decodes
`Start` above at compile time and embeds it, so it needs no load.
hxn-assets bundles only the files that the app's declaration classes list,
so the app declares an atlas's image too.

Each `AssetType` has a name, a `decode` function and an optional `close`
function. `decode` takes the bytes and an `AssetContext`. Through the
context, it loads other files that the value holds, such as the image that an
atlas lists. The context releases them after the value closes:

```haxe
final pair = new AssetType<String>("pair", (bytes, context) ->
	context.load(context.resolve("other.txt"), note).map(other -> bytes.toString() + other));
```

The check in `tests/assets` declares text, JSON and a type with a dependency,
and tests what handles share, close and release.
