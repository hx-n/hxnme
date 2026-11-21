# hxnme

hxnme is the hxn media engine. It is written in Haxe, and it runs on the
runtimes that hxn supports: HashLink, Ash, hxcpp and CPPIA, natively and on
wasm. It uses the hxn libraries for windows, the GPU, audio, text, files and
assets.

The engine is a small kernel and a set of plugins. Each plugin is a haxelib.
An application lists the plugins that it uses, and only those are compiled.

## Packages

| Package | Contents |
|---|---|
| [hxnme](packages/hxnme/README.md) | The kernel. |
| [hxnme-physics](packages/hxnme-physics/README.md) | The physics plugin. |

## License

Apache-2.0. See [LICENSE](LICENSE).
