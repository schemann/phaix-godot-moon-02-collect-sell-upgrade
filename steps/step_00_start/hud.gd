extends CanvasLayer
## Two numbers: how much dust the brush has taken, and how clean the tile is.

@export var moon: Node3D

@onready var dust: Label = $Panel/Dust
@onready var clean: Label = $Panel/Clean

func _ready() -> void:
	moon.dust_changed.connect(_show)
	_show()

func _show() -> void:
	dust.text = "DUST  %.1f kg" % moon.kilograms()
	clean.text = "CLEAN  %.1f %%" % moon.clean_percent()
