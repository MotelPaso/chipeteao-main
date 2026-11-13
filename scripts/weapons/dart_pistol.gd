extends WeaponBase
## Pistola de dardos: dispara dardos rápidos que persiguen un poco al blanco
## adquirido. Con más de un proyectil, los dardos salen en ráfaga, uno tras
## otro, en abanico alrededor de la puntería (ver fire_volley()). Sin modelo en
## la mano: el disparo se lee por el trazador brillante y un fogonazo del pool
## en el marcador Muzzle con cada dardo (su aspecto está en MuzzleFlash.tscn,
## grupo «Fogonazo»).

@export_group("Dardos")
## Escena del dardo que se dispara (Projectile.tscn).
@export var projectile_scene: PackedScene
## Grados entre dardos vecinos cuando hay más de uno.
@export var fan_spread_deg: float = 8.0
## Los dardos vuelan este múltiplo de attack_range, así los blancos al borde del alcance igual reciben.
@export var range_grace: float = 1.3

@export_group("Ráfaga")
## Segundos entre dardos de una misma ráfaga (se comprime si no cabe en el enfriamiento).
@export var burst_stagger: float = 0.07

@onready var _muzzle: Node3D = $Muzzle


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Caso degenerado (blanco encima de la boca): se dispara hacia donde miramos.
	var base_dir := aim_dir_or(
			body_aim_point(target) - _muzzle.global_position,
			-global_transform.basis.z)
	var count := maxi(effective_projectile_count(), 1)
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
