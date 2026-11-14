class_name MythosTornados
extends MythosMove
## Tornados de fuego: levanta tornados alrededor del raider. Primero se
## forman (el aviso) y después lo persiguen un rato quemando lo que tocan:
## son más lentos que un raider y giran de a poco, así que se los esquiva
## corriendo y cambiando de rumbo, pero mientras duran no hay dónde quedarse
## quieto. Con agresividad salen más y son más rápidos. En co-op se reparten
## entre los raiders.

@export_group("Tornados")
## Escena del tornado (FireTornado, sale de Pools). Su altura y su aspecto están en esa escena.
@export var tornado_scene: PackedScene = preload("res://scenes/fx/FireTornado.tscn")
## Segundos de carga antes de levantarlos.
@export var windup: float = 0.9
## Tornados con agresividad 0.
@export var count: int = 1
## Tornados extra con agresividad 1.
@export var extra_at_full_aggression: int = 2
## Tope de tornados vivos a la vez.
@export var max_live: int = 4
## Radio de daño de cada tornado, en metros.
@export var radius: float = 3.0
## Distancia al raider, en metros, a la que se forma cada tornado.
@export var spawn_distance: float = 8.0
## Segundos que tarda en formarse (el aviso): mientras tanto no daña.
@export var warn_seconds: float = 1.3
## Segundos que gira persiguiendo antes de deshacerse.
@export var life_seconds: float = 9.0
## Daño por segundo a quien toque (valor base).
@export var dps: float = 32.0
## Metros por segundo a los que persigue, con agresividad 0 (un raider corre a 8,6).
@export var speed: float = 6.0
## Multiplicador de esa velocidad con agresividad 1.
@export var speed_at_full_aggression: float = 1.2
## Segundos quieto después de levantarlos.
@export var recover: float = 0.6

var _target: Node3D = null
var _timer: float = 0.0
var _cast: bool = false


func scale_damage(multiplier: float) -> void:
	dps *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_timer = windup
	_cast = false
	boss.rig.set_pose(MythosRig.Pose.CAST)
	boss.rig.gesture(&"spin")


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _cast:
		return true
	_cast = true
	_raise()
	_timer = recover
	boss.rig.set_pose(boss.rest_pose())
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())


## Forma los tornados en círculo alrededor de sus raiders.
func _raise() -> void:
	var raiders := Coop.alive_players(get_tree())
	if tornado_scene == null or raiders.is_empty():
		return
	var room := max_live - get_tree().get_node_count_in_group(FireTornado.GROUP)
	var wanted := mini(aggression_count(count, extra_at_full_aggression), room)
	var start := randf() * TAU
	for index: int in wanted:
		var raider := raiders[index % raiders.size()]
		var angle := start + TAU * float(index) / float(maxi(wanted, 1))
		var at := boss.safe_point(raider.global_position
				+ Vector3(cos(angle), 0.0, sin(angle)) * spawn_distance)
		var tornado := Pools.acquire_scene(tornado_scene) as FireTornado
		if tornado == null:
			return
		Telegraph.spawn_disc(boss, at, radius, warn_seconds, boss.telegraph_color)
		tornado.start(at, radius, warn_seconds, life_seconds, dps,
				speed * aggression_lerp(1.0, speed_at_full_aggression))
