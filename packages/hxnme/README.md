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
that they need. The [hxnme repository](https://github.com/hx-n/hxnme)
lists the platforms, and its
[architecture guide](https://github.com/hx-n/hxnme/blob/main/docs/architecture.md)
describes the design.

## Kernel

This haxelib is the kernel. It runs the app loop and calls the app's
systems, which are functions that are called per frame, in a fixed order.
It keeps the registry of the plugins that the app depends on. It also
provides math types, and loads assets through the hxn-assets and hxn-file
haxelibs. The window, input, rendering, physics and the features of each
platform ship as plugins. An app lists its plugins in its project file,
`hxnme.toml`. The kernel composes them at compile time, so each app
compiles only the plugins that it lists.

## Getting started

Install the `hxn` command as the
[hxn README](https://github.com/hx-n/hxn#quick-setup) describes, and the
kernel with `haxelib install hxnme`. Then `hxn me new <name>` creates a
small 2D game in a new directory, in which the player collects gems. To
create the game and run it in a window:

```
hxn me new my-game
cd my-game
hxn run hl app.hxml
```

## Guides

- [Creating an app](https://github.com/hx-n/hxnme/blob/main/packages/hxnme/docs/new.md):
  the game that `hxn me new` creates, and how to run it in a web page.
- [Project file](https://github.com/hx-n/hxnme/blob/main/packages/hxnme/docs/project-file.md):
  the keys of `hxnme.toml`.
- [Plugins](https://github.com/hx-n/hxnme/blob/main/packages/hxnme/docs/plugins.md):
  the manifest, the plugin class and the native libraries of each target.
- [Systems](https://github.com/hx-n/hxnme/blob/main/packages/hxnme/docs/systems.md):
  `@:system`, the phases of a frame, and resources.
- [Running an app](https://github.com/hx-n/hxnme/blob/main/packages/hxnme/docs/running.md):
  the app loop, fixed steps, the lifecycle, and services such as the host
  that drives the frames.
- [Assets](https://github.com/hx-n/hxnme/blob/main/packages/hxnme/docs/assets.md):
  asset classes, typed references, loading and releasing.

## License

hxnme uses the Apache-2.0 license. See [LICENSE](https://github.com/hx-n/hxnme/blob/main/LICENSE).
