extends WeaponBase
## Rook's starting weapon: sweeps a melee arc toward the nearest enemy and
## damages every "enemies"-group body inside it. No held model — the
## attack reads through a pooled crescent SlashArc swipe flashed through
## the hit arc, plus a small spark burst on each enemy struck.

@export var arc_angle_deg: float = 150.0
@export var swing_time: float = 0.25
## Slash swipe tint (steel-blue, matching the old blade's emission).
@export var slash_color: Color = Color(0.75, 0.85, 1.0)
## Spark tint for per-enemy hit bursts.
@export var spark_color: Color = Color(0.7, 0.8, 1.0)


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
			# Tiny spark burst where the blade "connects".
			Juice.burst(body.global_position + Vector3.UP * 0.6, spark_color, 4)


func _play_swing(center_dir: Vector3) -> void:
	var slash := Pools.acquire_scene(Pools.SLASH_ARC_SCENE) as SlashArc
	if slash == null:
		return
	slash.play(global_position, center_dir, attack_range * area_scale() * 0.9,
			slash_color, arc_angle_deg * 0.8, swing_time)
