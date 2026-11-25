package hxn.me.dev;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import sys.net.Socket;

/** `Channel` sends and receives messages over a socket. Each message starts with its length. **/
@:noCompletion
class Channel {
	final socket:Socket;
	final chunk = Bytes.alloc(65536);
	var received = Bytes.alloc(0);

	public function new(socket:Socket)
		this.socket = socket;

	/** Sends `message`. It throws if the other end closed the socket. **/
	public function send(message:Bytes):Void {
		socket.output.writeInt32(message.length);
		socket.output.write(message);
		socket.output.flush();
	}

	/** Returns the messages that arrived, without waiting. It throws if the other end closed the socket. **/
	public function receive():Array<Bytes> {
		var all:Null<BytesBuffer> = null;
		while (Socket.select([socket], [], [], 0).read.length > 0) {
			var read = socket.input.readBytes(chunk, 0, chunk.length);
			if (all == null) {
				all = new BytesBuffer();
				all.add(received);
			}
			all.addBytes(chunk, 0, read);
		}
		var messages = [];
		if (all == null)
			return messages;
		received = all.getBytes();
		var at = 0;
		while (received.length - at >= 4 && received.length - at - 4 >= received.getInt32(at)) {
			var length = received.getInt32(at);
			messages.push(received.sub(at + 4, length));
			at += 4 + length;
		}
		received = received.sub(at, received.length - at);
		return messages;
	}

	public function close():Void
		socket.close();
}
