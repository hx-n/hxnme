# Plugins

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
