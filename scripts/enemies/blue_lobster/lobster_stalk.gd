class_name LobsterStalk
extends Node
## Cómo ronda la Langosta Azul entre un ataque y otro (nodo Stalk de
## BlueLobster.tscn): a qué raider persigue y hacia dónde camina. De lejos va
## derecho hacia él (corriendo, si se le fue muy lejos); de cerca lo rodea de
## costado, sin quedarse quieta, y cambia de sentido cada tanto. En co-op
## cambia de raider cada focus_seconds, así sus ataques no caen siempre sobre
## el mismo.

@export_group("Objetivo")
## Segundos que persigue al mismo raider antes de elegir otro (co-op).
@export var focus_seconds: float = 9.0

@export_group("Ronda")
## Distancia al raider, en metros, a la que deja de acercarse y empieza a rodearlo.
@export var orbit_distance: float = 3.3
## Margen en metros alrededor de esa distancia dentro del cual solo rodea.
@export var orbit_band: float = 0.7
## Fracción de su velocidad con que rodea al raider (0-1).
@export_range(0.0, 1.0) var orbit_speed_factor: float = 0.72
## Fracción de su velocidad con que retrocede si el raider se le pega (0-1).
@export_range(0.0, 1.0) var retreat_speed_factor: float = 0.5
## Segundos mínimos entre un cambio de sentido y el siguiente.
@export var flip_min_seconds: float = 1.6
## Segundos máximos entre un cambio de sentido y el siguiente.
@export var flip_max_seconds: float = 3.8

@export_group("Persecución")
## Metros al raider desde los que deja de caminar y CORRE a alcanzarlo.
@export var chase_distance: float = 16.0
## Metros al raider a los que vuelve a caminar.
@export var chase_stop_distance: float = 9.0
## Multiplicador de su velocidad mientras corre (un raider camina a 8,6 m/s).
@export var chase_speed_factor: float = 1.7

## El raider que persigue ahora.
var _focus: Node3D = null
var _focus_left: float = 0.0
## Sentido en que lo rodea: 1 o -1.
var _side: float = 1.0
var _flip_left: float = 0.0
## True mientras corre a alcanzar a un raider que se le fue lejos.
var _chasing: bool = false
## Azar propio: la ronda no toca el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_flip_left = _rng.randf_range(flip_min_seconds, flip_max_seconds)


## Un frame de pelea: corren el reloj del objetivo y el del cambio de sentido.
func tick(delta: float) -> void:
	_focus_left -= delta
	_flip_left -= delta
	if _flip_left <= 0.0:
		flip()


## El raider al que persigue: el mismo mientras siga en pie y no se le acabe
## el turno; si no, el siguiente en pie más cercano (otro, si hay otro).
func pick_target(tree: SceneTree, from: Vector3) -> Node3D:
	var standing := Coop.alive_players(tree)
	if standing.is_empty():
		_focus = null
		return null
	if _focus != null and is_instance_valid(_focus) and standing.has(_focus) \
			and (_focus_left > 0.0 or standing.size() == 1):
		return _focus
	var previous := _focus
	_focus = null
	var best := INF
	for raider: Node3D in standing:
		if raider == previous and standing.size() > 1:
			continue
		var distance := raider.global_position.distance_squared_to(from)
		if distance < best:
			best = distance
			_focus = raider
	_focus_left = focus_seconds
	return _focus


## Hacia dónde camina, con `seek` apuntando al raider y `distance` metros
## hasta él. El largo del vector es la fracción de su velocidad.
func intent(seek: Vector3, distance: float) -> Vector3:
	if seek.length_squared() < 0.0001:
		return Vector3.ZERO
	var tangent := Vector3(-seek.z, 0.0, seek.x) * _side
	if distance > orbit_distance + orbit_band:
		return seek
	if distance < orbit_distance - orbit_band:
		# Demasiado cerca: se abre mientras sigue girando.
		return (tangent - seek * retreat_speed_factor).normalized() * orbit_speed_factor
	# En su distancia: gira y corrige apenas hacia el radio que quiere.
	var radial := (distance - orbit_distance) / maxf(orbit_band, 0.01)
	return (tangent + seek * radial * 0.6).normalized() * orbit_speed_factor


## Multiplicador de su velocidad a `distance` metros del raider: corre si se
## le fue lejos y vuelve a caminar cuando lo tiene cerca.
func pace(distance: float) -> float:
	if distance > chase_distance:
		_chasing = true
	elif distance < chase_stop_distance:
		_chasing = false
	return chase_speed_factor if _chasing else 1.0


## Cambia ya el sentido en que lo rodea (un ataque lo pide al terminar).
func flip() -> void:
	_side = -_side
	_flip_left = _rng.randf_range(flip_min_seconds, flip_max_seconds)
