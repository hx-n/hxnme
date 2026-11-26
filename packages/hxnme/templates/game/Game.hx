import hxn.me.Asset;
import hxn.me.Assets;
import hxn.me.Display;
import hxn.me.Res;
import hxn.me.ResMut;
import hxn.me.Time;
import hxn.me.gpu.Camera;
import hxn.me.gpu.Cameras;
import hxn.me.input.Input;
import hxn.me.render2d.Draw;
import hxn.me.render2d.Shadow;
import hxn.me.render2d.Text;
import hxn.me.render2d.Typesetter;
import hxn.text.Font;

/**
	`Game` holds the systems of a small game. The player moves with WASD, the
	arrow keys or the left stick of a gamepad, and collects the gems. R or the
	Start button of the gamepad starts the game again. The floor fills the
	window, or the screen of a mobile device, with one unit for each logical
	pixel and y up. The player, the gems and the score stay in the display's
	safe area, clear of a notch and the home indicator. A screen camera draws
	the score over the floor.
**/
class Game {
	static inline final SPEED = 320.0;
	static inline final GEMS = 5;
	// The player collects a gem when the player's center comes this near to the gem's center.
	static inline final REACH = 26.0;
	// The score is on this layer, which the screen camera draws over the world.
	static inline final HUD = 2;
	// These shadows draw flattened silhouettes on the ground under the player and the gems.
	static final ground = new Shadow(0, -14, 4, 0x000000, 0.45, 0.4);
	static final gemGround = new Shadow(0, -10, 3, 0x000000, 0.35, 0.4);

	static var sheet:Null<Asset<GameAssetsSheetAtlas>>;
	static var font:Null<Asset<Font>>;
	static var label:Null<Text>;
	// These hold the size of the floor and the bounds of the safe area in it, which `fit` takes from the display in each frame.
	static var width = 0.0;
	static var height = 0.0;
	static var left = 0.0;
	static var right = 0.0;
	static var bottom = 0.0;
	static var top = 0.0;
	static var x = 0.0;
	static var y = 0.0;
	static var score = 0;
	// Holds the centers of the gems, as pairs of x and y.
	static final gems:Array<Float> = [];

	@:system(Start)
	static function setup(cameras:ResMut<Cameras>, assets:ResMut<Assets>, display:Res<Display>) {
		fit(cameras, display);
		x = (left + right) / 2;
		y = (bottom + top) / 2;
		var hud = new Camera();
		hud.projection = Screen;
		hud.layers = HUD;
		hud.order = 1;
		cameras.add(hud);
		var store:Assets = assets;
		store.load(GameAssets.Sheet).then(a -> sheet = a);
		store.load(GameAssets.Ui).then(f -> font = f);
		for (_ in 0...GEMS) {
			gems.push(0);
			gems.push(0);
		}
		for (i in 0...GEMS)
			place(i);
	}

	@:system(Update)
	static function play(input:Res<Input<Action>>, time:Res<Time>, typesetter:ResMut<Typesetter>) {
		if (font != null && label == null)
			label = (typesetter : Typesetter).text(font.value, 'Score $score', {size: 24});
		if (input.pressed(Restart))
			setScore(0);
		var dx = clamp(input.value(MoveX)), dy = -clamp(input.value(MoveY));
		var length = Math.sqrt(dx * dx + dy * dy);
		if (length > 1) {
			dx /= length;
			dy /= length;
		}
		x = Math.max(left + 16, Math.min(right - 16, x + dx * SPEED * time.delta));
		y = Math.max(bottom + 16, Math.min(top - 16, y + dy * SPEED * time.delta));
		for (i in 0...GEMS)
			if (Math.abs(gems[i * 2] - x) < REACH && Math.abs(gems[i * 2 + 1] - y) < REACH) {
				setScore(score + 1);
				place(i);
			}
	}

	// Makes the floor the size of the display, and moves the gems that a smaller safe area leaves out back into it.
	@:system(Begin)
	static function fit(cameras:ResMut<Cameras>, display:Res<Display>) {
		var scale = display.scale;
		width = display.width / scale;
		height = display.height / scale;
		// The world has y up, so the bottom inset is at the smallest y.
		left = display.safeLeft / scale;
		right = width - display.safeRight / scale;
		bottom = display.safeBottom / scale;
		top = height - display.safeTop / scale;
		var main = cameras.main;
		main.x = width / 2;
		main.y = height / 2;
		for (i in 0...Std.int(gems.length / 2))
			if (gems[i * 2] < left + 40 || gems[i * 2] > right - 40 || gems[i * 2 + 1] < bottom + 40 || gems[i * 2 + 1] > top - 40)
				place(i);
	}

	// Draws the floor, the gems, the player and the score in each frame, in that order.
	@:system(Update, after = Game.play)
	static function draw(draw:ResMut<Draw>, display:Res<Display>) {
		var d:Draw = draw;
		d.layer = 1;
		d.rect(0, 0, width, height, 0x1B2430);
		if (sheet == null)
			return;
		// The atlas has a property for each region of sheet.json. Each region has its pivot at its center.
		var atlas = sheet.value;
		for (i in 0...GEMS)
			d.region(atlas.gem, gems[i * 2], gems[i * 2 + 1], gemGround);
		d.region(atlas.player, x, y, ground);
		d.layer = HUD;
		// The screen camera has y down, from the top left corner of the display.
		var hudX = display.safeLeft / display.scale + 16, hudY = display.safeTop / display.scale + 16;
		d.regionSlice(atlas.panel, hudX, hudY, 180, 48);
		if (label != null)
			d.text(label, hudX + 16, hudY + 10, 0xF1F5F9);
	}

	static function setScore(value:Int) {
		score = value;
		if (label != null)
			label.set('Score $score');
	}

	// Moves gem `i` to a random place in the safe area, away from its edges.
	static function place(i:Int) {
		gems[i * 2] = left + 40 + Math.random() * Math.max(0, right - left - 80);
		gems[i * 2 + 1] = bottom + 40 + Math.random() * Math.max(0, top - bottom - 80);
	}

	static function clamp(v:Float):Float
		return v < -1 ? -1 : v > 1 ? 1 : v;
}
