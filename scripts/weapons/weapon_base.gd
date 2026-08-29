class_name WeaponBase
extends Node3D
## Base for auto-firing weapons: ticks a cooldown and calls fire() at the
## nearest body in the "enemies" group within attack_range.
## Subclasses override fire() with their attack behavior.

@export var damage: float = 10.0
@export var cooldown: float = 1.0
@export var attack_range: float = 3.0
@export var projectile_count: int = 1

var _cooldown_left: float = 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _cooldown_left > 0.0:
		return
	var target := acquire_target()
	if target == null:
		return
	_cooldown_left = cooldown
	fire(target)


## Nearest body in the "enemies" group within attack_range, or null.
func acquire_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist_sq := attack_range * attack_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var dist_sq := global_position.distance_squared_to(body.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = body
	return nearest


## Virtual: perform the attack against the acquired target.
func fire(_target: Node3D) -> void:
	push_warning("%s: fire() not implemented" % name)
