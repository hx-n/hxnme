# Developing an app

`hxn me dev` runs an app on Ash and updates it when you save a file. Run it in the
directory of the program file:

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

After a Haxe file changes, the command compiles the app again and gives the running
app the new code. One Haxe compiler stays in memory while the command runs, and it
compiles again only the modules that a change affects. The app loop loads that code at the start of a frame, so the app
keeps its state: the values of its fields stay, and the next frames run the new
functions.

After an asset changes, the command sends the file to the running app. The app decodes
the file again, and the [handles](assets.md) to the asset give the new value. An image
that changes shows in everything that draws it, and an atlas keeps its `Region`
objects and gives them their new rectangles. When code and assets change together, the
new code starts in the same frame as the new assets. If a file does not decode, the
command prints the error, and the app keeps the value from before.

Some changes need a restart, and the command then restarts the app:

- Ash cannot load the change into the running app, for example because a class has a
  new static function.
- `hxnme.toml` or the program file changed.
- The app cannot load an asset again. This applies to fonts, to data that hxn-assets
  embeds at compile time, and to files that the app loads without the kernel's
  `Assets`.

If the app does not compile, the command prints the errors, and the running app stays
as it is. If the app crashes, it starts again after the next change. The command ends
when the app exits with status 0, for example because you close its window.

The app runs from `bin/<program file>/dev/run`, with the project directory as its
working directory. The check in `tests/dev` runs the command on an app without a
window, and changes its sources and its assets.
