extends Resource
## One row of the Tool Locker, as data: its name, its price, and the tool it puts in your hand.
## The tool scene carries its own footprint, so a new tool is a new file here and no new code.

@export var title := ""
@export var price := 0
@export var tool: PackedScene
