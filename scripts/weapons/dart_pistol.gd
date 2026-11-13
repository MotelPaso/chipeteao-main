extends WeaponBase
<<<<<<< Updated upstream
## Vex's starting weapon: fires fast, lightly homing darts at the acquired
## target. projectile_count > 1 fans the extra darts around the aim direction.
## No held model — the shot reads through the bright tracer plus a pooled
## muzzle-flash pop at the Muzzle marker on every volley.
=======
## Pistola de dardos: dispara dardos rápidos que persiguen un poco al blanco
## adquirido. Con más de un proyectil, los dardos salen en ráfaga, uno tras
## otro, en abanico alrededor de la puntería (ver fire_volley()). Sin modelo en
## la mano: el disparo se lee por el trazador brillante y un fogonazo del pool
## en el marcador Muzzle con cada dardo (su aspecto está en MuzzleFlash.tscn,
## grupo «Fogonazo»).
<<<<<<< Updated upstream
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes

@export var projectile_scene: PackedScene
## Muzzle flash tint (matches the dart tracer).
@export var flash_color: Color = Color(1.0, 0.8, 0.35)
## Yaw between neighboring darts when projectile_count > 1.
@export var fan_spread_deg: float = 8.0
## Aim above the target's origin so darts hit body height, not feet.
@export var aim_height: float = 0.8
## Darts fly a bit past attack_range so edge-of-range targets still connect.
@export var range_grace: float = 1.3

@export_group("Ráfaga")
## Segundos entre dardos de una misma ráfaga (se comprime si no cabe en el enfriamiento).
@export var burst_stagger: float = 0.07

@onready var _muzzle: Node3D = $Muzzle


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Degenerate case (target on top of the muzzle): fire where we face.
	var base_dir := aim_dir_or(
			target.global_position + Vector3.UP * aim_height - _muzzle.global_position,
			-global_transform.basis.z)
	var count := maxi(effective_projectile_count(), 1)
<<<<<<< Updated upstream
<<<<<<< Updated upstream
	for i in count:
		var yaw := deg_to_rad(fan_spread_deg) * (float(i) - float(count - 1) * 0.5)
		_spawn_dart(base_dir.rotated(Vector3.UP, yaw), target)
	# One flash per volley, however many darts fan out.
	var flash := Pools.acquire_scene(Pools.MUZZLE_FLASH_SCENE) as MuzzleFlash
	if flash != null:
		flash.play(_muzzle.global_position, flash_color, 0.5)


func _spawn_dart(direction: Vector3, target: Node3D) -> void:
	# Pooled, parented to the scene root so darts keep flying while the
	# player moves on.
	var dart := Pools.acquire_scene(projectile_scene) as Projectile
	if dart == null:
		return
	# Aim can run near-colinear with UP (enemy right below a platform edge);
	# a sideways up vector keeps the basis buildable, flight unchanged.
	dart.global_transform = Transform3D(
			Basis.looking_at(direction, safe_up(direction)), _muzzle.global_position)
	dart.launch(self, attack_range * range_grace, target)
=======
	fire_volley(count, base_dir, _shoot_dart.bind(target), burst_stagger, fan_spread_deg)


## Un dardo con su fogonazo. Los dardos escalonados salen unos instantes
## después de fire(): si el blanco ya murió, vuelan rectos en la dirección
## calculada (el dardo ya deja de perseguir cadáveres por sí solo).
func _shoot_dart(direction: Vector3, target: Node3D) -> void:
	var dart := Pools.acquire_scene(projectile_scene) as Projectile
	if dart != null:
		# La puntería puede quedar casi colineal con UP (enemigo justo debajo de
		# una plataforma); un "arriba" lateral mantiene la base construible.
		dart.global_transform = Transform3D(
				Basis.looking_at(direction, safe_up(direction)), _muzzle.global_position)
		dart.launch(self, attack_range * range_grace, target if is_instance_valid(target) else null)
	var flash := Pools.acquire_scene(Pools.MUZZLE_FLASH_SCENE) as MuzzleFlash
	if flash != null:
		flash.play(_muzzle.global_position, MuzzleFlash.Style.MUZZLE)
>>>>>>> Stashed changes
=======
	fire_volley(count, base_dir, _shoot_dart.bind(target), burst_stagger, fan_spread_deg)


## Un dardo con su fogonazo. Los dardos escalonados salen unos instantes
## después de fire(): si el blanco ya murió, vuelan rectos en la dirección
## calculada (el dardo ya deja de perseguir cadáveres por sí solo).
func _shoot_dart(direction: Vector3, target: Node3D) -> void:
	var dart := Pools.acquire_scene(projectile_scene) as Projectile
	if dart != null:
		# La puntería puede quedar casi colineal con UP (enemigo justo debajo de
		# una plataforma); un "arriba" lateral mantiene la base construible.
		dart.global_transform = Transform3D(
				Basis.looking_at(direction, safe_up(direction)), _muzzle.global_position)
		dart.launch(self, attack_range * range_grace, target if is_instance_valid(target) else null)
	var flash := Pools.acquire_scene(Pools.MUZZLE_FLASH_SCENE) as MuzzleFlash
	if flash != null:
		flash.play(_muzzle.global_position, MuzzleFlash.Style.MUZZLE)
>>>>>>> Stashed changes
