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

## Seconds between the swings a Tome of Multitude adds. Extra swings are
## staggered instead of simultaneous: two arcs cast from the same shoulder
## in the same frame are one arc that happens to hit twice.
const EXTRA_SWING_STAGGER: float = 0.09
## Yaw between neighboring swings, so the extras carve their own ground
## instead of retracing the first one.
const EXTRA_SWING_FAN_DEG: float = 25.0
## The whole staggered chain has to end inside this fraction of one
## cooldown, or a long volley would still be swinging when the next one
## starts and the combo would read as a single smear.
const SWING_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	# Degenerate case (target directly above/below): swing where we face.
	var center_dir := flat_dir_or(target.global_position - global_position,
			-global_transform.basis.z)
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_SWING_STAGGER,
			effective_cooldown() * SWING_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_SWING_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		var swing_dir := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			_swing(swing_dir)
		else:
			# Pausable and stepped in physics: an extra swing must not land
			# while the upgrade UI holds the tree, and damage belongs on the
			# same tick the rest of the combat runs on.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_swing.bind(swing_dir))


## One full swing: the hit pass plus its crescent. The staggered extras land
## here a beat later, when this weapon may already have left the tree with
## a removed raider.
func _swing(center_dir: Vector3) -> void:
	if not is_inside_tree():
		return
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
