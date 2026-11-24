# Creating an app

`hxn me new <name>` creates a small game in a new directory called `<name>`.
It lists the window, input, GPU and 2D plugins in its `hxnme.toml`, and
declares an atlas and a font in `GameAssets`. The player moves with WASD,
the arrow keys or the left stick of a gamepad and collects gems, and a
screen camera draws the score:

```
hxn me new my-game
cd my-game
hxn run hl app.hxml
```

To run the game in a web page, compile it to wasm with Ash or with hxcpp:

```
hxn run hl app.hxml --wasm --threads --browser
hxn run cpp app.hxml --wasm --browser
```

The template keeps the license of its font in `licenses/`. Keep it with
the game, or replace the font. The check in `tests/new` creates a game with
the command and checks the files that it writes.
