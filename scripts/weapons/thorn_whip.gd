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
	# Degenerate case (target directly above/below): lash where we face, and
	# FORWARD when our own facing is vertical too.
	var lash_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	var length := attack_range * area_scale()
	_lash_strip(lash_dir, length)
	_spawn_crack_visual(lash_dir, length)


## Hits every enemy whose flat position falls inside the strip: within
## `length` along lash_dir and half the (area-scaled) width off its axis.
func _lash_strip(lash_dir: Vector3, length: float) -> void:
	var half_width := strip_width * 0.5 * area_scale()
	var slow_mult := 1.0 - clampf(slow_percent, 0.0, 95.0) / 100.0
	for body: Node3D in enemies_in_lane(global_position, lash_dir, length, half_width):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		# No slowing corpses: the lash that killed this body must not leave
		# a slow behind on it (see the same guard in stench.gd).
		if enemy != null and (health == null or not health.is_dead):
			enemy.apply_slow(slow_mult, slow_duration * duration_scale())


func _spawn_crack_visual(lash_dir: Vector3, length: float) -> void:
	# Pooled, scene-root parented so the crack stays put while the player
	# moves on.
	var crack := Pools.acquire_scene(Pools.WHIP_CRACK_SCENE) as WhipCrack
	if crack == null:
		return
	crack.play(global_position + Vector3.UP * 0.9, lash_dir, length, crack_color)
