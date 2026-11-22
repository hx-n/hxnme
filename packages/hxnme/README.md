# hxnme

The hxn media engine (hxnme) kernel. It is intentionally lightweight: it
provides the app loop, the frame scheduler, the plugin registry, math, and
the asset and file layer built on hxn-assets and hxn-file. Everything else,
including rendering, audio, text, input, ECS, UI, physics and
platform-specific features, ships as plugins. The plugin system keeps the
architecture flexible without costing performance: plugins are composed at
compile time, with no run-time discovery or lookup, and an app compiles only
the plugins it needs.

## Project file

An app keeps its plugins and metadata in `hxnme.toml`, beside the program
file that `hxn run`, `hxn build` and `hxn package` compile. The program file
selects the kernel with `-lib hxnme`:

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
| `plugins` | Haxelibs added to the build, with the haxelibs they depend on, as `-lib` would add them. A path such as `"./plugins/tilemap"` adds an in-project plugin from that directory. A plugin can also be selected with `-lib` in the program file. |
| `app.preset` | The Ash preset for the kind of app: `game`, `server`, `application` or another that `ash --help` lists. It sets when Ash's hybrid and JIT modes compile a function, as in `hxn run hl --vm ash`. A `--preset` in the `--ash` or `--vm` command overrides it. |

hxnme reads the file in a build hook of the hxn command.

## Plugins

A plugin is a haxelib with an `hxnme` section in its `haxelib.json`, a class
that implements `hxn.me.Plugin`, and an `extraParams.hxml` that registers it:

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
class TilemapPlugin implements hxn.me.Plugin {
	public function new() {}

	public function start():Void {}
}
```

| Field | Meaning |
|---|---|
| `plugin` | The plugin class. It must carry `@:plugin` with the haxelib name. |
| `requires` | Plugins that must be in the app. They start first. |
| `platforms` | Where the plugin runs: runtimes (`hl`, `cpp`, `cppia`) and platforms (`desktop`, `wasm`, `android`, `ios`). Omitted means everywhere. |

At compile time the kernel generates `hxn.me.Plugins`. Its `start()` creates
each plugin of the app and starts it, after the plugins it requires, with a
direct call to each. `-D hxnme_dump` writes the classes that the kernel
generates to `hxnme-generated.hx`, or to the path given as its value.

`@:plugin` can also describe the plugin:
`@:plugin("hxnme-tilemap", description = "Draws tile maps")`.

These are compile errors that name the plugin: a missing required plugin, a
cycle of requirements, a plugin that does not support the target, and a
plugin class without the matching `@:plugin`.

## Systems

A system is a static function with `@:system`. It names its phase, and it
can name the systems that it runs after or before:

```haxe
import hxn.me.Res;
import hxn.me.ResMut;

class Movement {
	@:system(Update, after = Physics, description = "Moves each body by its velocity")
	static function move(time:Res<Time>, bodies:ResMut<Bodies>) {
		for (i in 0...bodies.count)
			bodies.x[i] += bodies.vx[i] * time.delta;
	}
}
```

The phases of a frame run in this order:

| Phase | Runs |
|---|---|
| `Start` | Once, after the plugins start. |
| `Fixed` | Once for each fixed time step. A frame can run it zero or more times. |
| `Update` | Once a frame. |
| `Render` | Once a frame, after `Update`. Its systems record the drawing. |

| Key | Meaning |
|---|---|
| `after`, `before` | One name or an array of names. A name is a system (`move`, `Movement.move`) or a class of systems (`Movement`, `game.Movement`). A class means each of its systems in the same phase. |
| `description` | What the system does. The kernel records it with the system. |

A system gets its resources as parameters. A resource is the one instance
of a class that the systems of an app share. The class must have a
constructor that takes no arguments. `Res<T>` reads `T`, and `ResMut<T>`
writes `T`. The kernel gets the reads and writes of each system from these
parameter types.

The app names the classes that hold its systems, and gets its schedule:

```haxe
var schedule = hxn.me.App.schedule(Movement, Scoring);
```

A plugin names its classes of systems on its plugin class, with
`@:systems(Broadphase, Solver)`. The static functions of the plugin class
can also be systems.

At compile time the kernel generates `hxn.me.Schedule`. It creates the
resources, and it has one method for each phase: `start()`, `fixed()`,
`update()` and `render()`. Each method calls each system of its phase
directly, once. The order obeys every `after` and `before`. Where no
constraint applies, the systems of the plugins come first, in plugin order.
The systems of the app follow, in the order that the app names their
classes. `-D hxnme_dump` writes this class too, with the reads, the writes
and the description of each system.

These are compile errors that point at the annotation:

- A cycle of constraints.
- A constraint that names no system, or names a system in another phase.
- A name that matches more than one class or system.
- A phase that does not exist.
- A parameter that is not a resource.
- A resource class without a constructor that takes no arguments.
