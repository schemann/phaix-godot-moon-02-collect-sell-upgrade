extends Node3D
## The tool in the player's hand. A ray from the camera finds the ground, the tool's head lands there, and the brush action cleans.
## The model is a scene of its own: any rigid scene with a node called Head on its local Z axis and its head's footprint fits, and the code does not change.

const REACH := 2.3 ## Metres from the camera to the farthest ground the head can land on.
const AMOUNT := 255 ## What one stamp takes from every point under the head.
const HAND := Vector3(0.32, 1.05, -0.1) ## The hand at the hip, low on the right, in the player's space.
const JOINT := 0.3 ## Metres from the ground up to the joint on top of the head, where the pole ends.
const RUSTLES: Array[AudioStream] = [preload("res://sounds/cloth1.ogg"), preload("res://sounds/cloth2.ogg"),
	preload("res://sounds/cloth3.ogg"), preload("res://sounds/cloth4.ogg")] ## Four cloth rustles, played in turn.
const QUIET := 0.12 ## Seconds of quiet between two rustles.

@onready var moon: Node3D = owner.moon
@onready var camera: Camera3D = get_parent()
@onready var model: Node3D = $Model
@onready var head: Node3D = $Model/Head
## The tool's imprint: its head seen from above, metres across and along the pole. The tool scene carries it, so a bigger tool clears more.
@onready var footprint: Vector2 = model.get_meta("footprint")
@onready var round_head: bool = model.get_meta("round", false)
@onready var puff: GPUParticles3D = $Puff
@onready var sound: AudioStreamPlayer = $Sound

var _last := Vector3.ZERO
var _was_down := false
var _rustle := 0 ## The rustle that plays next.
var _wait := 0.0 ## Seconds until it starts.

func _physics_process(delta: float) -> void:
	var point := aim()
	var down := Input.is_action_pressed("brush")
	_pose(point + Vector3.UP * JOINT)
	var speed := point.distance_to(_last) / delta if down and _was_down else 0.0
	puff.global_position = point
	puff.emitting = speed > 0.3
	sound.volume_db = linear_to_db(clampf(speed / 3.0, 0.001, 1.0))
	if down:
		_wait -= delta
		if _wait <= 0.0:
			sound.stream = RUSTLES[_rustle]
			sound.play()
			_wait = sound.stream.get_length() + QUIET
			_rustle = (_rustle + 1) % RUSTLES.size()
		var heading := head.global_basis.z
		if _was_down:
			moon.sweep(_last, point, heading, footprint, round_head, AMOUNT)
		else:
			moon.clean(point, heading, footprint, round_head, AMOUNT)
		_last = point
	else:
		sound.stop()
		_wait = 0.0
	_was_down = down

## Where the view meets the ground. A view above the ground lands the head about as far out as the ray reaches.
func aim() -> Vector3:
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var ray := PhysicsRayQueryParameters3D.create(from, from + forward * REACH, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit:
		return hit.position
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var point := from + flat * REACH * 0.85
	point.y = moon.surface.height_at(point.x, point.z)
	return point

## The pole runs through the hand towards the point, the head lies flat on the ground, also on a slope.
func _pose(point: Vector3) -> void:
	var hand: Vector3 = owner.to_global(HAND)
	var along := hand.direction_to(point)
	model.global_basis = Basis.looking_at(along, Vector3.UP, true)
	model.global_position = point - along * head.position.z
	var ground: Vector3 = moon.surface.normal_at(point.x, point.z)
	head.global_basis = Basis.looking_at(along.slide(ground).normalized(), ground, true)
