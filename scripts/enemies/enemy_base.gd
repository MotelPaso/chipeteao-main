class_name EnemyBase
extends CharacterBody3D
## Shared enemy chassis (flat arena, no navmesh yet): gravity, seek-the-
## player steering with a light separation push from nearby enemies so
## hordes spread into a mob instead of stacking, facing, and the death flow
## via the Health child (kill credit, XP gem drop, squash-out tween).
## Subclasses shape behavior through the virtual hooks below.
## make_elite() upgrades any enemy into a glowing elite variant.

@export var move_speed: float = 4.0
@export var turn_speed: float = 10.0
@export var separation_radius: float = 1.2
@export var separation_strength: float = 1.5
@export var xp_gem_scene: PackedScene
@export_group("Elite")
@export var elite_hp_multiplier: float = 3.0
@export var elite_speed_multiplier: float = 1.3
@export var elite_damage_multiplier: float = 1.5
@export var elite_body_scale: float = 1.35
@export var elite_xp_multiplier: int = 5

var is_elite: bool = false

@onready var _health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _xp_multiplier: int = 1
## Map-tier XP gem value factor (see apply_tier_scaling); 1.0 = baseline.
var _tier_xp_multiplier: float = 1.0
# Timed slow (Thorn Whip etc.): a speed multiplier active while the timer
# runs; expiry restores full speed. See apply_slow for the refresh rules.
var _slow_multiplier: float = 1.0
var _slow_time_left: float = 0.0


func _ready() -> void:
	_health.died.connect(_on_died)
	_health.damaged.connect(_on_damaged_flash)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_slow_time_left = maxf(_slow_time_left - delta, 0.0)
	_behavior_tick(delta)

	var steer := Vector3.ZERO
	var seek := Vector3.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 0.001:
			seek = to_player / distance
		steer = _movement_intent(seek, distance)
		_combat_tick(player, distance)

	steer += _separation_push() * separation_strength
	steer.y = 0.0
	if steer.length_squared() > 1.0:
		steer = steer.normalized()
	var slowed_speed := move_speed * active_slow_multiplier()
	velocity.x = steer.x * slowed_speed
	velocity.z = steer.z * slowed_speed

	var face := _facing_direction(steer, seek)
	if face.length_squared() > 0.0001:
		# Face the chosen direction (-Z forward).
		var target_yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

	move_and_slide()


## Virtual: per-frame housekeeping (attack cooldowns etc.) before steering.
func _behavior_tick(_delta: float) -> void:
	pass


## Virtual: where to steer given the flat unit direction to the player and
## the flat distance. Default chases straight in.
func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	return seek


## Virtual: attack opportunity for this frame; distance is flat.
func _combat_tick(_player: Node3D, _distance: float) -> void:
	pass


## Virtual: direction the body turns toward. Default faces its steering.
func _facing_direction(steer: Vector3, _seek: Vector3) -> Vector3:
	return steer


## Virtual: scale whatever damage number(s) the subclass owns; called once
## by make_elite().
func _apply_elite_damage(_multiplier: float) -> void:
	pass


## Applies a timed slow: this enemy moves at speed_multiplier of its normal
## speed for `duration` seconds. Re-application REFRESHES (overwrites both
## strength and timer) rather than stacking, so repeated whip lashes can
## never compound a slow toward zero.
func apply_slow(speed_multiplier: float, duration: float) -> void:
	if duration <= 0.0:
		return
	_slow_multiplier = clampf(speed_multiplier, 0.05, 1.0)
	_slow_time_left = duration


## Current external speed multiplier: 1.0 whenever no slow is active.
func active_slow_multiplier() -> float:
	return _slow_multiplier if _slow_time_left > 0.0 else 1.0


## Map-tier difficulty hook (GDD 6/7), applied by the spawner right after
## a spawn: multiplies max HP (healed to the new max), attack damage
## (through the same virtual elites use), and the XP gem payout. Distinct
## from make_elite() and stacks multiplicatively with it in either order.
## Every factor at 1.0 (tier 1) is an exact no-op. Call after the enemy is
## inside the tree (relies on the onready Health child).
func apply_tier_scaling(hp_mult: float, dmg_mult: float, xp_value_mult: float = 1.0) -> void:
	if hp_mult != 1.0:
		_health.max_hp *= hp_mult
		_health.heal_full()
	if dmg_mult != 1.0:
		_apply_elite_damage(dmg_mult)
	_tier_xp_multiplier = xp_value_mult


## Promotes this enemy to an elite: more HP (healed to the new max), speed,
## damage, and XP, bigger body, and an emissive glow overlay. Call after
## the enemy is inside the tree (relies on onready children). Idempotent.
func make_elite() -> void:
	if is_elite:
		return
	is_elite = true
	_health.max_hp *= elite_hp_multiplier
	_health.heal_full()
	move_speed *= elite_speed_multiplier
	_apply_elite_damage(elite_damage_multiplier)
	_xp_multiplier = elite_xp_multiplier
	scale *= elite_body_scale
	_apply_elite_glow()


## Self-illuminated tint over every mesh in the visual rig so elites read
## at a glance even inside a horde.
func _apply_elite_glow() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1.0, 0.62, 0.12, 0.3)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.1)
	glow.emission_energy_multiplier = 1.8
	for node: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_overlay = glow


func _on_damaged_flash(_amount: float, _current: float) -> void:
	Juice.flash(_visual)


## Virtual: death juice (tiny shake + shard burst tinted like the body);
## the boss overrides this with its bigger moment.
func _death_feedback() -> void:
	Juice.enemy_died(global_position + Vector3.UP * 0.8, death_burst_color())


## Tint for this enemy's death burst: the first visual mesh's albedo, so
## the shards read as pieces of the body. Elites keep their base skin color
## (the glow is an overlay, which get_active_material ignores).
func death_burst_color() -> Color:
	for node: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null \
				or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var material := mesh_instance.get_active_material(0) as StandardMaterial3D
		if material != null:
			return material.albedo_color
	return Color(0.75, 0.75, 0.78)


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
	_death_feedback()
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
	var drop := xp_gem_scene.instantiate()
	var gem := drop as XpGem
	if gem == null:
		drop.free()
		return
	# Elite factor first (int), then the map-tier value factor (min 1 XP);
	# both 1 on a baseline spawn, leaving the scene value untouched.
	gem.xp_value = maxi(roundi(float(gem.xp_value * _xp_multiplier) * _tier_xp_multiplier), 1)
	# Parented to the scene root, not this enemy, so it outlives the corpse.
	get_tree().current_scene.add_child(gem)
	gem.global_position = global_position + Vector3.UP * 0.6
