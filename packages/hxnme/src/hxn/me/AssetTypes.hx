package hxn.me;

import haxe.io.Bytes;
import hxn.Future;

/** The kernel's asset types for data. **/
class AssetTypes {
	/** The bytes of the file. **/
	public static final bytes = new AssetType<Bytes>("bytes", (bytes, _) -> Future.resolved(bytes));

	/** The file as UTF-8 text. **/
	public static final text = new AssetType<String>("text", (bytes, _) -> Future.resolved(bytes.toString()));

	/** The file parsed as JSON. **/
	public static final json = new AssetType<Dynamic>("json", (bytes, _) -> try Future.resolved(haxe.Json.parse(bytes.toString())) catch (e:haxe.Exception)
		Future.rejected(e));
}
