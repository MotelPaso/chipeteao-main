extends WeaponBase
## Arco de caza: suelta flechas rápidas y rectas que atraviesan hasta
## pierce_count enemigos cada una (la escena Arrow apaga la persecución del
## Projectile). Con más de un proyectil, la ráfaga sale en abanico alrededor
## de la puntería. Sin modelo en la mano: el disparo se lee por el trazador
## grueso de la flecha y un destello de carga en el Nock que crece y estalla
## al soltar (su aspecto está en MuzzleFlash.tscn, grupo «Destello de carga»).

## Escena de la flecha que se dispara (Arrow.tscn).
@export var projectile_scene: PackedScene
## Máximo de enemigos que daña una flecha antes de desaparecer ("Puntas con púas" lo sube).
@export var pierce_count: int = 3
## Grados entre flechas vecinas cuando hay más de una.
@export var fan_spread_deg: float = 7.0
## Las flechas vuelan este múltiplo de attack_range, así los blancos al borde del alcance igual reciben.
@export var range_grace: float = 1.15

@onready var _nock: Node3D = $Nock


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Caso degenerado (blanco encima del Nock): se dispara hacia donde miramos.
	var base_dir := aim_dir_or(
			body_aim_point(target) - _nock.global_position,
			-global_transform.basis.z)
	var count := maxi(effective_projectile_count(), 1)
	for i: int in count:
		var yaw := deg_to_rad(fan_spread_deg) * (float(i) - float(count - 1) * 0.5)
		_spawn_arrow(base_dir.rotated(Vector3.UP, yaw), target)
	# Destello de tensar y soltar: crece como una cuerda tensa que atrapa luz y
	# estalla cuando salen las flechas.
	var glint := Pools.acquire_scene(Pools.MUZZLE_FLASH_SCENE) as MuzzleFlash
	if glint != null:
		glint.play(_nock.global_position, MuzzleFlash.Style.GLINT)


func _spawn_arrow(direction: Vector3, target: Node3D) -> void:
	# Del pool, colgada de la arena: la flecha sigue volando mientras el
	# jugador camina. La perforación se fija por disparo, después del reinicio del pool.
	var arrow := Pools.acquire_scene(projectile_scene) as Projectile
	if arrow == null:
		return
	# La puntería puede quedar casi colineal con UP (enemigo justo debajo de
	# una plataforma); un "arriba" lateral mantiene la base construible.
	arrow.global_transform = Transform3D(
			Basis.looking_at(direction, safe_up(direction)), _nock.global_position)
	arrow.pierce_remaining = maxi(pierce_count, 1)
	arrow.launch(self, attack_range * range_grace, target)
