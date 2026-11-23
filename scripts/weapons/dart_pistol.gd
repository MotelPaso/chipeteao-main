extends WeaponBase
## Pistola de dardos: dispara dardos rápidos que persiguen un poco al blanco
## adquirido. Con más de un proyectil, los dardos salen en ráfaga, uno tras
## otro, todos hacia el mismo blanco (ver fire_volley()). Sin modelo en
## la mano: el disparo se lee por el trazador brillante y un fogonazo del pool
## en el marcador Muzzle con cada dardo (su aspecto está en MuzzleFlash.tscn,
## grupo «Fogonazo»).
## Rebotes: tras impactar, el dardo sale directo hacia otro enemigo cercano (ver
## Projectile._bounce_to_next), hasta `bounces` veces.

@export_group("Dardos")
## Escena del dardo que se dispara (Projectile.tscn).
@export var projectile_scene: PackedScene
## Los dardos vuelan este múltiplo de attack_range, así los blancos al borde del alcance igual reciben.
@export var range_grace: float = 1.3
## Velocidad de vuelo del dardo, en m/s. Pisa la del Projectile.tscn en cada disparo. Las mejoras de arma la suben.
@export var projectile_speed: float = 60.0
## Radianes por segundo que el dardo puede girar hacia su blanco (la escena usa mucho menos); más alto = menos fallos.
@export var homing_turn_speed: float = 18.0
## Veces que el dardo salta a otro enemigo cercano tras impactar. Las mejoras de arma lo suben, con decimales (1.3, 1.7…); se usa redondeado hacia abajo.
@export var bounces: float = 1.0
## Distancia máxima, en metros, a la que un rebote busca el siguiente enemigo.
@export var bounce_range: float = 10.0
## Si cada rebote muestra un destello en el punto del choque.
@export var bounce_flash: bool = true

@export_group("Ráfaga")
## Segundos entre dardos de una misma ráfaga (se comprime si no cabe en el enfriamiento).
@export var burst_stagger: float = 0.07

@onready var _muzzle: Node3D = $Muzzle
@onready var _hit_sound: AudioStreamPlayer = $HitSound


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Caso degenerado (blanco encima de la boca): se dispara hacia donde miramos.
	var base_dir := aim_dir_or(
			body_aim_point(target) - _muzzle.global_position,
			-global_transform.basis.z)
	var count := maxi(effective_projectile_count(), 1)
	fire_volley(count, target, base_dir, _shoot_dart, burst_stagger)


## Un dardo con su fogonazo, hacia el blanco de la ráfaga (volley_target());
## si ya murió vuela recto por `direction`.
func _shoot_dart(direction: Vector3) -> void:
	var dart := Pools.acquire_scene(projectile_scene) as Projectile
	if dart != null:
		# La puntería puede quedar casi colineal con UP (enemigo justo debajo de
		# una plataforma); un "arriba" lateral mantiene la base construible.
		dart.global_transform = Transform3D(
				Basis.looking_at(direction, safe_up(direction)), _muzzle.global_position)
		dart.launch(self, attack_range * range_grace, volley_target())
		# Después del reinicio del pool, que los deja en su valor de escena.
		dart.speed = projectile_speed
		dart.homing_turn_speed = homing_turn_speed
		dart.bounces_left = floori(bounces + 0.0001)
		# Puntería asistida: impacto comprobado por la propia bala y nuevo blanco
		# si el suyo muere (ver Projectile.assisted).
		dart.assisted = true
	var flash := Pools.acquire_scene(Pools.MUZZLE_FLASH_SCENE) as MuzzleFlash
	if flash != null:
		flash.play(_muzzle.global_position, MuzzleFlash.Style.MUZZLE)
	_hit_sound.play()


## Lo llama el dardo (Projectile) al rebotar: un destello donde salta.
func on_dart_bounce(at: Vector3) -> void:
	if not bounce_flash:
		return
	var flash := Pools.acquire_scene(Pools.MUZZLE_FLASH_SCENE) as MuzzleFlash
	if flash != null:
		flash.play(at, MuzzleFlash.Style.MUZZLE)
