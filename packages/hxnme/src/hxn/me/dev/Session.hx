package hxn.me.dev;

#if hxnme_dev
import haxe.io.Bytes;
import sys.net.Host;
import sys.net.Socket;

/**
	`Session` connects a running app to `hxn me dev`, which gives its address
	in `HXNME_DEV`, or for Android in `-D hxnme_dev_address`. It takes one update at a time. The assets of the update
	load first, and the code loads in the frame in which they are ready, so
	new code never runs with the assets from before.
**/
@:noCompletion
class Session {
	static var started = false;
	static var channel:Null<Channel>;
	static final updates:Array<Update> = [];
	static var current:Null<Update>;
	static var ready = false;

	/** Takes the updates that arrived. The app loop calls it at the start of each frame. **/
	public static function frame():Void {
		if (!started) {
			started = true;
			connect();
		}
		if (channel == null)
			return;
		try
			for (message in channel.receive())
				updates.push(Update.read(message))
		catch (_:haxe.Exception)
			channel = null;
		if (current == null && updates.length > 0)
			begin(updates.shift());
		if (current != null && ready) {
			var code = current.code;
			current = null;
			if (code)
				hl.Api.checkReload();
		}
	}

	static function begin(update:Update) {
		current = update;
		ready = false;
		var assets = Assets.current;
		if (assets == null) {
			for (path in update.files.keys())
				restart('$path changed');
			ready = true;
		} else
			assets.update(update.files).then(_ -> ready = true);
	}

	static function connect() {
		var address = Sys.getEnv("HXNME_DEV");
		#if hxnme_dev_address
		if (address == null)
			address = haxe.macro.Compiler.getDefine("hxnme_dev_address");
		#end
		if (address == null)
			return;
		var parts = address.split(":");
		var socket = new Socket();
		try {
			socket.connect(new Host(parts[0]), Std.parseInt(parts[1]));
			socket.setFastSend(true);
			channel = new Channel(socket);
		} catch (_:haxe.Exception)
			socket.close();
	}

	/** Asks `hxn me dev` to restart the app, because of `reason`. **/
	public static function restart(reason:String):Void
		send("restart " + reason);

	/** Prints `text` as a message of `hxn me dev`. **/
	public static function say(text:String):Void
		send("say " + text);

	static function send(text:String) {
		if (channel == null)
			return;
		try
			channel.send(Bytes.ofString(text))
		catch (_:haxe.Exception)
			channel = null;
	}
}
#end
