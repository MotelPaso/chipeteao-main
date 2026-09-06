extends WeaponBase
## Otto's starting weapon: hurls a spinning blade that flies out along the
## aim line, then swings back to the player, cutting everything it passes
## in both directions (BoomerangProjectile owns the out-and-back flight).

@export var projectile_scene: PackedScene
## Multiplier on how far the blade flies before turning back ("Far Flight"
## raises it; area tomes stretch the sweep too).
@export var travel_scale: float = 1.0
## Height above this mount the blade is thrown from.
@export var throw_height: float = 0.0

## Seconds between the blades a Tome of Multitude adds. Thrown one after
## the other, never together: blades launched from the same hand on the
## same frame fly the same line out and back, so only the first one ever
## touches anything.
const EXTRA_THROW_STAGGER: float = 0.11
## Yaw between neighboring blades, so each extra sweeps its own corridor.
const EXTRA_THROW_FAN_DEG: float = 20.0
## The whole staggered chain has to end inside this fraction of one
## cooldown, or a volley would still be leaving the hand at the next throw.
const THROW_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Degenerate case (target directly above/below): throw where we face, and
	# FORWARD when our own facing is vertical too.
	var center_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_THROW_STAGGER,
			effective_cooldown() * THROW_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_THROW_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		var throw_dir := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			_throw_blade(throw_dir)
		else:
			# Pausable and stepped in physics: an extra blade must not leave
			# while the upgrade UI holds the tree, and the throw belongs on
			# the same tick the rest of the combat runs on.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_throw_blade.bind(throw_dir))


## Hurls one blade along `throw_dir`. The staggered extras land here a beat
## later, when this weapon may already have left the tree with a removed
## raider — and a blade thrown from outside the tree has no position to
## start from (nor a player to come home to).
func _throw_blade(throw_dir: Vector3) -> void:
	if not is_inside_tree():
		return
	# Pooled, parented to the scene root so the blade keeps flying while
	# the player moves on.
	var blade := Pools.acquire_scene(projectile_scene) as BoomerangProjectile
	if blade == null:
		return
	blade.launch(self, global_position + Vector3.UP * throw_height, throw_dir,
			attack_range * travel_scale * area_scale())
