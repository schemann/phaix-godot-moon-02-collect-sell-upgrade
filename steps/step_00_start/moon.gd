extends Node3D
## The moon of this tutorial: one surface, one dust tile, and the count of what was cleaned. The brush talks to it, the HUD listens.

signal dust_changed

const DustTile := preload("dust_tile.gd")
const GRAMS_PER_FULL_PIXEL := 1.0

@onready var surface: Node3D = $Surface
@onready var stones: GeometryInstance3D = $Rocks

var tile: RefCounted = DustTile.new()
var removed := 0 ## Bytes taken from the mask so far.
var _dirty := false

func _ready() -> void:
	surface.material.set_shader_parameter("dust_mask", tile.texture)
	## The stones read the same mask, so their shader lifts them as high as the dust under them.
	stones.material_override.set_shader_parameter("dust_mask", tile.texture)

## One stamp of the tool's head where the brush is.
func clean(point: Vector3, heading: Vector3, size: Vector2, round_head: bool, amount: int) -> void:
	_count(tile.stamp(point, heading, size, round_head, amount))

## A stroke from one point to another: stamps along the line, half the head's shorter side apart, so that a fast hand leaves no gaps.
## Each stamp knows where the one before it stood and takes only the ground that one did not cover, so a pass takes `amount` once.
func sweep(from: Vector3, to: Vector3, heading: Vector3, size: Vector2, round_head: bool, amount: int) -> void:
	var stamps := ceili(from.distance_to(to) / (minf(size.x, size.y) * 0.5))
	var taken := 0
	for i in range(1, stamps + 1):
		var before := from.lerp(to, float(i - 1) / stamps)
		taken += tile.stamp(from.lerp(to, float(i) / stamps), heading, size, round_head, amount, before)
	_count(taken)

## What the stamps took goes to removed, and the HUD hears of it, only when anything left the mask.
func _count(taken: int) -> void:
	if taken > 0:
		removed += taken
		_dirty = true
		dust_changed.emit()

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		tile.upload()

func kilograms() -> float:
	return removed / float(DustTile.FULL) * GRAMS_PER_FULL_PIXEL / 1000.0

func clean_percent() -> float:
	return 100.0 * removed / float(DustTile.PIXELS * DustTile.PIXELS * DustTile.FULL)
