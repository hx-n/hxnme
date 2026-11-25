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
app the new code. The app loop loads that code at the start of a frame, so the app
keeps its state: the values of its fields stay, and the next frames run the new
functions.

Some changes need a restart, and the command then restarts the app:

- Ash cannot load the change into the running app, for example because a class has a
  new static function.
- `hxnme.toml`, the program file or an asset changed.

If the app does not compile, the command prints the errors, and the running app stays
as it is. If the app crashes, it starts again after the next change. The command ends
when the app exits with status 0, for example because you close its window.

The app runs from `bin/<program file>/dev/run`, with the project directory as its
working directory. The check in `tests/dev` runs the command on an app without a
window, and changes its files.
