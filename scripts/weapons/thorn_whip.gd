extends WeaponBase
## Bramble's starting weapon: cracks a thorned lash along a narrow strip
## from the wielder toward the target, damaging every "enemies"-group body
## inside it and briefly slowing the EnemyBase ones (refresh, not stack —
## see EnemyBase.apply_slow). No held model — the crack reads through a
## pooled WhipCrack: a tapering green strip that whips out along the lane
## and snaps back, spraying thorn particles.

## Full width of the lash strip; the strip's length is attack_range. Both
## scale with area tomes.
@export var strip_width: float = 1.2
## Percent of move speed removed from lashed enemies (30 = they keep 70%).
@export var slow_percent: float = 30.0
@export var slow_duration: float = 1.5
## Whip strip tint (verdant, matching the old coil's emission).
@export var crack_color: Color = Color(0.5, 0.85, 0.3)


func fire(target: Node3D) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	# Degenerate case (target directly above/below): lash where we face.
	var lash_dir := to_target.normalized() if to_target.length_squared() > 0.0001 \
			else -global_transform.basis.z
	lash_dir.y = 0.0
	lash_dir = lash_dir.normalized() if lash_dir.length_squared() > 0.0001 else Vector3.FORWARD
	var length := attack_range * area_scale()
	_lash_strip(lash_dir, length)
	_spawn_crack_visual(lash_dir, length)


## Hits every enemy whose flat position falls inside the strip: within
## `length` along lash_dir and half the (area-scaled) width off its axis.
func _lash_strip(lash_dir: Vector3, length: float) -> void:
	var half_width := strip_width * 0.5 * area_scale()
	var slow_mult := 1.0 - clampf(slow_percent, 0.0, 95.0) / 100.0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_enemy := body.global_position - global_position
		to_enemy.y = 0.0
		var along := to_enemy.dot(lash_dir)
		if along < 0.0 or along > length:
			continue
		if (to_enemy - lash_dir * along).length() > half_width:
			continue
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		if enemy != null:
			enemy.apply_slow(slow_mult, slow_duration)


func _spawn_crack_visual(lash_dir: Vector3, length: float) -> void:
	# Pooled, scene-root parented so the crack stays put while the player
	# moves on.
	var crack := Pools.acquire_scene(Pools.WHIP_CRACK_SCENE) as WhipCrack
	if crack == null:
		return
	crack.play(global_position + Vector3.UP * 0.9, lash_dir, length, crack_color)
