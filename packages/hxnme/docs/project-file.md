# Project file

Each app keeps its plugins and its metadata in `hxnme.toml`. The file is
colocated with the program file of the app, which is the `.hxml` file that
`hxn run`, `hxn build` and `hxn package` compile. The program file selects
the kernel with `-lib hxnme`:

```
-lib hxnme
-main Main
```

```toml
plugins = ["hxnme-physics"]

[app]
preset = "game"
```

The kernel reads these keys:

| Key | Effect |
|---|---|
| `plugins` | The plugins of the app. Each name adds that haxelib and the haxelibs it depends on, the same way as `-lib`. Each path, such as `"./plugins/tilemap"`, adds the plugin in that directory, relative to `hxnme.toml`. The program file can also select a plugin with `-lib`. |
| `app.preset` | The Ash preset for the kind of app: `game`, `server`, `application`, or another preset that `ash --help` lists. The preset sets when Ash compiles a function to machine code in its hybrid and JIT modes, for example in `hxn run hl --vm ash`. The `--preset` flag in the `--ash` or `--vm` option of the hxn command overrides it. |
| `app.step` | The number of fixed steps in a second. The default is 60. |
| `app.step_snap` | The tolerance for a whole number of fixed steps in a frame, as a part of one step. The default is 0.1, and 0 turns the correction off. |
| `app.rate` | The number of frames in a second on `HeadlessHost`, the host of an app without a window. The default is 60. |
| `app.id` | The name of the app's storage, for its bundled files and saves, and the bundle identifier of its iOS app. The default is `hxnme`. |
| `app.frames` | The number of frames after which the app stops, for checks that run an app unattended. The default is 0, which runs the app until it quits. |
| `display.width`, `display.height`, `display.scale` | The display on `HeadlessHost`. The defaults are 1280, 720 and 1. |
| `display.refresh` | If the host does not set the refresh rate of the display, this key sets it, in frames a second. The default is 60. |
| `libraries.<plugin>` | Replaces the haxelibs that the plugin's manifest lists for some targets. Each key is part of a target triple, such as `linux`, and its value is the list for every target whose triple contains it. The longest key that matches applies. Paths are relative to `hxnme.toml`. |

Each plugin keeps its keys in its own table, such as `[window]`. Code reads
a key at compile time with `hxn.me.Project.text`, `number`, `integer` or
`flag`, and each call becomes a constant. For example,
`Project.text("window.title", "App")` becomes the title from the file. If
the file does not set a title, the call becomes `"App"`.
