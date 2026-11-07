extends WeaponBase
## Espada corta: barre un arco cuerpo a cuerpo hacia el enemigo más cercano y
## daña a todo cuerpo del grupo "enemies" dentro. Sin modelo en la mano: el
## ataque se lee por una medialuna SlashArc del pool que cruza el arco de
## golpe, más una chispa pequeña en cada enemigo alcanzado.

## Apertura del tajo, en grados: daña a los enemigos dentro de este abanico.
@export var arc_angle_deg: float = 150.0
## Segundos que dura la medialuna del tajo.
@export var swing_time: float = 0.25
## Color de la medialuna del tajo.
@export var slash_color: Color = Color(0.75, 0.85, 1.0)
## Radio de la medialuna como fracción del alcance del tajo (0-1).
@export var slash_radius_scale: float = 0.9
## Giro de la medialuna como fracción de arc_angle_deg (0-1).
@export var slash_sweep_scale: float = 0.8
## Color de la chispa en cada enemigo alcanzado.
@export var spark_color: Color = Color(0.7, 0.8, 1.0)

@export_group("Multitud")
## Segundos entre los tajos extra del Tomo de Multitud; dos arcos en el mismo frame serían uno que golpea dos veces.
@export var extra_stagger: float = 0.09
## Grados entre tajos vecinos de una ráfaga, para que cada extra cubra su propio terreno.
@export var extra_fan_deg: float = 25.0


func fire(target: Node3D) -> void:
	# Caso degenerado (blanco justo arriba o abajo): se tajea hacia donde miramos.
	var center_dir := flat_dir_or(target.global_position - global_position,
			-global_transform.basis.z)
	fire_volley(maxi(effective_projectile_count(), 1), center_dir, _swing,
			extra_stagger, extra_fan_deg)


## Un tajo completo: la pasada de daño más su medialuna.
func _swing(center_dir: Vector3) -> void:
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
	slash.play(global_position, center_dir, attack_range * area_scale() * slash_radius_scale,
			slash_color, arc_angle_deg * slash_sweep_scale, swing_time)
