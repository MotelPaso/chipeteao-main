extends WeaponBase
## Pistola de dardos: dispara dardos rápidos que persiguen un poco al blanco
## adquirido. Con más de un proyectil, los extra salen en abanico alrededor
## de la puntería. Sin modelo en la mano: el disparo se lee por el trazador
## brillante y un fogonazo del pool en el marcador Muzzle en cada ráfaga
## (su aspecto está en MuzzleFlash.tscn, grupo «Fogonazo»).

@export_group("Dardos")
## Escena del dardo que se dispara (Projectile.tscn).
@export var projectile_scene: PackedScene
## Grados entre dardos vecinos cuando hay más de uno.
@export var fan_spread_deg: float = 8.0
## Los dardos vuelan este múltiplo de attack_range, así los blancos al borde del alcance igual reciben.
@export var range_grace: float = 1.3

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
	for i in count:
		var yaw := deg_to_rad(fan_spread_deg) * (float(i) - float(count - 1) * 0.5)
		_spawn_dart(base_dir.rotated(Vector3.UP, yaw), target)
	# Un fogonazo por ráfaga, salgan los dardos que salgan.
	var flash := Pools.acquire_scene(Pools.MUZZLE_FLASH_SCENE) as MuzzleFlash
	if flash != null:
		flash.play(_muzzle.global_position, MuzzleFlash.Style.MUZZLE)


func _spawn_dart(direction: Vector3, target: Node3D) -> void:
	# Del pool, colgado de la arena: el dardo sigue volando mientras el jugador camina.
	var dart := Pools.acquire_scene(projectile_scene) as Projectile
	if dart == null:
		return
	# La puntería puede quedar casi colineal con UP (enemigo justo debajo de
	# una plataforma); un "arriba" lateral mantiene la base construible.
	dart.global_transform = Transform3D(
			Basis.looking_at(direction, safe_up(direction)), _muzzle.global_position)
	dart.launch(self, attack_range * range_grace, target)
