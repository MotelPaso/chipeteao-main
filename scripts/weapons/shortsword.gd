extends WeaponBase
## Espada corta: barre un arco cuerpo a cuerpo hacia el enemigo más cercano y
## daña a todo cuerpo del grupo "enemies" dentro. Sin modelo en la mano: el
## ataque se lee por una medialuna SlashArc del pool que cruza el arco de
## golpe, más una chispa pequeña en cada enemigo alcanzado.

@export var arc_angle_deg: float = 150.0
@export var swing_time: float = 0.25
## Color de la medialuna del tajo.
@export var slash_color: Color = Color(0.75, 0.85, 1.0)
## Color de la chispa en cada enemigo alcanzado.
@export var spark_color: Color = Color(0.7, 0.8, 1.0)

## Segundos entre los tajos que agrega el Tomo de Multitud. Escalonados y no
## simultáneos: dos arcos desde el mismo hombro en el mismo frame son un arco
## que golpea dos veces.
const EXTRA_SWING_STAGGER: float = 0.09
## Giro entre tajos vecinos, así los extras cubren su propio terreno.
const EXTRA_SWING_FAN_DEG: float = 25.0
## La cadena escalonada entera termina dentro de esta fracción de un
## enfriamiento, o una ráfaga larga seguiría tajeando al empezar la siguiente.
const SWING_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	# Caso degenerado (blanco justo arriba o abajo): se tajea hacia donde miramos.
	var center_dir := flat_dir_or(target.global_position - global_position,
			-global_transform.basis.z)
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_SWING_STAGGER,
			effective_cooldown() * SWING_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_SWING_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		var swing_dir := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			_swing(swing_dir)
		else:
			# Temporizador pausable y en paso de física: un tajo extra no sale
			# con la pantalla de mejoras abierta, y el daño cae en el mismo tick
			# que el resto del combate.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_swing.bind(swing_dir))


## Un tajo completo: la pasada de daño más su medialuna. Los extras
## escalonados llegan aquí un poco después, cuando el arma puede haber
## salido del árbol con un raider quitado.
func _swing(center_dir: Vector3) -> void:
	if not is_inside_tree():
		return
	_hit_enemies_in_arc(center_dir)
	_play_swing(center_dir)


func _hit_enemies_in_arc(center_dir: Vector3) -> void:
	# Los tomos de área alargan el tajo más allá del alcance de búsqueda.
	var reach := attack_range * area_scale()
	for body: Node3D in enemies_in_arc(global_position, center_dir, reach, arc_angle_deg):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
			# Chispa pequeña donde "conecta" la hoja.
			Juice.burst(body.global_position + Vector3.UP * 0.6, spark_color, 4)


func _play_swing(center_dir: Vector3) -> void:
	var slash := Pools.acquire_scene(Pools.SLASH_ARC_SCENE) as SlashArc
	if slash == null:
		return
	slash.play(global_position, center_dir, attack_range * area_scale() * 0.9,
			slash_color, arc_angle_deg * 0.8, swing_time)
