extends WeaponBase
## Rook's starting weapon: sweeps a melee arc toward the nearest enemy and
## damages every "enemies"-group body inside it, with a placeholder blade
## swipe (Tween on SwingPivot) as the visual.

@export var arc_angle_deg: float = 150.0
@export var swing_time: float = 0.25

@onready var _swing_pivot: Node3D = $SwingPivot

var _swing_tween: Tween


func fire(target: Node3D) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	# Degenerate case (target directly above/below): swing where we face.
	var center_dir := to_target.normalized() if to_target.length_squared() > 0.0001 \
			else -global_transform.basis.z
	_hit_enemies_in_arc(center_dir)
	_play_swing(center_dir)


func _hit_enemies_in_arc(center_dir: Vector3) -> void:
	var half_arc := deg_to_rad(arc_angle_deg * 0.5)
	# Area tomes extend the swing's reach past the base targeting range.
	var reach := attack_range * area_scale()
	var range_sq := reach * reach
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if global_position.distance_squared_to(body.global_position) > range_sq:
			continue
		var to_enemy := body.global_position - global_position
		to_enemy.y = 0.0
		# Bodies right on top of us count as inside the arc.
		if to_enemy.length_squared() > 0.0001 \
				and center_dir.angle_to(to_enemy) > half_arc:
			continue
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)


func _play_swing(center_dir: Vector3) -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	# Aim the pivot at the target, then sweep across the full arc.
	_swing_pivot.look_at(_swing_pivot.global_position + center_dir, Vector3.UP)
	var half_arc := deg_to_rad(arc_angle_deg * 0.5)
	_swing_pivot.rotation.y += half_arc
	_swing_pivot.visible = true
	_swing_tween = create_tween()
	_swing_tween.tween_property(_swing_pivot, "rotation:y",
			_swing_pivot.rotation.y - half_arc * 2.0, swing_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_callback(func() -> void: _swing_pivot.visible = false)
