class_name MythosPresence
extends Node
## Lo que se SIENTE cuando Mythos va hacia el raider (nodo Presence de
## Mythos.tscn). Cada pisada en tierra retumba: un golpe sordo, un temblor de
## cámara y brasas bajo la pata. Cada golpe de alas de su vuelo de caza
## levanta una ráfaga de brasas del suelo. Y a medida que acorta la distancia
## los bordes de la pantalla se oscurecen (la viñeta de Feel). Todo se siente
## menos cuanto más lejos está. Solo acompaña: cómo se mueve lo deciden Flight
## y el rig, y las brasas son los nodos StepEmbers y GustEmbers de la escena.

@export_group("Pisadas")
## Sonido de cada pisada (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var step_sfx: StringName = &"phoenix_step"
## Temblor de cámara (0-1) de una pisada junto al raider.
@export var step_shake: float = 0.1
## Segundos que dura ese temblor.
@export var step_shake_seconds: float = 0.2
## Metros hacia cada lado del cuerpo donde cae la pata.
@export var step_side: float = 0.5

@export_group("Aletazos de caza")
## Sonido de cada golpe de alas mientras se le viene encima al raider (vacío = ninguno).
@export var beat_sfx: StringName = &"phoenix_flap"
## Temblor de cámara (0-1) de un golpe de alas junto al raider.
@export var beat_shake: float = 0.05
## Segundos que dura ese temblor.
@export var beat_shake_seconds: float = 0.15
## Altura del cuerpo, en metros, hasta la que sus alas levantan brasas del suelo.
@export var beat_ember_height: float = 6.5

@export_group("Pavor")
## Parte de la viñeta de peligro (0-1) cuando lo tiene encima en vuelo de caza.
@export_range(0.0, 1.0) var hunt_dread: float = 0.4
## Lo mismo cuando lo acecha a pie.
@export_range(0.0, 1.0) var prowl_dread: float = 0.3
## Metros al raider desde los que la viñeta empieza a notarse.
@export var dread_from: float = 16.0
## Metros al raider a los que llega entera.
@export var dread_full_within: float = 5.0

@export_group("Distancia")
## Metros al raider más cercano hasta los que pisadas y aletazos se sienten enteros.
@export var full_within: float = 6.0
## Metros desde los que ya no se sienten.
@export var none_beyond: float = 30.0
## Decibeles que baja el sonido a esa distancia.
@export var far_volume_db: float = -16.0

## Fase del aleteo en el frame anterior, para saber cuándo empieza a empujar.
var _last_phase: float = 0.0

@onready var _boss: Mythos = get_parent() as Mythos
@onready var _motion: MythosMotion = $"../Visual/Motion"
@onready var _step_embers: CPUParticles3D = %StepEmbers
@onready var _gust_embers: CPUParticles3D = %GustEmbers


func _ready() -> void:
	_motion.stepped.connect(_on_stepped)


func _process(_delta: float) -> void:
	if _boss == null or _boss.rig == null or not _boss.is_fighting():
		return
	var phase := _boss.rig.flap_phase
	var pose := _boss.rig.pose()
	# Las alas empujan más fuerte a mitad de la bajada (cuando la fase pasa por PI).
	if pose == MythosRig.Pose.HUNT and _last_phase < PI and phase >= PI:
		_on_wing_beat()
	_last_phase = phase
	var dread := hunt_dread if pose == MythosRig.Pose.HUNT \
			else prowl_dread if pose == MythosRig.Pose.PROWL else 0.0
	if dread > 0.0:
		_boss.feel.dread(dread * (1.0 - smoothstep(dread_full_within, dread_from, _nearest())))


# --- privados ---------------------------------------------------------------------

func _on_stepped(left: bool) -> void:
	if _boss == null or not _boss.is_fighting():
		return
	var near := _nearness()
	if near <= 0.0:
		return
	var side := _boss.global_basis.x * (-step_side if left else step_side)
	_puff(_step_embers, _boss.global_position + side)
	Juice.shake(step_shake * near, step_shake_seconds)
	if step_sfx != &"":
		Sfx.play(step_sfx, lerpf(far_volume_db, 0.0, near))


func _on_wing_beat() -> void:
	var near := _nearness()
	if near <= 0.0:
		return
	if _boss.rig.body_height() <= beat_ember_height:
		_puff(_gust_embers, _boss.global_position)
	Juice.shake(beat_shake * near, beat_shake_seconds)
	if beat_sfx != &"":
		Sfx.play(beat_sfx, lerpf(far_volume_db, 0.0, near))


## Suelta de una vez las brasas de `embers` en `at` (un punto a ras de suelo).
func _puff(embers: CPUParticles3D, at: Vector3) -> void:
	embers.global_position = at
	embers.restart()
	embers.emitting = true


## Metros de Mythos al raider en pie más cercano (INF si no queda ninguno).
func _nearest() -> float:
	var nearest := INF
	for raider: Node3D in Coop.alive_players(get_tree()):
		nearest = minf(nearest, raider.global_position.distance_to(_boss.global_position))
	return nearest


## Cuánto se siente desde donde está el raider más cercano (0-1).
func _nearness() -> float:
	return 1.0 - smoothstep(full_within, none_beyond, _nearest())
