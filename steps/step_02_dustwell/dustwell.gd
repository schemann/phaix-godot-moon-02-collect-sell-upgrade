extends Node3D
## The Dustwell: walk up to it, press E, and the Dust Pack empties into it. It keeps the dust, and its gauge shows how full it is.

const DustPack := preload("dust_pack.gd")
const GAUGE_KG := 10.0 ## The kilograms that fill the gauge on the front to the top.

@onready var gauge: Node3D = $Dustwell/Fill

var stored := 0 ## Bytes of dust inside: exactly the bytes the pack held.

func _ready() -> void:
	add_to_group("stations")
	_show()

## What E does here, for the HUD.
func prompt(player: Node3D) -> String:
	return "E  Empty the Dust Pack" if player.pack.bytes > 0 else "The Dust Pack is empty"

## E: the whole pack goes in.
func use(player: Node3D) -> void:
	stored += player.pack.take_all()
	_show()

func kilograms() -> float:
	return stored / float(DustPack.BYTES_PER_KG)

func _show() -> void:
	gauge.scale.y = clampf(kilograms() / GAUGE_KG, 0.001, 1.0)
