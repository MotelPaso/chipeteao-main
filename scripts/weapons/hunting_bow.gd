extends WeaponBase
## Juno's starting weapon: looses fast, dead-straight arrows that pierce
## through up to pierce_count enemies each (the Arrow scene disables the
## Projectile homing). projectile_count > 1 fans a volley around the aim
## direction, Dart Pistol style.

@export var projectile_scene: PackedScene
## Max enemies one arrow damages before despawning ("Barbed Heads" raises it).
@export var pierce_count: int = 3
## Yaw between neighboring arrows when projectile_count > 1.
@export var fan_spread_deg: float = 7.0
## Aim above the target's origin so arrows hit body height, not feet.
@export var aim_height: float = 0.8
## Arrows fly a bit past attack_range so edge-of-range targets still connect.
@export var range_grace: float = 1.15

@onready var _nock: Node3D = $Nock


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	var to_aim := target.global_position + Vector3.UP * aim_height - _nock.global_position
	# Degenerate case (target on top of the nock): fire where we face.
	var base_dir := to_aim.normalized() if to_aim.length_squared() > 0.0001 \
			else -global_transform.basis.z
	var count := maxi(projectile_count, 1)
	for i: int in count:
		var yaw := deg_to_rad(fan_spread_deg) * (float(i) - float(count - 1) * 0.5)
		_spawn_arrow(base_dir.rotated(Vector3.UP, yaw), target)


func _spawn_arrow(direction: Vector3, target: Node3D) -> void:
	# Pooled, parented to the scene root so arrows keep flying while the
	# player moves on. Pierce is set per shot, after the pool's reset.
	var arrow := Pools.acquire_scene(projectile_scene) as Projectile
	if arrow == null:
		return
	arrow.global_transform = Transform3D(
			Basis.looking_at(direction, Vector3.UP), _nock.global_position)
	arrow.pierce_remaining = maxi(pierce_count, 1)
	arrow.launch(self, attack_range * range_grace, target)
