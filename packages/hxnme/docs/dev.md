# Hot reload

`hxn me dev` runs an app with hot reload of code and assets. When you save a file, the
running app gets the change and keeps its state. The app runs on Ash. Run the command
in the directory of the program file:

```
cd my-game
hxn me dev
```

It runs `app.hxml`. To run another program file, pass its name. The Ash command is
`ash`, the value of `HXN_ASH`, or the value of `--ash`:

```
hxn me dev tools.hxml --ash ~/ash/ash
```

The command watches these files:

- The Haxe files in the directory of the app and in its class paths, which include
  those of its plugins.
- The files in the assets directory.
- `hxnme.toml` and the program file.

If the app does not compile, the command prints the errors, and the running app stays
as it is. If the app crashes, it starts again after the next change. The command ends
when the app exits with status 0, for example because you close its window.

## Code hot reload

After a Haxe file changes, the command compiles the app again and hot reloads the new
code. The app loads that code at the start of a frame, so the app keeps its state: the
values of its fields stay, and the next frames run the new functions. One Haxe compiler
stays in memory while the command runs. It compiles again only the modules that a
change affects.

## Asset hot reload

After an asset changes, the command sends the file to the running app. The app decodes
the file again, and the [handles](assets.md) to the asset give the new value. Changed
images show in everything that draws them. Atlases keep their `Region` objects and give
them their new rectangles.

When code and assets change together, the new code starts in the same frame as the new
assets. If a file does not decode, the command prints the error, and the app keeps the
value from before.

## Changes that restart the app

Some changes cannot hot reload, and the command then restarts the app:

- Ash cannot hot reload the new code, for example because a class has a new static
  function.
- `hxnme.toml` or the program file changed.
- The app cannot hot reload the asset. This applies to fonts, to data that hxn-assets
  embeds at compile time, and to files that the app loads without the kernel's
  `Assets`.

The app runs from `bin/<program file>/dev/run`, with the project directory as its
working directory. The check in `tests/dev` runs the command on an app without a
window, and changes its sources and its assets.
