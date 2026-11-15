extends CanvasLayer
## Three numbers: how much dust the brush has taken, how clean the tile is, and what the Dust Pack holds.

@export var moon: Node3D
@export var player: Node3D

@onready var dust: Label = $Panel/Dust
@onready var clean: Label = $Panel/Clean
@onready var in_pack: Label = $Panel/Pack

func _ready() -> void:
	moon.dust_changed.connect(_show)
	player.pack.changed.connect(_show)
	_show()

func _show() -> void:
	dust.text = "DUST  %.1f kg" % moon.kilograms()
	clean.text = "CLEAN  %.1f %%" % moon.clean_percent()
	in_pack.text = "PACK  %.1f / %.1f kg" % [player.pack.kilograms(), player.pack.capacity_kg]
