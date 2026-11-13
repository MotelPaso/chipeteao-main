class_name MythosRain
extends MythosMove
## Lluvia de brasas: marca zonas de fuego sueltas alrededor de CADA raider en
## pie, una tras otra. Ninguna nace encima de nadie (Mythos.spawn_fire_zone lo
## comprueba al marcar); un punto que no sirve se salta sin reintentar.

@export_group("Lluvia")
## Zonas por raider con agresividad 0.
@export var zones_per_raider: int = 2
## Zonas extra por raider con agresividad 1.
@export var extra_zones_at_full_aggression: int = 2
## Radio de cada zona, en metros.
@export var zone_radius: float = 2.2
## Distancia mínima de cada zona a su raider, en metros.
@export var min_distance: float = 4.5
## Distancia máxima de cada zona a su raider, en metros.
@export var max_distance: float = 13.0
## Segundos entre una marca y la siguiente.
@export var mark_interval: float = 0.22
## Segundos de aviso antes de que cada zona se encienda.
@export var warn_seconds: float = 1.1
## Segundos que arde cada zona.
@export var burn_seconds: float = 5.0
## Daño por segundo de cada zona (valor base).
@export var zone_dps: float = 16.0
## Segundos quieto después de la última marca.
@export var recover: float = 0.4

## Raiders que todavía esperan una marca, uno por zona pendiente.
var _queue: Array[Node3D] = []
var _timer: float = 0.0


func scale_damage(multiplier: float) -> void:
	zone_dps *= multiplier


func begin(_target: Node3D) -> void:
	_queue.clear()
	var per_raider := maxi(aggression_count(zones_per_raider, extra_zones_at_full_aggression), 1)
	# Por rondas, para que las marcas se repartan entre los raiders en vez de
	# caer todas seguidas sobre el primero.
	for round_index: int in per_raider:
		for raider: Node3D in Coop.alive_players(get_tree()):
			_queue.append(raider)
	_timer = 0.0
	boss.rig.set_pose(MythosRig.Pose.CAST)


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _queue.is_empty():
		boss.rig.set_pose(MythosRig.Pose.FLY)
		return true
	var raider: Node3D = _queue.pop_front()
	if is_instance_valid(raider) and raider.is_inside_tree():
		var angle := randf() * TAU
		var distance := randf_range(min_distance, max_distance)
		boss.spawn_fire_zone(raider.global_position
				+ Vector3(cos(angle), 0.0, sin(angle)) * distance,
				zone_radius, warn_seconds, burn_seconds, zone_dps)
	_timer = recover if _queue.is_empty() else mark_interval
	return false


func cancel() -> void:
	_queue.clear()
	boss.rig.set_pose(MythosRig.Pose.FLY)
