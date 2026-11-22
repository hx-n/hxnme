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
direct call to each. `-D hxnme_dump` writes the generated class to
`hxnme-plugins.hx`, or to the path given as its value.

A missing required plugin, a cycle of requirements, a plugin that does not
support the build's target, and a plugin class without the matching
`@:plugin` are compile errors that name the plugin.
