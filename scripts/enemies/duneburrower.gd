class_name Duneburrower
extends EnemyBase
## Excavadunas (Dunas de Ceniza), emboscador: alterna una persecución en la
## superficie, lenta y vulnerable, con un avance enterrado. Enterrado sale
## de la capa de enemigos y del grupo "enemies" (las armas no pueden apuntar
## ni pegarle al montículo), se desliza rápido bajo el raider, marca un
## disco y erupciona con daño de área antes de volver vulnerable. Respuesta:
## salir del disco durante la carga y castigar al gusano en la superficie.

enum State { SURFACED, BURROWED, ERUPTING }

## Grupo al que se une MIENTRAS está enterrado: enterrarse lo saca de
## "enemies", y lo que tiene que alcanzar a todo cuerpo vivo (primero que
## nada el tiempo detenido del spawner) se saltaría justo al único enemigo
## que todavía puede herirte desde la arena. Lo lee EnemySpawner.
const BURROWED_GROUP: StringName = &"burrowed"

@export_group("Ciclo")
## Segundos de persecución vulnerable tras cada erupción antes de enterrarse.
@export var surface_duration: float = 4.0
## Segundos máximos enterrado; pasado esto erupciona donde esté, así no se pasea para siempre un montículo invulnerable.
@export var max_burrow_duration: float = 6.0
## Distancia plana al raider, en metros, a la que el montículo ataca.
@export var strike_trigger_range: float = 1.1
## Multiplicador de move_speed mientras está enterrado (2.4 = 2.4 veces más rápido).
@export var burrow_speed_multiplier: float = 2.4

@export_group("Erupción")
## Segundos de aviso entre el disco y la erupción.
@export var erupt_windup: float = 0.8
## Radio de la erupción y de su disco de aviso, en metros.
@export var erupt_radius: float = 2.0
## Daño de la erupción a cada raider dentro del disco.
@export var erupt_damage: float = 14.0
## Metros sobre el punto de ataque por encima de los cuales la erupción no golpea.
@export var erupt_height_window: float = 1.5

@export_group("Telegrafía")
## Color del disco de aviso de la erupción.
@export var telegraph_color: Color = Color(0.95, 0.7, 0.25)
## Color del destello de impacto de la erupción.
@export var impact_color: Color = Color(1.0, 0.85, 0.45)
## Segundos que dura el destello de impacto.
@export var impact_flash_time: float = 0.2
## Fuerza del temblor de cámara de la erupción (0-1).
@export var impact_shake_strength: float = 0.1
## Segundos del temblor de cámara de la erupción.
@export var impact_shake_duration: float = 0.3
## Tope de trauma del temblor (0-1): muchas erupciones juntas no sacuden más que esto.
@export var impact_shake_cap: float = 0.4
## Color de las esquirlas de arena de la erupción.
@export var sand_burst_color: Color = Color(0.8, 0.66, 0.4)
## Cantidad de esquirlas de arena de la erupción.
@export var sand_burst_count: int = 7

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
	Telegraph.spawn_disc(self, _strike_point, erupt_radius, erupt_windup, telegraph_color)


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
	Telegraph.spawn_disc(self, _strike_point, erupt_radius, impact_flash_time, impact_color)
	Sfx.play(&"burrow_pop")
	Juice.shake(impact_shake_strength, impact_shake_duration, impact_shake_cap)
	Juice.burst(_strike_point + Vector3.UP * 0.5, sand_burst_color, sand_burst_count)
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
