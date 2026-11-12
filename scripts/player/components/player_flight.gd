class_name PlayerFlight
extends Node
## Vuelo (power-up): mientras dura, mantener saltar sube hasta un techo
## medido sobre el terreno y soltarlo planea hacia abajo. Al terminar, si el
## raider quedó sobre una celda bloqueada, lo baja a suelo caminable. Es el
## nodo Flight de Player.tscn: Player llama a tick() en su tick de física y
## PowerUps llama a Player.end_flight() por nombre.

## Puntos caminables que se prueban al aterrizar sobre una celda bloqueada;
## gana el más cercano. Cada uno saca números del RNG de la arena: cambiar
## la cantidad cambia las partidas con semilla.
const LANDING_SAMPLES: int = 24
## Altura sobre el terreno, en metros, desde la que cae el raider al
## aterrizar, para que se asiente sin empezar dentro del suelo.
const LANDING_CLEARANCE: float = 1.2

@export_group("Vuelo")
## Velocidad de subida mientras se mantiene saltar, en metros por segundo.
@export var flight_rise_speed: float = 9.0
## Techo sobre el terreno bajo el raider, en metros (pasa mesetas y rocas, la cámara aún ve el suelo).
@export var flight_ceiling: float = 12.0
## Velocidad de descenso al soltar saltar, en metros por segundo (un planeo, no una caída).
@export var flight_fall_speed: float = 4.0
## Distancia mínima al borde de la arena mientras vuela, en metros.
@export var flight_edge_margin: float = 2.0

@onready var _body: Player = get_parent() as Player


## Movimiento vertical durante Vuelo; devuelve true si tomó el frame (el
## llamador no aplica gravedad). El techo se mide SOBRE EL TERRENO: una Y
## fija enterraría al raider en una loma de un mapa y lo dejaría en el
## cielo en otro.
func tick() -> bool:
	var powerups := PowerUps.find_in(_body)
	if powerups == null or not powerups.has("flight") or _body.is_downed():
		return false
	var ceiling := _ground_height() + flight_ceiling
	if Input.is_action_pressed(_body.slot_action(&"jump")) and _body.global_position.y < ceiling:
		_body.velocity.y = flight_rise_speed
	elif _body.global_position.y >= ceiling:
		# Se queda en el techo en vez de rebotar.
		_body.velocity.y = minf(_body.velocity.y, 0.0)
	elif not _body.is_on_floor():
		_body.velocity.y = -flight_fall_speed
	else:
		_body.velocity.y = 0.0
	# El borde de la arena es un muro para quien camina y nada para quien
	# vuela: sin esto se podría salir volando sobre el vacío.
	var limit := _arena_limit()
	if limit > 0.0:
		_body.global_position.x = clampf(_body.global_position.x, -limit, limit)
		_body.global_position.z = clampf(_body.global_position.z, -limit, limit)
	return true


## Al terminar Vuelo: si el raider quedó sobre una celda bloqueada (el único
## lugar garantizado como NO caminable, y el que vigila el probe), lo baja
## al punto caminable más cercano.
func end_flight() -> void:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	if bounds == null or not bounds.has_method("is_walkable"):
		return
	var here := Vector2(_body.global_position.x, _body.global_position.z)
	if bool(bounds.call("is_walkable", here)):
		return
	var best := here
	var best_distance := INF
	if bounds.has_method("random_walkable_point"):
		for attempt in LANDING_SAMPLES:
			var candidate: Variant = bounds.call("random_walkable_point")
			if candidate is not Vector2:
				continue
			var distance := (candidate as Vector2).distance_squared_to(here)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	if best == here:
		return
	_body.global_position.x = best.x
	_body.global_position.z = best.y
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		_body.global_position.y = terrain.height_at(best.x, best.y) + LANDING_CLEARANCE
	_body.velocity = Vector3.ZERO
	print("Flight landing: p%d moved to walkable ground" % _body.player_index)


## Altura del terreno bajo el raider, para el techo.
func _ground_height() -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(_body.global_position.x, _body.global_position.z) \
			if terrain != null else 0.0


## Media extensión a la que se limita el vuelo, o 0 si la arena no la publica.
func _arena_limit() -> float:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	if bounds == null:
		return 0.0
	var extent: Variant = bounds.get("arena_half_extent")
	if extent is not float and extent is not int:
		return 0.0
	return float(extent) - flight_edge_margin
