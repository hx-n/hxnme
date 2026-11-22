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
| `plugins` | Haxelibs added to the build, with the haxelibs they depend on, as `-lib` would add them. A plugin can also be selected with `-lib` in the program file. |
| `app.preset` | The Ash preset for the kind of app: `game`, `server`, `application` or another that `ash --help` lists. It sets when Ash's hybrid and JIT modes compile a function, as in `hxn run hl --vm ash`. A `--preset` in the `--ash` or `--vm` command overrides it. |

hxnme reads the file in a build hook of the hxn command.
