extends WeaponBase
## Vex's starting weapon: fires fast, lightly homing darts at the acquired
## target. projectile_count > 1 fans the extra darts around the aim direction.

@export var projectile_scene: PackedScene
## Yaw between neighboring darts when projectile_count > 1.
@export var fan_spread_deg: float = 8.0
## Aim above the target's origin so darts hit body height, not feet.
@export var aim_height: float = 0.8
## Darts fly a bit past attack_range so edge-of-range targets still connect.
@export var range_grace: float = 1.3

@onready var _muzzle: Node3D = $Muzzle


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	var to_aim := target.global_position + Vector3.UP * aim_height - _muzzle.global_position
	# Degenerate case (target on top of the muzzle): fire where we face.
	var base_dir := to_aim.normalized() if to_aim.length_squared() > 0.0001 \
			else -global_transform.basis.z
	var count := maxi(projectile_count, 1)
	for i in count:
		var yaw := deg_to_rad(fan_spread_deg) * (float(i) - float(count - 1) * 0.5)
		_spawn_dart(base_dir.rotated(Vector3.UP, yaw), target)


func _spawn_dart(direction: Vector3, target: Node3D) -> void:
	var dart := projectile_scene.instantiate() as Projectile
	if dart == null:
		return
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_tree().root
	# Scene-root parent so darts keep flying while the player moves on.
	parent_node.add_child(dart)
	dart.global_transform = Transform3D(
			Basis.looking_at(direction, Vector3.UP), _muzzle.global_position)
	dart.launch(self, attack_range * range_grace, target)
