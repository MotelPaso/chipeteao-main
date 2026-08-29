extends CharacterBody3D
## Melee grunt: seeks the player in a straight line (flat arena, no navmesh
## yet) with a light separation push from nearby enemies so hordes spread
## into a mob instead of stacking. Damages the player on contact, on a
## cooldown. Dies via its Health child with a quick squash-out tween.

@export var move_speed: float = 4.0
@export var turn_speed: float = 10.0
@export var contact_damage: float = 5.0
@export var attack_cooldown: float = 0.8
@export var attack_range: float = 1.3
@export var separation_radius: float = 1.2
@export var separation_strength: float = 1.5
@export var xp_gem_scene: PackedScene

@onready var _health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _attack_timer: float = 0.0


func _ready() -> void:
	_health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	var steer := Vector3.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 0.001:
			steer = to_player / distance
		_try_attack(player, distance)

	steer += _separation_push() * separation_strength
	steer.y = 0.0
	if steer.length_squared() > 1.0:
		steer = steer.normalized()
	velocity.x = steer.x * move_speed
	velocity.z = steer.z * move_speed

	if steer.length_squared() > 0.0001:
		# Face movement direction (-Z forward).
		var target_yaw := atan2(-steer.x, -steer.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

	move_and_slide()


func _try_attack(player: Node3D, distance: float) -> void:
	if _attack_timer > 0.0 or distance > attack_range:
		return
	# Height gate: a player on a ledge above is out of melee reach.
	if absf(player.global_position.y - global_position.y) > 1.6:
		return
	var player_health := Health.find_in(player)
	if player_health == null or player_health.is_dead:
		return
	_attack_timer = attack_cooldown
	player_health.take_damage(contact_damage)


## Sums push-away vectors from living "enemies" within separation_radius,
## with falloff (strongest when overlapping, zero at the edge). O(n^2) over
## the horde, fine at the spawner's cap on a flat arena.
func _separation_push() -> Vector3:
	var push := Vector3.ZERO
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var other := enemy as Node3D
		if other == null or other == self or not other.is_inside_tree():
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var dist := away.length()
		if dist >= separation_radius:
			continue
		if dist < 0.01:
			# Perfectly stacked bodies: nudge apart in a stable per-instance direction.
			away = Vector3.RIGHT.rotated(Vector3.UP, float(get_instance_id() % 64) * TAU / 64.0)
			dist = 0.01
		push += (away / dist) * (1.0 - dist / separation_radius)
	return push


func _on_died() -> void:
	# Leave the group first so weapons and separation ignore the corpse.
	remove_from_group("enemies")
	set_physics_process(false)
	_collision.set_deferred("disabled", true)
	RunState.add_kill()
	_drop_xp_gem()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "rotation:x", -TAU * 0.25, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.05, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _drop_xp_gem() -> void:
	if xp_gem_scene == null:
		return
	var gem := xp_gem_scene.instantiate() as Node3D
	# Parented to the scene root, not this grunt, so it outlives the corpse.
	get_tree().current_scene.add_child(gem)
	gem.global_position = global_position + Vector3.UP * 0.6
