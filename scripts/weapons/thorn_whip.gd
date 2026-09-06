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

## Seconds between the lashes a Tome of Multitude adds. One coil cannot be
## in two places at once, so the extras crack one after the other.
const EXTRA_LASH_STAGGER: float = 0.09
## Yaw between neighboring lashes: the strip is narrow, so a small fan is
## enough for each extra to sweep its own lane.
const EXTRA_LASH_FAN_DEG: float = 18.0
## The whole staggered chain has to end inside this fraction of one
## cooldown, or the tail of one volley would overlap the next.
const LASH_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	# Degenerate case (target directly above/below): lash where we face, and
	# FORWARD when our own facing is vertical too.
	var center_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	var length := attack_range * area_scale()
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_LASH_STAGGER,
			effective_cooldown() * LASH_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_LASH_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		var lash_dir := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			_lash(lash_dir, length)
		else:
			# Pausable and stepped in physics: an extra lash must not land
			# while the upgrade UI holds the tree, and damage belongs on the
			# same tick the rest of the combat runs on.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_lash.bind(lash_dir, length))


## One crack of the lash: the hit pass plus its visual. The staggered extras
## land here a beat later, when this weapon may already have left the tree
## with a removed raider.
func _lash(lash_dir: Vector3, length: float) -> void:
	if not is_inside_tree():
		return
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
