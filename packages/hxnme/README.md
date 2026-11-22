# hxnme

The hxn media engine (hxnme) kernel. It is intentionally lightweight: it
provides the app loop, the frame scheduler, the plugin registry, math, and
the asset and file layer built on hxn-assets and hxn-file. Everything else,
including rendering, audio, text, input, ECS, UI, physics and
platform-specific features, ships as plugins. The plugin system keeps the
architecture flexible without costing performance: plugins are composed at
compile time, with no run-time discovery or lookup, and an app compiles only
the plugins it needs.

## App metadata

An app declares its metadata as defines in its program file, the `.hxml`
file that `hxn run` and `hxn check` compile:

```
-lib hxnme
-main Main
-D hxnme_preset=game
```

`hxnme_preset` selects the Ash preset for the kind of app: `game`, `server`,
`application` or one of the others that `ash --help` lists. The preset sets
when Ash's hybrid and JIT modes compile a function, as in
`hxn run hl --vm ash`. hxn gives it to every Ash command that it runs for the
app. A `--preset` in the `--ash` or `--vm` command overrides the app's.

hxnme reads the defines in a build hook of the hxn command, and hxn passes
the options to Ash.
