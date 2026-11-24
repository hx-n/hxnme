# hxnme

[![Ash](https://github.com/hx-n/hxnme/actions/workflows/ash.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/ash.yml)
[![hxcpp](https://github.com/hx-n/hxnme/actions/workflows/hxcpp.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/hxcpp.yml)
[![CPPIA](https://github.com/hx-n/hxnme/actions/workflows/cppia.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/cppia.yml)
[![iOS](https://github.com/hx-n/hxnme/actions/workflows/ios.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/ios.yml)

hxnme is an engine framework, written in Haxe, for games and rich interactive
apps and experiences. It is part of the [hxn](https://github.com/hx-n/hxn)
project. The engine has a small kernel and a set of plugins, and each one is
published as its own haxelib. Apps depend on the kernel and add the plugins
that they need.

## Getting started

`hxn me new <name>` creates a small 2D game in a new directory. The game
uses the window, input, GPU and 2D plugins, and loads an atlas and a font
from its assets:

```
hxn me new my-game
cd my-game
hxn run hl app.hxml
```

To learn how to build an hxnme app, read the
[kernel's guides](packages/hxnme/docs). They cover the project file,
plugins, systems, running an app and assets in depth.

## Platforms

hxnme apps run on the desktop, in a web page and on mobile devices. On each
platform, the GPU plugin uses that platform's graphics API:

| Platform | Graphics API | Runtimes |
|---|---|---|
| macOS | Metal | hxcpp, CPPIA, HashLink and Ash |
| Linux | Vulkan or OpenGL ES | hxcpp, CPPIA, HashLink and Ash |
| Windows | Direct3D 12 | hxcpp, CPPIA, HashLink and Ash |
| Web | WebGPU or WebGL2 | hxcpp or Ash, compiled to wasm |
| Android | Vulkan or OpenGL ES | hxcpp, and Ash ahead of time |
| iOS | Metal | hxcpp, and Ash ahead of time |

## Architecture

```mermaid
flowchart TB
    app["App"]

    subgraph plugins["Plugins"]
        windowing["Window"]
        render["Rendering"]
        audio["Audio"]
        text["Text"]
        input["Input"]
        ecs["ECS"]
        ui["UI"]
        physics["Physics"]
        platform["Platform-specific plugins"]
        custom["Custom plugins"]
    end

    subgraph kernel["Kernel"]
        loop["App loop"]
        scheduler["Frame scheduler"]
        registry["Plugin registry"]
        math["Math"]
        assets["Assets and files"]
    end

    subgraph libraries["hxn libraries"]
        window["hxn-window"]
        gpu["hxn-gpu, hxnsl"]
        av["hxn-av, hxn-audio"]
        textlib["hxn-text"]
        assetlib["hxn-assets, hxn-file"]
    end

    subgraph runtimes["Runtimes"]
        hxcpp["hxcpp"]
        hashlink["HashLink"]
        ash["Ash JIT and AOT"]
    end

    app --> plugins --> kernel --> libraries --> runtimes
```

An hxnme app is a Haxe program with an `hxnme.toml` file that defines a set
of plugins it depends on. Each plugin is a haxelib. The `hxnme` section of
its `haxelib.json` is the plugin's manifest. It defines the plugin class, the other
plugins it depends on, the platforms it supports and the haxelibs it needs for
each target.

Plugins and the app add code to the frame in three forms:

- Systems are static functions with `@:system`. The annotation specifies the
  phase of the frame that calls the system, and the systems that run before
  or after it.
- Resources are classes that hold shared state, such as the frame time or
  the state of the keys. Each system takes the resources it uses as
  parameters: `Res<T>` to read and `ResMut<T>` to write.
- Services are interfaces that one plugin implements for the others. For
  example, the window plugin provides `Host`, which drives the frames.

The plugin below turns an angle in each frame. Its manifest in
`haxelib.json` defines the plugin class:

```json
"hxnme": {"plugin": "spin.SpinPlugin"}
```

```haxe
package spin;

import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;

// @:systems lists the classes that hold the plugin's systems.
@:plugin("hxnme-spin")
@:systems(Spin)
class SpinPlugin {
	public function new() {}

	public function start():Void {}
}

// A resource. The kernel creates one instance and passes it to each system
// that takes it.
class Angle {
	public var radians = 0.0;

	public function new() {}
}

class Spin {
	@:system(Update)
	static function turn(time:Res<Time>, angle:ResMut<Angle>) {
		angle.radians += time.delta;
	}

	@:system(Update, after = turn)
	static function wrap(angle:ResMut<Angle>) {
		if (angle.radians > 2 * Math.PI)
			angle.radians -= 2 * Math.PI;
	}
}
```

The kernel's macros compose the plugins at compile time. They read
`hxnme.toml`, resolve the dependency graph of the plugins, and check each
plugin against the target platform. They sort the systems of each phase
topologically by their constraints. They then generate `Plugins`, which
starts each plugin in proper order of dependencies, and `Schedule`, which
calls each system with its resources. Missing dependencies and cycles are
compile errors.

At run time, the generated code calls plugins and systems directly, without
a registry or reflection. The `Start` phase runs once, after the plugins
start. Then each frame runs `Begin`, `Fixed` once for each fixed time step,
`Update` and `Render`.

Bulk data, such as the instances that the 2D renderer draws, is laid out as
struct-of-arrays in hxn typed buffers. The Rust libraries borrow these
buffers without a copy, and the renderer uploads them to the GPU as they are.
Per-instance work runs in shaders. For example, the 2D renderer evaluates
signed distance fields for rounded shapes, borders, shadows and clipping on
the GPU. Plugins access the platform only through the hxn libraries, so app
code is portable across runtimes.

## Roadmap

1. Physics: a GPU solver, and the CPU solver for deterministic worlds.
2. Dev loop: hot reload of code and assets, on desktop, Android and iOS.
3. Entities: ECS, scenes, prefabs, serialization and audio.
4. UI: layout, widgets, text input and accessibility.
5. 3D: frame graph, meshes, materials and post-processing.
6. Delivery: packaging, signing, and deployment to app stores and the web.

## Agent skills

Each package has an agent skill for coding agents in
[`skills/`](skills/). The haxelib of the package includes its skill.

## License

hxnme uses the Apache-2.0 license. See [LICENSE](LICENSE).
