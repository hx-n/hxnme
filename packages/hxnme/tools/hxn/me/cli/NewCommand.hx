package hxn.me.cli;

import hxn.cli.Context;

/**
	Creates a small 2D game in a new directory, in which the player collects
	gems. The game lists the window, input, GPU and 2D plugins in its
	`hxnme.toml`, and declares an atlas and a font in `GameAssets`.
**/
class NewCommand implements hxn.cli.Command {
	/** The name of the game and of its directory: letters, digits, `-` and `_`, starting with a letter. **/
	@:arg var name:String;

	public function run(context:Context):Int {
		Tool.create(name, context.cwd, context.root);
		return 0;
	}
}
