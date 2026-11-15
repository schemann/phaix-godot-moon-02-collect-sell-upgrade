extends SceneTree
## Headless tests for godot-moon-02. From the repository root:
##   godot --headless --path godot-moon/02-collect-sell-upgrade -s res://tests/run_tests.gd
## Prints PASS or FAIL per test and exits with 0 only if every test passed. `-- --only=text` runs the tests whose name contains the text.

const STEPS: Array[String] = ["step_00_start", "step_01_pack", "step_02_dustwell", "step_03_lofter", "step_04_locker", "step_05_round"]
const FINAL := "step_05_round"
const Tile := preload("res://steps/step_05_round/dust_tile.gd")
const MoonScript := preload("res://steps/step_05_round/moon.gd")
const DustPack := preload("res://steps/step_05_round/dust_pack.gd")
const BrushScript := preload("res://steps/step_05_round/brush.gd")
const BRUSH := Vector2(1.0, 0.24) ## The Brushbar's footprint (models/brushbar.tscn): metres across and along the pole.
const AMOUNT := 255 ## brush.gd: one pass takes the whole layer.
const PUSH := Vector3.RIGHT ## A stroke along +x with the head facing +x: a forward push, the head's footprint across it.
const SIDEWAYS := Vector3.FORWARD ## A stroke along +x with the head facing -z: the head slides along its own length.

## What each step adds to the one before.
const NEW_FILES: Dictionary[String, Array] = {
	"step_01_pack": ["dust_pack.gd"],
	"step_02_dustwell": ["dustwell.gd"],
	"step_03_lofter": ["lofter.tscn"],
	"step_04_locker": ["item.gd", "tool_locker.gd", "widebar.tres"],
	"step_05_round": ["dust_pack_4kg.tres", "rotary_scrubber.tres"],
}

var _failed := 0
var _only := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
	_all.call_deferred()

func _all() -> void:
	for test: Callable in [
		_a_stamp_stops_at_its_limit, _a_stroke_stops_at_its_limit, _the_pack_holds_what_left_the_mask, _a_full_pack_takes_nothing_more,
		_the_dustwell_takes_the_whole_pack, _a_launch_pays_for_every_kilogram, _a_new_lofter_comes_up, _e_reaches_a_machine_within_reach,
		_the_locker_sells_in_order, _no_scrip_no_tool, _a_bought_tool_is_in_the_hand, _the_widebar_clears_a_wider_stripe,
		_a_disc_clears_its_width_in_every_direction, _a_bigger_pack_holds_twice_as_much, _the_pole_is_two_metres,
		_the_head_hangs_until_the_brush_is_held, _a_full_pack_does_not_lift_the_head, _a_head_in_the_air_takes_nothing, _a_tool_plays_its_brush_animation_only_while_brushing, _every_step_hangs_the_head_the_same_way, _the_ground_log_sees_a_head_that_takes_dust_in_the_air, _the_machines_stand_on_level_bare_ground, _a_cleaned_tile_reads_a_hundred_percent,
		_every_step_adds_its_files, _every_step_loads, _no_light_shows_a_warning_triangle, _every_scene_is_on_jolt,
	]:
		if _only.is_empty() or test.get_method().contains(_only):
			await test.call()
	print("RESULT %s" % ("PASS" if _failed == 0 else "FAIL %d" % _failed))
	quit(0 if _failed == 0 else 1)

func _check(name_of_test: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name_of_test, detail])
	if not ok:
		_failed += 1

func _sum_gone(tile: RefCounted) -> int:
	var gone := 0
	for value: int in tile.bytes:
		gone += Tile.FULL - value
	return gone

## A stamp with a limit takes exactly that much and leaves the rest of the dust where it lies.
func _a_stamp_stops_at_its_limit() -> void:
	var tile: RefCounted = Tile.new()
	var taken: int = tile.stamp(Vector3.ZERO, PUSH, BRUSH, false, AMOUNT, Vector3.INF, 10000)
	var free: RefCounted = Tile.new()
	var whole: int = free.stamp(Vector3.ZERO, PUSH, BRUSH, false, AMOUNT)
	_check("a stamp stops at its limit", taken == 10000 and _sum_gone(tile) == 10000 and whole > 10000, "took %d of %d, the head holds %d" % [taken, 10000, whole])

## A stroke shares one limit over all its stamps: the whole stroke takes at most the limit.
func _a_stroke_stops_at_its_limit() -> void:
	var moon: Node3D = _moon()
	var taken: int = moon.sweep(Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), PUSH, BRUSH, false, AMOUNT, 200000)
	var gone := _sum_gone(moon.tile)
	_check("a stroke stops at its limit", taken == 200000 and gone == 200000 and moon.removed == 200000, "took %d, the mask lost %d" % [taken, gone])
	moon.free()

## The pack counts bytes like the moon: while it has room, it holds exactly what left the mask.
func _the_pack_holds_what_left_the_mask() -> void:
	var moon: Node3D = _moon()
	var pack: Node3D = DustPack.new()
	for i in 2: ## Two strokes of 3 m, about 0.77 kg each: the 2 kg pack does not fill.
		var z := -4.0 + i * 1.2
		pack.add(moon.sweep(Vector3(-1.5, 0.0, z), Vector3(1.5, 0.0, z), PUSH, BRUSH, false, AMOUNT, pack.room()))
	_check("the pack holds what left the mask", pack.bytes == moon.removed and pack.bytes == _sum_gone(moon.tile) and not pack.is_full(),
		"pack %d bytes (%.2f kg), mask lost %d" % [pack.bytes, pack.kilograms(), _sum_gone(moon.tile)])
	pack.free()
	moon.free()

## A full pack has no room, so the brush leaves the dust where it is: the mask keeps every byte the pack could not take.
func _a_full_pack_takes_nothing_more() -> void:
	var moon: Node3D = _moon()
	var pack: Node3D = DustPack.new()
	for i in 12:
		var z := -7.0 + i * 1.2
		pack.add(moon.sweep(Vector3(-7.0, 0.0, z), Vector3(7.0, 0.0, z), PUSH, BRUSH, false, AMOUNT, pack.room()))
	var before: int = moon.removed
	var more: int = moon.sweep(Vector3(-7.0, 0.0, 9.0), Vector3(7.0, 0.0, 9.0), PUSH, BRUSH, false, AMOUNT, pack.room())
	var full: bool = pack.is_full() and is_equal_approx(pack.kilograms(), 2.0)
	_check("a full pack takes nothing more", full and more == 0 and moon.removed == before, "pack %.3f kg, a stroke more took %d" % [pack.kilograms(), more])
	pack.free()
	moon.free()

func _moon() -> Node3D:
	return MoonScript.new()

func _final() -> Node:
	return (load("res://steps/%s/main.tscn" % FINAL) as PackedScene).instantiate()

## E at the Dustwell: the whole pack goes in, byte for byte, and the pack is empty.
func _the_dustwell_takes_the_whole_pack() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var dustwell: Node3D = scene.get_node("Dustwell")
	player.pack.add(300000)
	dustwell.use(player)
	_check("the Dustwell takes the whole pack", dustwell.stored == 300000 and player.pack.bytes == 0, "stored %d, pack %d" % [dustwell.stored, player.pack.bytes])
	await _drop(scene)

## E again: the Lofter takes everything, and the launch pays 5 Scrip for every kilogram.
func _a_launch_pays_for_every_kilogram() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var dustwell: Node3D = scene.get_node("Dustwell")
	player.pack.add(DustPack.BYTES_PER_KG * 2)
	dustwell.use(player)
	var lofter: Node3D = dustwell.lofter
	dustwell.use(player)
	for i in 30:
		await physics_frame
	var flying: bool = is_instance_valid(lofter) and lofter.position.y > 0.05 and lofter.get_node("Exhaust").emitting
	_check("a launch pays for every kilogram", player.scrip == 10 and dustwell.stored == 0 and dustwell.lofter == null and flying,
		"scrip %d, stored %d, the Lofter at %.2f m" % [player.scrip, dustwell.stored, lofter.position.y if is_instance_valid(lofter) else -1.0])
	await _drop(scene)

## Three seconds after a launch, the next Lofter comes up into the cradle and stands there, ready.
func _a_new_lofter_comes_up() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var dustwell: Node3D = scene.get_node("Dustwell")
	player.pack.add(DustPack.BYTES_PER_KG)
	dustwell.use(player)
	dustwell.use(player)
	await create_timer(5.5).timeout
	var next: Node3D = dustwell.lofter
	var ok: bool = next != null and absf(next.position.y) < 0.01 and next.get_parent() == dustwell.socket
	_check("a new Lofter comes up", ok, "the new Lofter at %s" % (str(next.position) if next != null else "none"))
	await _drop(scene)

## The player's E reaches the machine whose middle is within 3.5 m, and nothing further away.
func _e_reaches_a_machine_within_reach() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var dustwell: Node3D = scene.get_node("Dustwell")
	player.global_position = dustwell.global_position + Vector3(0.0, 0.0, -3.4)
	var near: Node3D = player.station()
	player.global_position = dustwell.global_position + Vector3(0.0, 0.0, -3.6)
	var far: Node3D = player.station()
	_check("E reaches a machine within 3.5 metres", near == dustwell and far == null, "at 3.4 m %s, at 3.6 m %s" % [near, far])
	await _drop(scene)

## The Tool Locker sells its row in order: the Widebar first, then the bigger pack, then the Rotary Scrubber.
func _the_locker_sells_in_order() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var locker: Node3D = scene.get_node("Locker")
	var titles: Array[String] = []
	for item: Resource in locker.row:
		titles.append("%s %d" % [item.title, item.price])
	player.pay(100)
	locker.use(player)
	var after_one: int = player.scrip
	locker.use(player)
	locker.use(player)
	var ok: bool = str(titles) == str(["Widebar 20", "Dust Pack 4 kg 30", "Rotary Scrubber 50"]) and after_one == 80 and player.scrip == 0 and locker.next == 3
	_check("the Tool Locker sells in order", ok and locker.screen.text == "SOLD OUT", "%s, scrip after one %d, after three %d" % [str(titles), after_one, player.scrip])
	await _drop(scene)

## Without the Scrip for the next item, E changes nothing.
func _no_scrip_no_tool() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var locker: Node3D = scene.get_node("Locker")
	player.pay(19)
	locker.use(player)
	var ok: bool = player.scrip == 19 and locker.next == 0 and player.brush.footprint == BRUSH
	_check("no Scrip, no tool", ok and locker.prompt(player) == "Widebar costs 20 Scrip", "scrip %d, next %d, prompt %s" % [player.scrip, locker.next, locker.prompt(player)])
	await _drop(scene)

## A bought tool is in the hand at once: its model, its Head on the ground and its footprint.
func _a_bought_tool_is_in_the_hand() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	player.pay(20)
	scene.get_node("Locker").use(player)
	for i in 4:
		await physics_frame
	var brush: Node3D = player.brush
	var joint: Vector3 = brush.aim() + Vector3.UP * (BrushScript.JOINT + brush.lift) ## the idle pose hangs the head LIFT over the ground
	var ok: bool = brush.footprint == Vector2(1.6, 0.27) and brush.model.scene_file_path == "res://models/widebar.tscn" and brush.head.global_position.distance_to(joint) < 0.25
	_check("a bought tool is in the hand", ok, "footprint %s, model %s" % [brush.footprint, brush.model.scene_file_path])
	await _drop(scene)

func _cleared_across(tile: RefCounted, z_from: float, z_to: float, x: float) -> float:
	var pixel := Tile.METRES / Tile.PIXELS
	var cleared := 0
	var z := z_from
	while z <= z_to:
		var px := int((x + Tile.METRES / 2.0) / pixel)
		var pz := int((z + Tile.METRES / 2.0) / pixel)
		if tile.bytes[pz * Tile.PIXELS + px] < Tile.FULL / 2.0:
			cleared += 1
		z += pixel
	return cleared * pixel

## One push of the Widebar clears a stripe 1.6 m wide, the Brushbar's 1.0 m: the footprint of the tool scene decides.
func _the_widebar_clears_a_wider_stripe() -> void:
	var wide: Vector2 = (load("res://models/widebar.tscn") as PackedScene).instantiate().get_meta("footprint")
	var narrow: RefCounted = Tile.new()
	var broad: RefCounted = Tile.new()
	var moon_a: Node3D = _moon()
	moon_a.tile = narrow
	moon_a.sweep(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), PUSH, BRUSH, false, AMOUNT)
	var moon_b: Node3D = _moon()
	moon_b.tile = broad
	moon_b.sweep(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), PUSH, wide, false, AMOUNT)
	var a := _cleared_across(narrow, -2.0, 2.0, 0.0)
	var b := _cleared_across(broad, -2.0, 2.0, 0.0)
	_check("the Widebar clears a wider stripe", absf(a - 1.0) < 0.07 and absf(b - 1.6) < 0.07, "Brushbar %.2f m, Widebar %.2f m" % [a, b])
	moon_a.free()
	moon_b.free()

## A bar clears its width only when it is pushed along the pole; slid along its length it clears its depth. The Rotary Scrubber's disc
## clears its 1.2 m whichever way it moves.
func _a_disc_clears_its_width_in_every_direction() -> void:
	var disc: Node3D = (load("res://models/rotary_scrubber.tscn") as PackedScene).instantiate()
	var size: Vector2 = disc.get_meta("footprint")
	var round_head: bool = disc.get_meta("round", false)
	disc.free()
	var widths: Array[float] = []
	for setup: Array in [[BRUSH, false, PUSH], [BRUSH, false, SIDEWAYS], [size, round_head, PUSH], [size, round_head, SIDEWAYS]]:
		var moon: Node3D = _moon()
		moon.sweep(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), setup[2], setup[0], setup[1], AMOUNT)
		widths.append(_cleared_across(moon.tile, -2.0, 2.0, 0.0))
		moon.free()
	var ok := round_head and absf(widths[0] - 1.0) < 0.07 and absf(widths[1] - 0.24) < 0.07 and absf(widths[2] - 1.2) < 0.07 and absf(widths[3] - 1.2) < 0.07
	_check("a disc clears its width in every direction", ok, "bar pushed %.2f m, bar sideways %.2f m, disc %.2f m and %.2f m" % widths)

## The bigger pack has room for 4 kg, twice the 2 kg it starts with, and keeps what is inside.
func _a_bigger_pack_holds_twice_as_much() -> void:
	var pack: Node3D = DustPack.new()
	var first: int = pack.room()
	pack.add(1000)
	pack.upgrade(4.0)
	_check("a bigger pack holds twice as much", first == DustPack.BYTES_PER_KG * 2 and pack.room() == DustPack.BYTES_PER_KG * 4 - 1000 and pack.bytes == 1000,
		"room %d, then %d" % [first, pack.room()])
	pack.free()

## The pole is 2.0 m from the grip to Head in all three tools, and the head lands 2.3 x 0.85 = 1.96 m ahead of the eye on flat ground.
func _the_pole_is_two_metres() -> void:
	var poles: Array[float] = []
	for path: String in ["res://models/brushbar.tscn", "res://models/widebar.tscn", "res://models/rotary_scrubber.tscn"]:
		var tool: Node3D = (load(path) as PackedScene).instantiate()
		poles.append((tool.get_node("Head") as Node3D).position.z)
		tool.free()
	var scene := _final()
	root.add_child(scene)
	var player: Node3D = scene.get_node("Player")
	player.global_position = Vector3(1.5, scene.get_node("Moon/Surface").height_at(1.5, 0.0) + 0.05, 0.0)
	player.camera.rotation.x = -0.3
	for i in 6:
		await physics_frame
	var aim: Vector3 = player.brush.aim()
	var eye: Vector3 = player.camera.global_position
	var ahead := Vector2(aim.x - eye.x, aim.z - eye.z).length()
	var two := poles.all(func(pole: float) -> bool: return absf(pole - 2.0) < 0.001)
	_check("the pole is two metres", two and absf(ahead - BrushScript.REACH * 0.85) < 0.02, "poles %s, the head %.3f m ahead" % [str(poles), ahead])
	await _drop(scene)

## The idle pose and the brushing pose: the head hangs
## LIFT over the ground while the brush action is not held and is on the ground while it is held, and it starts to move in the frame the action is pressed or let go
## (onset, not completion): down in DOWN_TIME, up in UP_TIME. The pack has nothing to do with it.
func _the_head_hangs_until_the_brush_is_held() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var brush: Node3D = player.brush
	player.global_position = Vector3(1.5, scene.get_node("Moon/Surface").height_at(1.5, 0.0) + 0.05, 0.0)
	player.camera.rotation.x = -0.3
	for i in 40: ## the idle pose from the first frame on
		await physics_frame
	var idle: float = brush.lift
	var high := _hang(scene, brush)
	Input.action_press("brush")
	for i in 2: ## a physics frame in which the head has seen the press: it has started to move
		await physics_frame
	var onset_down: float = brush.lift
	for i in 6: ## DOWN_TIME is six frames at 60 Hz
		await physics_frame
	var arrived: float = brush.lift
	for i in 30:
		await physics_frame
	var held: float = brush.lift
	var low := _hang(scene, brush)
	Input.action_release("brush")
	for i in 2:
		await physics_frame
	var onset_up: float = brush.lift
	for i in 30: ## UP_TIME is twelve frames
		await physics_frame
	var idle_again: float = brush.lift
	var up_again := _hang(scene, brush)
	_check("the head hangs until the brush is held", is_equal_approx(idle, BrushScript.LIFT) and onset_down < BrushScript.LIFT and arrived == 0.0 and held == 0.0
		and onset_up > 0.0 and is_equal_approx(idle_again, BrushScript.LIFT) and absf(high - low - BrushScript.LIFT) < 0.02 and absf(up_again - high) < 0.02
		and is_equal_approx(BrushScript.DOWN_TIME, 0.1) and is_equal_approx(BrushScript.UP_TIME, 0.2),
		"lift %.3f idle, %.3f in the frame of the press, %.3f DOWN_TIME later, %.3f held, %.3f in the frame of the release, %.3f idle again; the head's joint hangs %.3f m over the ground, %.3f held, %.3f idle again"
		% [idle, onset_down, arrived, held, onset_up, idle_again, high, low, up_again])
	await _drop(scene)

## A full pack does not lift the head (point 4, the answer to the lift of 2026-11-06): with the brush held the head still goes down to the ground, takes
## nothing because the pack has no room, and the puff stays off; with the brush let go it hangs as it always does. The control: with room in the pack the
## same walk takes dust and the puff is on.
func _a_full_pack_does_not_lift_the_head() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var brush: Node3D = player.brush
	var moon: Node = scene.get_node("Moon")
	player.global_position = Vector3(1.5, scene.get_node("Moon/Surface").height_at(1.5, 0.0) + 0.05, 0.0)
	player.camera.rotation.x = -0.3
	player.pack.add(player.pack.room())
	var full: bool = player.pack.is_full()
	Input.action_press("brush")
	for i in 40:
		await physics_frame
	var full_held: float = brush.lift
	var full_low := _hang(scene, brush)
	Input.action_release("brush")
	for i in 40:
		await physics_frame
	var full_idle := _hang(scene, brush)
	Input.action_press("brush")
	for i in 40:
		await physics_frame
	var before: int = moon.removed
	Input.action_press("move_forward", 1.0) ## a walk at the keys, 3.2 m/s: the puff is on with room in the pack
	var full_puff := false
	for i in 20:
		await physics_frame
		full_puff = full_puff or brush.puff.emitting
	var full_taken: int = moon.removed - before
	Input.action_release("move_forward")
	Input.action_release("brush")
	player.pack.take_all() ## the control: room in the pack, the same brush held and the same walk
	for i in 40:
		await physics_frame
	Input.action_press("brush")
	for i in 40:
		await physics_frame
	var room_held: float = brush.lift
	before = moon.removed
	Input.action_press("move_forward", 1.0)
	var room_puff := false
	for i in 20:
		await physics_frame
		room_puff = room_puff or brush.puff.emitting
	var room_taken: int = moon.removed - before
	Input.action_release("move_forward")
	Input.action_release("brush")
	_check("a full pack does not lift the head", full and full_held == 0.0 and room_held == 0.0 and absf(full_idle - full_low - BrushScript.LIFT) < 0.02
		and full_taken == 0 and not full_puff and room_taken > 0 and room_puff,
		"full pack, brush held: lift %.3f, the joint %.3f m over the ground, taken %d bytes, puff %s; let go: %.3f m; room, brush held: lift %.3f, taken %d bytes, puff %s"
		% [full_held, full_low, full_taken, full_puff, full_idle, room_held, room_taken, room_puff])
	await _drop(scene)

## A head that hangs over the ground takes nothing: with the brush pressed, no byte leaves the mask until the head is down (review of 2026-11-06: the stamp ran
## while the head still hung over the dust; point 4 of 2026-11-07 keeps the rule: `down` counts only when `lift` is back at zero).
func _a_head_in_the_air_takes_nothing() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var brush: Node3D = player.brush
	var moon: Node = scene.get_node("Moon")
	player.global_position = Vector3(1.5, scene.get_node("Moon/Surface").height_at(1.5, 0.0) + 0.05, 0.0)
	player.camera.rotation.x = -0.3
	for i in 40:
		await physics_frame
	var up: float = brush.lift
	Input.action_press("brush") ## the head comes down in DOWN_TIME, 0.1 s
	var before: int = moon.removed
	for i in 3: ## it is on its way: the head has seen the press in the second frame
		await physics_frame
	var in_the_air: float = brush.lift
	var taken_in_the_air: int = moon.removed - before
	for i in 60: ## and now it is down and works
		await physics_frame
	Input.action_release("brush")
	var taken_down: int = moon.removed - before - taken_in_the_air
	_check("a head in the air takes nothing", is_equal_approx(up, BrushScript.LIFT) and in_the_air > 0.0 and in_the_air < BrushScript.LIFT and taken_in_the_air == 0 and taken_down > 0,
		"lift %.3f idle, %.3f on its way down; taken in the air %d bytes, once down %d bytes" % [up, in_the_air, taken_in_the_air, taken_down])
	await _drop(scene)

## A tool's own animation (point 4, Daniel 2026-11-07: "wenn es eine hat einen animation abspielen für brush"): the Rotary Scrubber's scene carries an AnimationPlayer with an
## animation called brush, which plays while the tool is on the ground and brushing and pauses where it is when the brush is let go; the Brushbar has none and nothing breaks.
func _a_tool_plays_its_brush_animation_only_while_brushing() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var brush: Node3D = player.brush
	player.global_position = Vector3(1.5, scene.get_node("Moon/Surface").height_at(1.5, 0.0) + 0.05, 0.0)
	player.camera.rotation.x = -0.3
	var bar_has_none: bool = brush.animation == null
	Input.action_press("brush")
	for i in 20:
		await physics_frame
	Input.action_release("brush")
	brush.equip(load("res://models/rotary_scrubber.tscn") as PackedScene)
	for i in 40:
		await physics_frame
	var player_node: AnimationPlayer = brush.animation
	var idle_playing: bool = player_node != null and player_node.is_playing()
	Input.action_press("brush")
	for i in 3: ## on its way down: nothing plays yet
		await physics_frame
	var early_playing: bool = player_node.is_playing()
	for i in 30:
		await physics_frame
	var playing: bool = player_node.is_playing() and player_node.current_animation == "brush"
	var turned: float = (brush.head.get_node("Spinner") as Node3D).rotation.y
	var spun := absf(turned) > 0.0
	Input.action_release("brush")
	for i in 3:
		await physics_frame
	var paused_at: float = player_node.current_animation_position
	var stays_paused: bool = not player_node.is_playing()
	for i in 20:
		await physics_frame
	var kept: bool = is_equal_approx(player_node.current_animation_position, paused_at) and paused_at > 0.0
	var loops: bool = player_node.get_animation("brush").loop_mode == Animation.LOOP_LINEAR
	_check("a tool plays its brush animation only while brushing", bar_has_none and player_node != null and not idle_playing and not early_playing and playing and spun and stays_paused and kept and loops,
		"the Brushbar has none %s; the scrubber's: idle %s, on its way down %s, brushing %s (disc turned %.2f rad), let go: paused %s at %.2f s, kept %s, loops %s"
		% [bar_has_none, idle_playing, early_playing, playing, turned, stays_paused, paused_at, kept, loops])
	await _drop(scene)

## The ground log (tools/pilot.gd HeadProbe) leaves a head in the air out, which works nothing, but sees one that takes dust: dust gone from the mask since the last look
## puts the head in the log, and its gap over the ground fails the take (review of 2026-11-06: the probe returned null for any lift above 1 mm).
func _the_ground_log_sees_a_head_that_takes_dust_in_the_air() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var player: Node3D = scene.get_node("Player")
	var brush: Node3D = player.brush
	var moon: Node = scene.get_node("Moon")
	var probe: RefCounted = (load("res://tools/pilot.gd") as GDScript).HeadProbe.new()
	probe.brush = brush
	Input.action_press("brush")
	for i in 40:
		await physics_frame
	var down_first: Variant = probe.head ## on the ground, the first look
	Input.action_release("brush")
	for i in 40:
		await physics_frame
	var up_quiet: Variant = probe.head ## in the air, nothing taken
	var up_still: Variant = probe.head
	moon._count(50) ## dust leaves the mask while the head is in the air
	var up_took: Variant = probe.head
	var up_after: Variant = probe.head
	Input.action_press("brush")
	for i in 40:
		await physics_frame
	var down_again: Variant = probe.head
	Input.action_release("brush")
	_check("the ground log sees a head that takes dust in the air", down_first is Node3D and up_quiet == null and up_still == null and up_took is Node3D
		and up_after == null and down_again is Node3D, "down %s, up %s %s, taking %s, after %s, down again %s" % [down_first is Node3D, up_quiet, up_still, up_took is Node3D, up_after, down_again is Node3D])
	await _drop(scene)

## Steps 1 to 5 move the head the same way: the brush.gd of each has the two lines of point 4 (the brush action decides, not the pack) and the gate that lets a head in the air
## work nothing; step 5 alone plays the tool's animation.
func _every_step_hangs_the_head_the_same_way() -> void:
	var ok := true
	var seen: PackedStringArray = []
	for i in range(1, STEPS.size()):
		var code := FileAccess.get_file_as_string("res://steps/%s/brush.gd" % STEPS[i])
		var rule := code.contains("\trise = move_toward(rise, 0.0 if down else 1.0, delta / (DOWN_TIME if down else UP_TIME))\n") \
			and code.contains("\tlift = LIFT * smoothstep(0.0, 1.0, rise)\n") and code.contains("const DOWN_TIME := 0.1 ") and code.contains("const UP_TIME := 0.2 ") \
			and not code.contains("is_full() else") and not code.contains("LIFT_SPEED")
		var gate := code.contains("\tdown = down and lift == 0.0 ")
		var animates := code.contains("animation.play(\"brush\")") and code.contains("animation.pause()") and not code.contains("spinner")
		var right := rule and gate and (animates == (STEPS[i] == FINAL))
		ok = ok and right
		seen.append("%s %s" % [STEPS[i], "ok" if right else "WRONG"])
	_check("every step hangs the head the same way", ok, ", ".join(seen))

## How high the head's own node hangs over the ground under it.
func _hang(scene: Node, brush: Node3D) -> float:
	var at: Vector3 = (brush.head as Node3D).global_position
	return at.y - float(scene.get_node("Moon/Surface").height_at(at.x, at.z))

## The ground under a machine is level and bare rock: the height is the pad's everywhere under the footprint, no dust lies there, and the machine stands on it
## (the Dustwell stood 17.7 cm and the Tool Locker 11.9 cm in the ground before).
func _the_machines_stand_on_level_bare_ground() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var surface: Node3D = scene.get_node("Moon/Surface")
	var tile: RefCounted = scene.get_node("Moon").tile
	var worst := 0.0
	var dust := 0
	var at := 0
	for name_of_machine: String in ["Dustwell", "Locker"]:
		var machine: Node3D = scene.get_node(name_of_machine)
		var pad: Dictionary = surface.PADS[at]
		at += 1
		worst = maxf(worst, absf(machine.global_position.y - float(pad.y)))
		var x := float(pad.x) - float(pad.hx) + 0.2 ## the pad, less the margin the footprint keeps
		while x <= float(pad.x) + float(pad.hx) - 0.2:
			var z := float(pad.z) - float(pad.hz) + 0.2
			while z <= float(pad.z) + float(pad.hz) - 0.2:
				worst = maxf(worst, absf(surface.height_at(x, z) - float(pad.y)))
				var px := clampi(int((x + Tile.METRES / 2.0) / Tile.METRES * Tile.PIXELS), 0, Tile.PIXELS - 1)
				var pz := clampi(int((z + Tile.METRES / 2.0) / Tile.METRES * Tile.PIXELS), 0, Tile.PIXELS - 1)
				dust += int(tile.bytes[pz * Tile.PIXELS + px])
				z += 0.25
			x += 0.25
	_check("the machines stand on level bare ground", worst < 0.002 and dust == 0, "off the pad by %.4f m at most, %d bytes of dust under the footprints" % [worst, dust])
	await _drop(scene)

## The pads are bare from the start and not part of what there is to clean: stamping the whole tile reads CLEAN 100 % (review of 2026-11-06: it topped out
## at 98.8 % with the two pads of steps 4 and 5).
func _a_cleaned_tile_reads_a_hundred_percent() -> void:
	var scene := _final()
	root.add_child(scene)
	await physics_frame
	var moon: Node = scene.get_node("Moon")
	var bare: int = moon.bare
	var before: float = moon.clean_percent()
	moon.clean(Vector3.ZERO, Vector3.FORWARD, Vector2(Tile.METRES, Tile.METRES), false, Tile.FULL)
	var after: float = moon.clean_percent()
	_check("a cleaned tile reads 100 %", bare > 0 and before == 0.0 and absf(after - 100.0) < 0.001,
		"%d bytes bare under the pads, CLEAN %.3f %% at the start and %.3f %% with the whole tile stamped" % [bare, before, after])
	await _drop(scene)

func _drop(scene: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene.queue_free()
	await process_frame
	await process_frame

func _every_step_adds_its_files() -> void:
	for i in range(1, STEPS.size()):
		var step := STEPS[i]
		var before := DirAccess.open("res://steps/" + STEPS[i - 1]).get_files()
		var after := DirAccess.open("res://steps/" + step).get_files()
		var added: Array[String] = []
		for file in after:
			if file not in before and not file.ends_with(".uid"):
				added.append(file)
		added.sort()
		var wanted: Array = NEW_FILES[step].duplicate()
		wanted.sort()
		_check("%s adds %s" % [step, str(wanted)], str(added) == str(wanted), str(added))

func _every_step_loads() -> void:
	for step in STEPS:
		var scene: Node = (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
		root.add_child(scene)
		for i in 4:
			await physics_frame
		var player: Node = scene.get_node("Player")
		var ground: float = scene.get_node("Moon/Surface").height_at(0.0, 6.0)
		_check("%s loads" % step, player.camera != null and absf(ground) < 3.0, "ground=%.2f" % ground)
		await _drop(scene)

## The editor draws a yellow triangle on a Light3D whose scale is not 1 (godot-moon-01): the engine's own test on every light of every step.
func _no_light_shows_a_warning_triangle() -> void:
	for step in STEPS:
		var scene: Node = (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
		var lights := scene.find_children("*", "Light3D", true, false)
		var warned: Array[String] = []
		for light: Light3D in lights:
			if not light.scale.is_equal_approx(Vector3.ONE):
				warned.append("%s scale %s" % [scene.get_path_to(light), light.scale])
		_check("%s: no light shows a warning triangle" % step, not lights.is_empty() and warned.is_empty(), "%d light(s) %s" % [lights.size(), str(warned)])
		scene.free()

func _every_scene_is_on_jolt() -> void:
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine")
	_check("every scene is on Jolt", engine == "Jolt Physics", engine)
