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


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Degenerate case (target directly above/below): throw where we face, and
	# FORWARD when our own facing is vertical too.
	var throw_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	# Pooled, parented to the scene root so the blade keeps flying while
	# the player moves on.
	var blade := Pools.acquire_scene(projectile_scene) as BoomerangProjectile
	if blade == null:
		return
	blade.launch(self, global_position + Vector3.UP * throw_height, throw_dir,
			attack_range * travel_scale * area_scale())
