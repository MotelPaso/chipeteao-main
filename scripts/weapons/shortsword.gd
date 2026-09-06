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
	# Degenerate case (target directly above/below): swing where we face.
	var center_dir := flat_dir_or(target.global_position - global_position,
			-global_transform.basis.z)
	_hit_enemies_in_arc(center_dir)
	_play_swing(center_dir)


func _hit_enemies_in_arc(center_dir: Vector3) -> void:
	# Area tomes extend the swing's reach past the base targeting range.
	var reach := attack_range * area_scale()
	for body: Node3D in enemies_in_arc(global_position, center_dir, reach, arc_angle_deg):
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
