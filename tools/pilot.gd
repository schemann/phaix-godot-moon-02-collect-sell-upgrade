extends Node
## The hand of a take: where the player looks, walks and brushes, second by second, through the same input the game reads. tools/shots.gd calls tick() once per physics tick.
## Keys of the take's "pilot" block: stand [x, z], then keys, each {t, yaw, pitch, walk, side, sway, period, brush, lerp}. Yaw and pitch ease from key to key, the rest holds until the next key.
## A key with "lerp" true runs straight to the next one instead, walk and side too: the dense keys of a walk like a player at the keys (tools/make_takes.py `Walk`,
## a sample every 0.1 s of smooth curves) would otherwise stop the turn at every key.
## walk and side press the move actions with that strength; the actions' dead zone of 0.2 keeps the player standing below it, above it the speed is 3.2 * (value - 0.2) / 0.8 m/s.
## "tool" puts another tool scene in the hand before the take (the Widebar), "lane" {side, length, ahead, bend} pushes
## one gently curved lane with the tool the scene holds before that, beside the path; "prewash" brushes a track first, like a player at the keys.
## godot-moon-02: the state of the round before the take, as a player would have it there: "bought" sells that many items of the Tool
## Locker's row first (their tools and the bigger pack, as E would), "scrip" pays that much, "stored" puts that many kilograms into the Dustwell,
## "pack" that many into the Dust Pack ("pack": "full" fills it). The presses during the take are its events (E is a `key` event of "interact").

var _player: CharacterBody3D
var _moon: Node = null ## Main/Moon, for floor_at()
var _keys: Array = []

func setup(scene: Node, data: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = scene.get_node_or_null("Main") if scene.get_node_or_null("Main") != null else scene
	_player = game.get_node("Player")
	_keys = data.keys
	var stand: Array = data.stand
	var surface: Node = game.get_node("Moon/Surface")
	_player.global_position = Vector3(float(stand[0]), surface.height_at(float(stand[0]), float(stand[1])) + 0.05, float(stand[1]))
	_player.velocity = Vector3.ZERO
	_apply(float(_keys[0].get("yaw", 0.0)), float(_keys[0].get("pitch", 0.0)))
	if data.has("lane"):
		lane(game.get_node("Moon"), _player, float(data.lane.side), float(data.lane.length), float(data.lane.get("ahead", 0.0)), float(data.lane.get("bend", 0.0)))
	if data.has("tool"):
		hold(_player.get_node("Camera/Brush"), String(data.tool))
	if data.has("prewash") and not (data.prewash is bool and not data.prewash):
		## true: the lanes of godot-moon-01; {"far": [a, b]}: lanes that end a to b metres out (W1 of godot-moon-02 stops them short of the machines).
		var far: Array = data.prewash.get("far", [8.5, 12.0]) if data.prewash is Dictionary else [8.5, 12.0]
		prewash(game.get_node("Moon"), _player, Vector2(float(far[0]), float(far[1])))
	_round(game, data)

## The round so far (see the header): what was bought, the Scrip, the Dustwell's store and the pack.
func _round(game: Node, data: Dictionary) -> void:
	var locker: Node = game.get_node_or_null("Locker")
	for i in int(data.get("bought", 0)):
		var item: Resource = locker.row[locker.next]
		if item.tool != null:
			_player.brush.equip(item.tool)
		if float(item.get("capacity_kg") if "capacity_kg" in item else 0.0) > 0.0:
			_player.pack.upgrade(float(item.capacity_kg))
		locker.next += 1
		locker._show()
	if data.has("scrip"):
		_player.pay(int(data.scrip))
	var pack: Node = _player.get_node_or_null("Pack")
	if data.has("stored"):
		var well: Node = game.get_node("Dustwell")
		well.stored = roundi(float(data.stored) * pack.BYTES_PER_KG)
		well._show()
	if data.has("pack"):
		pack.add(pack.room() if str(data.pack) == "full" else roundi(float(data.pack) * pack.BYTES_PER_KG))
	## Every gram in the pack, in the Dustwell and shipped (the Scrip you have and the Scrip you spent, 5 a kilogram, dustwell.gd) was taken from
	## this tile, so DUST and CLEAN count it: what a prewash or a lane has not taken yet is counted as taken elsewhere on the tile, out of view.
	var moon: Node = game.get_node("Moon")
	var spent := 0
	for i in int(data.get("bought", 0)):
		spent += int(locker.row[i].price)
	var shipped_kg := (int(data.get("scrip", 0)) + spent) / 5.0
	var held: int = 0 if pack == null else int(pack.bytes)
	var well_node: Node = game.get_node_or_null("Dustwell")
	if well_node != null and "stored" in well_node:
		held += int(well_node.stored)
	var missing: int = held + roundi(shipped_kg * 255000.0) - int(moon.removed)
	if missing > 0:
		moon._count(missing)

## Another tool scene in the hand: brush.gd's own equip (steps 4 and 5) puts it there; before step 4 the same swap by hand, so the stamp is the new tool's head.
func hold(brush: Node3D, path: String) -> void:
	var scene := load(path) as PackedScene
	if brush.has_method("equip"):
		brush.equip(scene)
		return
	var old: Node = brush.get_node("Model")
	var model: Node3D = scene.instantiate()
	brush.remove_child(old)
	old.free()
	model.name = "Model"
	brush.add_child(model)
	brush.move_child(model, 0)
	brush.model = model
	brush.head = model.get_node("Head")
	brush.footprint = model.get_meta("footprint")
	brush.round_head = model.get_meta("round", false)

## One push before the take with the tool in the hand: from where the head lands (REACH * 0.85 out at the pitches of the takes) plus
## `ahead` metres (where the take's own stroke starts after its head), `side` metres to the right, `length` metres away, the head facing along it.
## `bend` metres: the lane drifts that far to the right by its end, along a gentle curve, like a player's push at the keys. Step 3 has no
## sweep yet, so there the lane is clean() every 10 cm, as its brush stamps once a tick.
func lane(moon: Node3D, player: Node3D, side: float, length: float, ahead := 0.0, bend := 0.0) -> void:
	var brush: Node = player.get_node("Camera/Brush")
	var away := -player.global_basis.z
	var right := player.global_basis.x
	var start := player.global_position + away * (float(brush.REACH) * 0.85 + ahead) + right * side
	var last := start
	moon.clean(start, away, brush.footprint, brush.round_head, brush.AMOUNT)
	var along := 0.1
	while along <= length:
		var next := start + away * along + right * (bend * pow(along / length, 2.0))
		var heading := last.direction_to(next)
		if moon.has_method("sweep"):
			moon.sweep(last, next, heading, brush.footprint, brush.round_head, brush.AMOUNT)
		else:
			moon.clean(next, heading, brush.footprint, brush.round_head, brush.AMOUNT)
		last = next
		along += 0.1

const PREWASH_SEED := 311 ## The prewash is the same track on every run.

## Real strokes before the take starts, as a player at the keys brushes them, with the brush's own calls (moon.clean
## where the head comes down, then moon.sweep with the tool's footprint and AMOUNT, one pass): one continuous path of the head, five lanes out and
## back along the crater's winding path, each with its own length, its own near end and its own small wobble, the next lane 0.75 to 0.95 m beside
## the last under the 1 m head, so neighbours overlap a little and no two run ruler-parallel. The head faces away all the time, as a push broom
## does: it pushes the lanes out, slides over at their ends along a rounded corner and pulls the next lane back. A sweep goes 2 cm, about what a
## tick of the hand moves (in steps of 25 cm the head's outer corners jumped 4 cm at every step and the walls came out as a saw, W1 of
## 2026-11-04). Turning the head round in the corners left specks of dust on the floor: a stamp's `before` is the stamp before it turned to this
## heading, and in a turn tighter than half the head that covers ground the stamp before never touched (G7E of 2026-11-04 17:10).
func prewash(moon: Node3D, player: Node3D, far := Vector2(8.5, 12.0)) -> void:
	var brush: Node = player.get_node("Camera/Brush")
	var right := player.global_basis.x
	var away := -player.global_basis.z
	var origin := player.global_position + away * 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = PREWASH_SEED
	var facing := PackedVector2Array()
	var path := _prewash_path(rng, facing, far)
	var last := origin + away * path[0].x + right * path[0].y
	moon.clean(last, (away * facing[0].x + right * facing[0].y).normalized(), brush.footprint, brush.round_head, brush.AMOUNT)
	for i in range(1, path.size()):
		var next := origin + away * path[i].x + right * path[i].y
		moon.sweep(last, next, (away * facing[i].x + right * facing[i].y).normalized(), brush.footprint, brush.round_head, brush.AMOUNT)
		last = next

## The head's path of the prewash, points 2 cm apart as (metres away from the origin, metres to its right); `facing` gets the way the head
## faces at each point: along its lane, pointing away, and in a corner turning from the one lane's end to the next lane's start.
func _prewash_path(rng: RandomNumberGenerator, facing: PackedVector2Array, reach := Vector2(8.5, 12.0)) -> PackedVector2Array:
	var path := PackedVector2Array()
	var across := -1.8
	for row in 5:
		var near := rng.randf_range(0.0, 0.8)
		var far := rng.randf_range(reach.x, reach.y) - absf(across) * 0.3
		var wobble := rng.randf_range(0.05, 0.15)
		var rate := rng.randf_range(0.25, 0.45)
		var phase := rng.randf_range(0.0, TAU)
		var strip := PackedVector2Array()
		var along := near
		while along <= far:
			strip.append(Vector2(along, across + sin(along * 0.5) * 1.4 + wobble * sin(along * rate + phase)))
			along += 0.02
		var ways := PackedVector2Array()
		for k in strip.size():
			ways.append(strip[mini(k + 1, strip.size() - 1)] - strip[maxi(k - 1, 0)])
			ways[k] = ways[k].normalized()
		if row % 2 == 1:
			strip.reverse()
			ways.reverse()
		if not path.is_empty():
			_turn(path, facing, path[path.size() - 1], strip[0], 1.0 if row % 2 == 1 else -1.0, facing[facing.size() - 1], ways[0])
		path.append_array(strip)
		facing.append_array(ways)
		across += rng.randf_range(0.75, 0.95)
	return path

## A rounded corner from the end of one lane to the start of the next: the head slides over beyond the ends, `out` is the way the lane was
## going, and it turns from `from_way` to `to_way` as it goes.
func _turn(path: PackedVector2Array, facing: PackedVector2Array, from: Vector2, to: Vector2, out: float, from_way: Vector2, to_way: Vector2) -> void:
	var bulge := Vector2(0.5 * out, 0.0)
	var steps := maxi(2, ceili((from.distance_to(to) + 1.0) / 0.02))
	for k in range(1, steps):
		var u := float(k) / steps
		var a := from.lerp(from + bulge, u)
		var b := (from + bulge).lerp(to + bulge, u)
		var c := (to + bulge).lerp(to, u)
		path.append(a.lerp(b, u).lerp(b.lerp(c, u), u))
		facing.append(from_way.lerp(to_way, u).normalized())

func tick(at: float) -> void:
	var previous: Dictionary = _keys[0]
	var next: Dictionary = _keys[0]
	for key: Dictionary in _keys:
		if float(key.t) <= at:
			previous = key
			next = key
		else:
			next = key
			break
	var span := float(next.t) - float(previous.t)
	var straight := bool(previous.get("lerp", false))
	var share := 1.0 if span <= 0.0 else clampf((at - float(previous.t)) / span, 0.0, 1.0)
	if not straight:
		share = smoothstep(0.0, 1.0, share)
	var sway: float = float(previous.get("sway", 0.0)) * sin(at * TAU / float(previous.get("period", 2.0)))
	_apply(lerpf(float(previous.get("yaw", 0.0)), float(next.get("yaw", previous.get("yaw", 0.0))), share) + sway,
			lerpf(float(previous.get("pitch", 0.0)), float(next.get("pitch", previous.get("pitch", 0.0))), share))
	var walk := float(previous.get("walk", 0.0))
	var side := float(previous.get("side", 0.0))
	if straight:
		walk = lerpf(walk, float(next.get("walk", walk)), share)
		side = lerpf(side, float(next.get("side", side)), share)
	_axis("move_forward", "move_back", walk)
	_axis("move_right", "move_left", side)
	if bool(previous.get("brush", false)):
		Input.action_press("brush")
	else:
		Input.action_release("brush")

func _apply(yaw: float, pitch: float) -> void:
	_player.rotation.y = yaw
	_player.camera.rotation.x = pitch

func _axis(positive: String, negative: String, value: float) -> void:
	if value > 0.0:
		Input.action_press(positive, value)
		Input.action_release(negative)
	elif value < 0.0:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)

## The tool head as series rule 65 reads it. While the brush action is not held brush.gd hangs the head in the air (`lift`: up while the action is not held, down on the
## ground while it is; the old lift on a full pack is gone):
## it works no floor then and hangs over it on purpose, so it is not logged until it is down again. The rule is about a head that works the floor: "A tool head
## that works the floor (a broom, a brush) is on the floor while it works." A head in the air that takes dust (mask bytes gone since the last look) is logged
## like any other: its gap over the ground fails the take.
class HeadProbe extends RefCounted:
	var brush: Node
	var _removed := -1 ## What the moon had taken at the last look, or -1 before the first.
	var head: Variant:
		get:
			var removed: int = int(brush.get("moon").get("removed"))
			var took := _removed >= 0 and removed > _removed
			_removed = removed
			var raised: Variant = brush.get("lift") ## null in the steps before the lift
			return null if raised != null and float(raised) > 0.001 and not took else brush.get("head")

## Series rule 65: what the take tool (godot-mini/tools/take/shots.gd) logs against the ground: the head of the tool in the hand (it works the
## floor: its worst third across its width counts) and every machine that stands on the moon (its lowest point).
func grounded(scene: Node) -> Array:
	var game: Node = scene.get_node_or_null("Main") if scene.get_node_or_null("Main") != null else scene
	_moon = game.get_node_or_null("Moon")
	var out: Array = []
	var brush: Node = _player.get_node_or_null("Camera/Brush")
	if brush != null and brush.get("head") is Node3D: ## steps 0 to 2 of godot-moon-01 have no brush yet
		var probe := HeadProbe.new()
		probe.brush = brush
		out.append({node = probe, prop = "head", kind = "head", name = "tool head"}) ## read each time: the Tool Locker swaps the tool
	for child: Node in game.get_children():
		if child is Node3D and child != _player and child != _moon and not child.find_children("*", "StaticBody3D", true, false).is_empty():
			out.append({node = child, kind = "base", name = String(child.name)})
	return out

## The ground the picture shows at x, z: the rock of the surface, and on it the layer of dust where the tile still holds half a layer or more
## (the surface shader lifts it by `dust_metres`; a step whose shader has no dust stands on the rock).
func floor_at(x: float, z: float) -> float:
	var y := float(_moon.get_node("Surface").height_at(x, z))
	var tile: Variant = _moon.get("tile")
	var material: Variant = _moon.get_node("Surface").get("material")
	var lift: Variant = (material as ShaderMaterial).get_shader_parameter("dust_metres") if material is ShaderMaterial else null
	if tile != null and lift != null:
		var sizes: Dictionary = ((tile as RefCounted).get_script() as GDScript).get_script_constant_map()
		var pixels: int = sizes.PIXELS
		var metres: float = sizes.METRES
		var px := clampi(int((x + metres / 2.0) / metres * pixels), 0, pixels - 1)
		var pz := clampi(int((z + metres / 2.0) / metres * pixels), 0, pixels - 1)
		@warning_ignore("integer_division") ## half of FULL, rounded down on purpose: the mask bytes from there up count as dust
		if int(tile.bytes[pz * pixels + px]) >= int(sizes.FULL) / 2:
			y += float(lift)
	return y
