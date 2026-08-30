class_name XpGem
extends Area3D
## XP gem dropped by enemies. Idles with a spin/bob, then homes to the
## player with accelerating speed once inside the magnet radius (scaled by
## RunState.pickup_radius_multiplier so pickup upgrades affect every gem).
## Collects on player contact -> RunState.add_xp. Despawns after lifetime
## if never magnetized, to keep long runs from littering the arena.

@export var xp_value: int = 1
@export var magnet_radius: float = 3.5
@export var magnet_acceleration: float = 45.0
@export var lifetime: float = 60.0
@export var spin_speed: float = 2.5
@export var bob_amplitude: float = 0.12

@onready var _visual: Node3D = $Visual

var _age: float = 0.0
var _visual_rest_y: float = 0.0
var _homing: bool = false
var _speed: float = 0.0
var _collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_rest_y = _visual.position.y


func _physics_process(delta: float) -> void:
	_age += delta
	_visual.rotate_y(spin_speed * delta)

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# Aim at chest height so gems don't burrow toward the feet.
	var target := player.global_position + Vector3.UP * 0.9

	if not _homing:
		_visual.position.y = _visual_rest_y + sin(_age * 3.0) * bob_amplitude
		var radius := magnet_radius * RunState.pickup_radius_multiplier
		if global_position.distance_squared_to(target) <= radius * radius:
			_homing = true  # sticky: keeps chasing even if the player outruns it
		elif _age > lifetime:
			queue_free()
		return

	_speed += magnet_acceleration * delta
	global_position = global_position.move_toward(target, _speed * delta)
	# Fallback for very fast final approach, where the one-physics-frame
	# overlap can slip past the area signal.
	if global_position.distance_squared_to(target) < 0.36:
		_collect()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	Sfx.play(&"gem_pickup")
	RunState.add_xp(xp_value)
	queue_free()
