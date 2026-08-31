class_name Projectile
extends Area3D
## Weapon bullet: flies along -Z (bending lightly toward the target it was
## fired at) and damages "enemies"-group bodies it overlaps — each body at
## most once — until its pierce budget runs out (1 = classic dart).
## The firing weapon acquires it from Pools (parented to the scene root so
## it survives player movement); it releases back on hit-out or after
## max_distance, and pool_reset() re-arms pierce/hit-set/tracer for reuse.

@export var speed: float = 26.0
## Whether the flight bends toward the target at all (arrows fly straight).
@export var homing_enabled: bool = true
## Radians/sec the flight direction may bend toward the target; 0 disables homing.
@export var homing_turn_speed: float = 3.5
## How many distinct enemies this projectile may damage before despawning.
## The firing weapon can raise it per shot (Hunting Bow pierce upgrades).
@export var pierce_remaining: int = 1
## Aim above the target's origin so bullets converge on body height, not feet.
@export var aim_height: float = 0.8
## Tracer spawns stretched along its length and relaxes to 1 (cheap trail feel).
@export var spawn_stretch: float = 2.4

@onready var _tracer: MeshInstance3D = $Tracer

var _source: WeaponBase = null
var _max_distance: float = 20.0
var _travelled: float = 0.0
var _target: Node3D = null
## Instance ids already damaged, so a body re-entering (or hugging) the
## hitbox of a piercing shot is never hit twice by the same projectile.
var _hit_ids: Dictionary[int, bool] = {}
## Scene-default pierce budget, restored on reuse (the bow overrides it
## per shot AFTER the pool's reset).
var _default_pierce: int = 1
var _stretch_tween: Tween = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_default_pierce = pierce_remaining


## Pooled-node contract: fresh flight state and the tracer stretch replay.
func pool_reset() -> void:
	_source = null
	_target = null
	_max_distance = 20.0
	_travelled = 0.0
	_hit_ids.clear()
	pierce_remaining = _default_pierce
	_tracer.scale = Vector3(1.0, 1.0, spawn_stretch)
	if _stretch_tween != null and _stretch_tween.is_valid():
		_stretch_tween.kill()
	_stretch_tween = create_tween()
	_stretch_tween.tween_property(_tracer, "scale", Vector3.ONE, 0.12)


## Called by the firing weapon right after spawning and orienting the
## bullet. Damage is resolved at impact through the weapon's shared
## deal_damage funnel so global stats (crit, lifesteal) apply.
func launch(source: WeaponBase, max_distance: float, target: Node3D) -> void:
	_source = source
	_max_distance = max_distance
	_target = target


func _physics_process(delta: float) -> void:
	if _homing_active():
		_steer_toward_target(delta)
	var step := speed * delta
	global_position += -global_transform.basis.z * step
	_travelled += step
	if _travelled >= _max_distance:
		Pools.release(self)


func _steer_toward_target(delta: float) -> void:
	var to_target := _target.global_position + Vector3.UP * aim_height - global_position
	if to_target.length_squared() < 0.0001:
		return
	var forward := -global_transform.basis.z
	var desired := to_target.normalized()
	var angle := forward.angle_to(desired)
	if angle < 0.001:
		return
	var axis := forward.cross(desired)
	# Parallel/anti-parallel directions have no rotation axis; fly straight.
	if axis.length_squared() < 0.000001:
		return
	var new_forward := forward.rotated(axis.normalized(), minf(angle, homing_turn_speed * delta))
	# Near-vertical flight (homing over/under a target from a ledge) is
	# colinear with UP; a sideways up vector keeps the basis buildable.
	var up := Vector3.UP if absf(new_forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	look_at(global_position + new_forward, up)


func _homing_active() -> bool:
	# A dying enemy leaves the "enemies" group; the bullet stops chasing the
	# corpse and just flies out its remaining range.
	return homing_enabled and homing_turn_speed > 0.0 and _target != null \
			and is_instance_valid(_target) and _target.is_inside_tree() \
			and _target.is_in_group("enemies")


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemies"):
		return
	var body_id := body.get_instance_id()
	if _hit_ids.has(body_id):
		return
	_hit_ids[body_id] = true
	var health := Health.find_in(body)
	# A dart whose weapon was freed mid-flight fizzles (cannot happen with
	# the current no-weapon-removal rules; belt and braces).
	if health != null and _source != null and is_instance_valid(_source):
		_source.deal_damage(health)
	pierce_remaining -= 1
	if pierce_remaining <= 0:
		Pools.release(self)
