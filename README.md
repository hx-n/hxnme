<h1 align="center"><img src="assets/hxnME-gradient.svg" alt="hxnme" width="440"></h1>

<p align="center">
  <a href="https://github.com/hx-n/hxnme/actions/workflows/ash.yml"><img src="https://github.com/hx-n/hxnme/actions/workflows/ash.yml/badge.svg" alt="Ash"></a>
  <a href="https://github.com/hx-n/hxnme/actions/workflows/hashlink.yml"><img src="https://github.com/hx-n/hxnme/actions/workflows/hashlink.yml/badge.svg" alt="HashLink"></a>
  <a href="https://github.com/hx-n/hxnme/actions/workflows/hxcpp.yml"><img src="https://github.com/hx-n/hxnme/actions/workflows/hxcpp.yml/badge.svg" alt="hxcpp"></a>
  <a href="https://github.com/hx-n/hxnme/actions/workflows/cppia.yml"><img src="https://github.com/hx-n/hxnme/actions/workflows/cppia.yml/badge.svg" alt="CPPIA"></a>
  <a href="https://github.com/hx-n/hxnme/actions/workflows/web.yml"><img src="https://github.com/hx-n/hxnme/actions/workflows/web.yml/badge.svg" alt="Web"></a>
  <a href="https://github.com/hx-n/hxnme/actions/workflows/ios.yml"><img src="https://github.com/hx-n/hxnme/actions/workflows/ios.yml/badge.svg" alt="iOS"></a>
  <a href="https://github.com/hx-n/hxnme/actions/workflows/android.yml"><img src="https://github.com/hx-n/hxnme/actions/workflows/android.yml/badge.svg" alt="Android"></a>
</p>

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

## Guides

The guides describe how to build an hxnme app in depth:

- [Creating an app](packages/hxnme/docs/new.md): the game that `hxn me new`
  creates, and how to run it on each runtime.
- [Hot reload](packages/hxnme/docs/dev.md): `hxn me dev`, which hot reloads
  the code and assets of a running app.
- [Project file](packages/hxnme/docs/project-file.md): `hxnme.toml`
  project metadata file guide.
- [Plugins](packages/hxnme/docs/plugins.md): the manifest, the plugin class
  and the native libraries of each target.
- [Systems](packages/hxnme/docs/systems.md): `@:system`, the phases of a
  frame, and resources.
- [Running an app](packages/hxnme/docs/running.md): the app loop, fixed
  steps, the lifecycle, and services such as the host that drives the frames.
- [Assets](packages/hxnme/docs/assets.md): asset classes, typed references,
  loading and releasing.

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
