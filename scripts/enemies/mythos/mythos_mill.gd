class_name MythosMill
extends MythosMove
## Molino de tornados (segunda fase): levanta varias aspas de tornados de
## fuego alrededor de sí mismo. Primero se forman (el aviso, sin dañar) y
## después las aspas giran como un molino durante unos segundos. Las puntas
## barren más rápido de lo que corre un raider: se esquiva yendo hacia
## adentro, donde giran más lento, pasando por el hueco entre dos tornados
## de un aspa, o saliendo de su alcance. Con agresividad salen más aspas.

@export_group("Molino")
## Escena del tornado (FireTornado, sale de Pools).
@export var tornado_scene: PackedScene = preload("res://scenes/fx/FireTornado.tscn")
## Segundos de carga antes de levantarlo.
@export var windup: float = 1.0
## Aspas con agresividad 0.
@export var blades: int = 3
## Aspas extra con agresividad 1.
@export var extra_blades_at_full_aggression: int = 1
## Tornados de cada aspa.
@export var per_blade: int = 3
## Metros entre el centro y el primer tornado de cada aspa, y entre un tornado y el siguiente.
@export var spacing: float = 7.0
## Radio de daño de cada tornado, en metros (menos que la mitad de spacing: queda un hueco entre dos).
@export var radius: float = 2.6
## Segundos que tarda en formarse (el aviso): mientras tanto no daña.
@export var warn_seconds: float = 1.3
## Radianes por segundo a los que gira, con agresividad 0 (a 0,55 la punta de un aspa de 21 m va a 11,5 m/s).
@export var spin_speed: float = 0.5
## Multiplicador de ese giro con agresividad 1.
@export var spin_at_full_aggression: float = 1.25
## Segundos que gira antes de deshacerse.
@export var life_seconds: float = 7.0
## Daño por segundo de cada tornado a quien toque (valor base).
@export var dps: float = 26.0
## Tope de tornados vivos a la vez, contando los de sus otros ataques.
@export var max_live: int = 30
## Segundos quieto después de levantarlo.
@export var recover: float = 0.7

var _timer: float = 0.0
var _cast: bool = false
## Hacia qué lado gira (1 o -1): cambia en cada molino.
var _turn: float = 1.0


func scale_damage(multiplier: float) -> void:
	dps *= multiplier


func begin(_target: Node3D) -> void:
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
	boss.rig.gesture(&"slam")
	_timer = recover
	boss.rig.set_pose(boss.rest_pose())
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())


## Levanta las aspas alrededor de donde está, hasta donde deja el tope.
func _raise() -> void:
	if tornado_scene == null:
		return
	var room := max_live - get_tree().get_node_count_in_group(FireTornado.GROUP)
	var count := mini(aggression_count(blades, extra_blades_at_full_aggression),
			room / maxi(per_blade, 1))
	if count < 1:
		return
	_turn = -_turn
	var center := boss.floor_point(boss.global_position)
	var spin := spin_speed * aggression_lerp(1.0, spin_at_full_aggression) * _turn
	var start := randf() * TAU
	for blade: int in count:
		var angle := start + TAU * float(blade) / float(count)
		var arm := Vector3(cos(angle), 0.0, sin(angle))
		for step: int in per_blade:
			var reach := spacing * float(step + 1)
			var at := boss.floor_point(center + arm * reach)
			var tornado := Pools.acquire_scene(tornado_scene) as FireTornado
			if tornado == null:
				return
			Telegraph.spawn_disc(boss, at, radius, warn_seconds, boss.telegraph_color)
			tornado.start(at, radius, warn_seconds, life_seconds, dps, 0.0, false)
			tornado.orbit(center, spin, 0.0, reach)
