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
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	# Degenerate case (target directly above/below): throw where we face.
	var throw_dir := to_target.normalized() if to_target.length_squared() > 0.0001 \
			else -global_transform.basis.z
	throw_dir.y = 0.0
	throw_dir = throw_dir.normalized() if throw_dir.length_squared() > 0.0001 \
			else Vector3.FORWARD
	var blade := projectile_scene.instantiate() as BoomerangProjectile
	if blade == null:
		return
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_tree().root
	# Scene-root parent so the blade keeps flying while the player moves on.
	parent_node.add_child(blade)
	blade.launch(self, global_position + Vector3.UP * throw_height, throw_dir,
			attack_range * travel_scale * area_scale())
