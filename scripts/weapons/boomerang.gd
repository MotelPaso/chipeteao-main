extends WeaponBase
## Bumerán: lanza una hoja giratoria que vuela por la línea de puntería y
## vuelve al jugador, cortando todo lo que cruza a la ida y a la vuelta
## (BoomerangProjectile maneja el vuelo de ida y vuelta).

@export var projectile_scene: PackedScene
## Multiplicador de la distancia de vuelo antes de dar la vuelta ("Vuelo
## lejano" lo sube; los tomos de área también estiran el recorrido).
@export var travel_scale: float = 1.0
## Altura sobre este montaje desde la que se lanza la hoja, en metros.
@export var throw_height: float = 0.0

## Segundos entre las hojas que agrega el Tomo de Multitud. Se lanzan una
## tras otra, nunca juntas: hojas de la misma mano en el mismo frame vuelan
## la misma línea y solo la primera toca algo.
const EXTRA_THROW_STAGGER: float = 0.11
## Giro entre hojas vecinas, así cada extra barre su propio pasillo.
const EXTRA_THROW_FAN_DEG: float = 20.0
## La cadena escalonada entera termina dentro de esta fracción de un
## enfriamiento, o una ráfaga seguiría saliendo de la mano en el siguiente lanzamiento.
const THROW_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	# Caso degenerado (blanco justo arriba o abajo): se lanza hacia donde
	# miramos, y hacia FORWARD si nuestro frente también es vertical.
	var center_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_THROW_STAGGER,
			effective_cooldown() * THROW_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_THROW_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		var throw_dir := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			_throw_blade(throw_dir)
		else:
			# Temporizador pausable y en paso de física: una hoja extra no sale
			# con la pantalla de mejoras abierta, y el lanzamiento cae en el
			# mismo tick que el resto del combate.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_throw_blade.bind(throw_dir))


## Lanza una hoja por `throw_dir`. Los extras escalonados llegan aquí un poco
## después, cuando el arma puede haber salido del árbol con un raider
## quitado: fuera del árbol no hay posición de salida ni jugador al que volver.
func _throw_blade(throw_dir: Vector3) -> void:
	if not is_inside_tree():
		return
	# Del pool, colgada de la arena: la hoja sigue volando mientras el jugador camina.
	var blade := Pools.acquire_scene(projectile_scene) as BoomerangProjectile
	if blade == null:
		return
	blade.launch(self, global_position + Vector3.UP * throw_height, throw_dir,
			attack_range * travel_scale * area_scale())
