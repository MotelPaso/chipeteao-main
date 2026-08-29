class_name Projectile
extends Area3D
## Weapon bullet: flies along -Z (bending lightly toward the target it was
## fired at) and damages the first "enemies"-group body it overlaps.
## The firing weapon parents it to the scene root so it survives player
## movement; it despawns on hit or after max_distance so strays never linger.

@export var speed: float = 26.0
## Radians/sec the flight direction may bend toward the target; 0 disables homing.
@export var homing_turn_speed: float = 3.5
## Aim above the target's origin so bullets converge on body height, not feet.
@export var aim_height: float = 0.8
## Tracer spawns stretched along its length and relaxes to 1 (cheap trail feel).
@export var spawn_stretch: float = 2.4

@onready var _tracer: MeshInstance3D = $Tracer

var _source: WeaponBase = null
var _max_distance: float = 20.0
var _travelled: float = 0.0
var _target: Node3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_tracer.scale = Vector3(1.0, 1.0, spawn_stretch)
	var tween := create_tween()
	tween.tween_property(_tracer, "scale", Vector3.ONE, 0.12)


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
		queue_free()


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
	look_at(global_position + new_forward, Vector3.UP)


func _homing_active() -> bool:
	# A dying enemy leaves the "enemies" group; the bullet stops chasing the
	# corpse and just flies out its remaining range.
	return homing_turn_speed > 0.0 and _target != null and is_instance_valid(_target) \
			and _target.is_inside_tree() and _target.is_in_group("enemies")


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemies"):
		return
	var health := Health.find_in(body)
	# A dart whose weapon was freed mid-flight fizzles (cannot happen with
	# the current no-weapon-removal rules; belt and braces).
	if health != null and _source != null and is_instance_valid(_source):
		_source.deal_damage(health)
	queue_free()
