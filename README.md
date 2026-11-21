# hxnme

hxnme is an engine for games and interactive apps, written in Haxe. It is part
of the [hxn](https://github.com/hx-n/hxn) project. hxnme is a kernel and
plugins, each published as a haxelib. Apps depend on the kernel and on the
plugins that they use.

## Packages

| Haxelib | Contents |
|---|---|
| [hxnme](packages/hxnme/README.md) | Kernel: math types and numeric buffers. |
| [hxnme-physics](packages/hxnme-physics/README.md) | Physics plugin: rigid bodies in 2D and 3D, deterministic stepping and snapshots. |

## Roadmap

1. Core: app loop, input actions, 2D renderer, assets, and `new`, `run` and
   `build` for desktop and web.
2. Physics: a GPU solve, with the CPU solve for deterministic worlds.
3. Dev loop: hot reload of code and assets, on desktop, Android and iOS.
4. Entities: ECS, scenes, prefabs, serialization and audio.
5. UI: layout, widgets, text input and accessibility.
6. 3D: frame graph, meshes, materials and post-processing.
7. Delivery: packaging, signing, and deploys to app stores and the web.

## License

Apache-2.0. See [LICENSE](LICENSE).
