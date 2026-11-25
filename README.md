# hxnme

[![Ash](https://github.com/hx-n/hxnme/actions/workflows/ash.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/ash.yml)
[![HashLink](https://github.com/hx-n/hxnme/actions/workflows/hashlink.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/hashlink.yml)
[![hxcpp](https://github.com/hx-n/hxnme/actions/workflows/hxcpp.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/hxcpp.yml)
[![CPPIA](https://github.com/hx-n/hxnme/actions/workflows/cppia.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/cppia.yml)
[![iOS](https://github.com/hx-n/hxnme/actions/workflows/ios.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/ios.yml)
[![Android](https://github.com/hx-n/hxnme/actions/workflows/android.yml/badge.svg)](https://github.com/hx-n/hxnme/actions/workflows/android.yml)

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

[Architecture](docs/architecture.md) describes the layers of the engine, what
a plugin is made of, and how the kernel composes plugins and calls their
systems.

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
