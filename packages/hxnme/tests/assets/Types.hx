import hxn.Future;
import hxn.me.AssetType;

/** Asset types that count their decodes and closes, for the check. **/
class Types {
	public static var decodes = 0;
	public static var closes = 0;
	public static var closedNotes = 0;

	public static final counted = new AssetType<String>("counted", (bytes, _) -> {
		decodes++;
		Future.resolved(bytes.toString());
	}, _ -> closes++);

	public static final note = new AssetType<String>("note", (bytes, _) -> Future.resolved(bytes.toString()), _ -> closedNotes++);

	// Joins the asset's text with other.txt, which it loads through its context, so other.txt is released with it.
	public static final pair = new AssetType<String>("pair", (bytes, context) -> context.load(context.resolve("other.txt"), note)
		.map(other -> bytes.toString() + " " + other));
}
