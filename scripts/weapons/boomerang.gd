extends WeaponBase
## Bumerán: lanza una hoja giratoria que vuela por la línea de puntería y
## vuelve al jugador, cortando todo lo que cruza a la ida y a la vuelta
## (BoomerangProjectile maneja el vuelo de ida y vuelta).

@export_group("Lanzamiento")
## Escena del bumerán que se lanza (BoomerangProjectile.tscn).
@export var projectile_scene: PackedScene
## Multiplicador de la distancia de vuelo antes de dar la vuelta ("Vuelo lejano" y los tomos de área lo estiran).
@export var travel_scale: float = 1.0
## Altura sobre este montaje desde la que se lanza la hoja, en metros.
@export var throw_height: float = 0.0

@export_group("Multitud")
## Segundos entre las hojas extra del Tomo de Multitud; lanzadas juntas volarían la misma línea y solo la primera tocaría algo.
@export var extra_stagger: float = 0.11
## Grados entre hojas vecinas de una ráfaga, para que cada extra barra su propio pasillo.
@export var extra_fan_deg: float = 20.0


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Caso degenerado (blanco justo arriba o abajo): se lanza hacia donde
	# miramos, y hacia FORWARD si nuestro frente también es vertical.
	var center_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	fire_volley(maxi(effective_projectile_count(), 1), center_dir, _throw_blade,
			extra_stagger, extra_fan_deg)


## Lanza una hoja por `throw_dir`.
func _throw_blade(throw_dir: Vector3) -> void:
	# Del pool, colgada de la arena: la hoja sigue volando mientras el jugador camina.
	var blade := Pools.acquire_scene(projectile_scene) as BoomerangProjectile
	if blade == null:
		return
	blade.launch(self, global_position + Vector3.UP * throw_height, throw_dir,
			attack_range * travel_scale * area_scale())
