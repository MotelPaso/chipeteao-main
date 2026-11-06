class_name Duneburrower
extends EnemyBase
## Excavadunas (Dunas de Ceniza), emboscador: alterna una persecución en la
## superficie, lenta y vulnerable, con un avance enterrado. Enterrado sale
## de la capa de enemigos y del grupo "enemies" (las armas no pueden apuntar
## ni pegarle al montículo), se desliza rápido bajo el raider, marca un
## disco y erupciona con daño de área antes de volver vulnerable. Respuesta:
## salir del disco durante la carga y castigar al gusano en la superficie.

enum State { SURFACED, BURROWED, ERUPTING }

const TELEGRAPH_COLOR := Color(0.95, 0.7, 0.25)
## Grupo al que se une MIENTRAS está enterrado: enterrarse lo saca de
## "enemies", y lo que tiene que alcanzar a todo cuerpo vivo (primero que
## nada el tiempo detenido del spawner) se saltaría justo al único enemigo
## que todavía puede herirte desde la arena. Lo lee EnemySpawner.
const BURROWED_GROUP: StringName = &"burrowed"
const IMPACT_COLOR := Color(1.0, 0.85, 0.45)
const SAND_BURST_COLOR := Color(0.8, 0.66, 0.4)

@export_group("Cycle")
## Segundos de persecución vulnerable tras cada erupción antes de enterrarse.
@export var surface_duration: float = 4.0
## Seguro: enterrado, erupciona donde esté pasado este tiempo, así un raider
## más rápido no puede pasear para siempre un montículo invulnerable.
@export var max_burrow_duration: float = 6.0
## El montículo ataca al llegar a esta distancia plana del raider.
@export var strike_trigger_range: float = 1.1
@export var burrow_speed_multiplier: float = 2.4

@export_group("Eruption")
@export var erupt_windup: float = 0.8
@export var erupt_radius: float = 2.0
@export var erupt_damage: float = 14.0
## Erupción desde el suelo: un raider más alto que esto sobre el punto de
## ataque (una cornisa de mesa) no recibe el golpe.
@export var erupt_height_window: float = 1.5

var _state: State = State.SURFACED
var _state_timer: float = 0.0
var _strike_point: Vector3 = Vector3.ZERO
# Estado guardado al enterrarse y restaurado al erupcionar, para que el
# gusano vuelva exactamente como bajó (y no a valores fijos que se desfasan
# en cuanto una escena cambia uno).
var _surface_separation: float = 0.0
var _surface_speed: float = 0.0
var _surface_layer: int = 0
var _surface_mask: int = 0
# Raiders exceptuados de colisión mientras está enterrado: el montículo
# tiene que pasar bajo TODOS (en co-op cada raider es un obstáculo).
var _tunneled_players: Array[PhysicsBody3D] = []

@onready var _mound: Node3D = $Mound


func _init() -> void:
	# No poseíble: guarda y restaura sus propias capas y grupo en cada ciclo
	# de enterrarse, así que poseído seguiría atacando al equipo al que ahora
	# pertenece.
	possessable = false


func _ready() -> void:
	super()
	_state_timer = surface_duration
	# Sembrado desde la escena para que una erupción siempre pueda restaurar
	# un estado de superficie real, incluso por un camino que nunca pasó por
	# _burrow().
	_surface_speed = move_speed
	_surface_separation = separation_strength
	_surface_layer = collision_layer
	_surface_mask = collision_mask


func _behavior_tick(delta: float) -> void:
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.SURFACED:
			_burrow()
		State.BURROWED:
			_begin_eruption()  # seguro: ataca donde esté el montículo
		State.ERUPTING:
			_erupt()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	# El montículo se queda quieto bajo su disco; los otros dos estados persiguen.
	return Vector3.ZERO if _state == State.ERUPTING else seek


func _combat_tick(_player: Node3D, distance: float) -> void:
	if _state == State.BURROWED and distance <= strike_trigger_range:
		_begin_eruption()


func _burrow() -> void:
	_state = State.BURROWED
	_state_timer = max_burrow_duration
	_surface_speed = move_speed
	_surface_layer = collision_layer
	_surface_mask = collision_mask
	move_speed *= burrow_speed_multiplier
	# Fuera de la capa de enemigos y del grupo: las armas no lo apuntan, los
	# proyectiles del raider (máscara 2) le pasan por encima y la horda ni lo
	# empuja ni lo esquiva. La máscara baja a solo mundo para seguir pisando
	# el suelo, pero el raider comparte la capa 1 con el mundo: la excepción
	# de colisión es lo que deja al montículo pasar BAJO él en vez de chocarlo
	# (o treparlo).
	remove_from_group("enemies")
	# ...pero lo sigue encontrando lo que tiene que alcanzar a TODO cuerpo
	# vivo, como el congelamiento del tiempo detenido.
	add_to_group(BURROWED_GROUP)
	collision_layer = 0
	collision_mask = 1
	_tunneled_players.clear()
	for node: Node3D in Coop.alive_players(get_tree()):
		var body := node as PhysicsBody3D
		if body == null:
			continue
		_tunneled_players.append(body)
		add_collision_exception_with(body)
	_surface_separation = separation_strength
	separation_strength = 0.0
	_visual.visible = false
	_mound.visible = true


func _begin_eruption() -> void:
	if _state == State.ERUPTING:
		return
	_state = State.ERUPTING
	_state_timer = erupt_windup
	# El disco marca dónde va a salir el gusano (bajo el raider al disparar);
	# salir de él durante la carga evita todo el daño.
	_strike_point = global_position
	Telegraph.spawn_disc(self, _strike_point, erupt_radius, erupt_windup, TELEGRAPH_COLOR)


func _erupt() -> void:
	_state = State.SURFACED
	_state_timer = surface_duration
	# Se restaura, no se divide de vuelta: un burrow_speed_multiplier de 0
	# dividiría por cero, y un cambio de velocidad aplicado bajo tierra (un
	# ascenso a shiny) sobreviviría la vuelta multiplicado.
	move_speed = _surface_speed
	# Cualquier deriva residual vuelve al punto marcado, así el área de golpe
	# es exactamente la que prometió el disco.
	global_position.x = _strike_point.x
	global_position.z = _strike_point.z
	add_to_group("enemies")
	remove_from_group(BURROWED_GROUP)
	collision_layer = _surface_layer
	collision_mask = _surface_mask
	for body: PhysicsBody3D in _tunneled_players:
		if is_instance_valid(body):
			remove_collision_exception_with(body)
	_tunneled_players.clear()
	separation_strength = _surface_separation
	_mound.visible = false
	_visual.visible = true
	_play_erupt_pop()
	Telegraph.spawn_disc(self, _strike_point, erupt_radius, 0.2, IMPACT_COLOR)
	Sfx.play(&"burrow_pop")
	Juice.shake(0.1, 0.3, 0.4)
	Juice.burst(_strike_point + Vector3.UP * 0.5, SAND_BURST_COLOR, 7)
	# El disco es una promesa de área: todo el que esté encima recibe el golpe.
	damage_players_in_disc(_strike_point, erupt_radius, erupt_height_window,
			erupt_damage, self)


# Los factores de shiny y de grado caen sobre la erupción.
func _apply_elite_damage(multiplier: float) -> void:
	erupt_damage *= multiplier


## Estirón al salir: el gusano asoma del suelo.
func _play_erupt_pop() -> void:
	_visual.scale = Vector3(1.3, 0.15, 1.3)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
