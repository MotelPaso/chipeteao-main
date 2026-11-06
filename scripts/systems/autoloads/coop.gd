extends Node
## Autoload "Coop": configuración de la sesión de co-op local y cada ayudante
## que el resto del juego necesita para no suponer que "el jugador" es un
## solo nodo.
##
## - Sesión: player_count (1-4), un dispositivo por espacio (el espacio 0 es
##   teclado+mouse por defecto; los demás son ids de control) y un id de
##   CharacterCatalog por espacio. Lo configura el lobby de la pantalla de
##   selección; sobrevive a cambios de escena y a RunState.reset() igual que
##   GameConfig (Reintentar repite la misma party).
## - Entrada: en co-op cada espacio tiene su propio set de acciones del
##   InputMap ("p<slot>_move_left", etc.) atado SOLO a su dispositivo, así
##   cuatro personas pueden moverse a la vez sin pisarse. En solitario se
##   usan las acciones del proyecto (que además aceptan cualquier control,
##   así una persona puede jugar con control O teclado).
## - Consultas: jugador vivo más cercano o al azar, cantidad de vivos y una
##   foto del grupo por tick (el mismo truco para no reservar memoria que usa
##   EnemyBase con la horda). "Vivo" es "en el grupo player": un jugador
##   derribado sale del grupo hasta que lo reanimen, así todo sistema que
##   usa grupos (persecución enemiga, imán de gemas, interactuables) ignora
##   los cuerpos derribados sin hacer nada.

const MAX_PLAYERS: int = 4
## Dispositivo centinela del espacio de teclado+mouse.
const KEYBOARD_DEVICE: int = -1

## Acciones base que se clonan por espacio en co-op (deben existir en
## project.godot).
const BASE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"sprint", &"interact",
	&"camera_mode", &"camera_zoom_in", &"camera_zoom_out",
	&"map_overlay",
]

## Zona muerta del stick derecho (0-1), compartida por toda cámara con control.
const LOOK_DEADZONE: float = 0.18
## Radianes por segundo de giro con el stick a fondo (antes de la
## sensibilidad del usuario).
const LOOK_SPEED: float = 2.6

## Botones del control (nombres de Xbox): A salta, X corre/derrapa,
## Y interactúa.
const PAD_JUMP_BUTTON := JOY_BUTTON_A
const PAD_SPRINT_BUTTON := JOY_BUTTON_X
const PAD_INTERACT_BUTTON := JOY_BUTTON_Y
## El equivalente de Tab en el control: Back/Select, donde todo juego pone
## el mapa.
const PAD_MAP_BUTTON := JOY_BUTTON_BACK

var player_count: int = 1
## Dispositivo por espacio: KEYBOARD_DEVICE o un id de control.
var devices: Array[int] = [KEYBOARD_DEVICE]
## Id de CharacterCatalog por espacio; el espacio 0 copia
## GameConfig.selected_character_id.
var character_ids: Array[String] = []

## Foto del grupo "player" por tick de física (ver la de enemigos en
## EnemyBase): una horda de 200 pregunta por el jugador más cercano en cada
## tick, así el array del grupo se arma una vez por tick y no por enemigo.
var _players_snapshot: Array[Node3D] = []
var _players_snapshot_frame: int = -1


func is_coop() -> bool:
	return player_count > 1


## La llama el lobby de selección justo antes de empezar una partida (y una
## vez con count 1 para volver a solitario). Rearma las acciones por espacio.
func configure(count: int, slot_devices: Array[int], slot_characters: Array[String]) -> void:
	player_count = clampi(count, 1, MAX_PLAYERS)
	# Se arma espacio por espacio, NO con resize(): un Array[int] rellena con
	# 0, y 0 es el id del PRIMER control conectado, no el centinela del
	# teclado; un espacio sin dispositivo debe caer al teclado.
	var resolved: Array[int] = []
	resolved.resize(player_count)
	for slot: int in player_count:
		resolved[slot] = slot_devices[slot] if slot < slot_devices.size() else KEYBOARD_DEVICE
	devices = resolved
	character_ids = slot_characters.duplicate()
	character_ids.resize(player_count)
	invalidate_players()
	if player_count > 0 and not character_ids[0].is_empty():
		GameConfig.selected_character_id = character_ids[0]
	_rebuild_slot_actions()


## Id de personaje con que aparece un espacio; los vacíos usan la selección
## de solitario (espacio 0) o el valor por defecto del catálogo.
func character_for_slot(slot: int) -> String:
	if slot < character_ids.size() and not character_ids[slot].is_empty():
		return character_ids[slot]
	return GameConfig.selected_character_id


func device_for_slot(slot: int) -> int:
	return devices[slot] if slot < devices.size() else KEYBOARD_DEVICE


## Nombre de acción que debe leer un espacio. En solitario (y para un
## espacio fuera de rango) se usa la acción del proyecto, así siguen
## funcionando los atajos existentes y los eventos de cualquier control.
func action(slot: int, base: StringName) -> StringName:
	if not is_coop() or slot >= player_count:
		return base
	return StringName("p%d_%s" % [slot, base])


## Vector de mirada del stick derecho para el dispositivo de un espacio, con
## zona muerta, en [-1, 1] por eje. El espacio de teclado (y el solitario)
## acepta también CUALQUIER control conectado.
func look_vector(slot: int) -> Vector2:
	var device := device_for_slot(slot)
	if device != KEYBOARD_DEVICE:
		return _pad_look(device)
	if is_coop():
		# En co-op el espacio de teclado es dueño del mouse; los controles son
		# de los demás.
		return Vector2.ZERO
	var best := Vector2.ZERO
	for pad: int in Input.get_connected_joypads():
		var candidate := _pad_look(pad)
		if candidate.length_squared() > best.length_squared():
			best = candidate
	return best


func _pad_look(device: int) -> Vector2:
	var raw := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if raw.length() < LOOK_DEADZONE:
		return Vector2.ZERO
	# Reescala para que el movimiento empiece en cero justo pasada la zona muerta.
	return raw.normalized() * minf((raw.length() - LOOK_DEADZONE) / (1.0 - LOOK_DEADZONE), 1.0)


# --- Consultas de party (la respuesta a "¿qué jugador?" de todo sistema) -----

## Jugador VIVO más cercano a `from`, o null si nadie está en pie. Reemplaza
## a get_first_node_in_group("player") en todo uso por posición
## (persecución enemiga, imán de gemas, anillos de spawn).
func nearest_player(tree: SceneTree, from: Vector3) -> Node3D:
	var nearest: Node3D = null
	var best := INF
	for player: Node3D in _players_this_tick(tree):
		if not _is_standing(player):
			continue
		var dist := from.distance_squared_to(player.global_position)
		if dist < best:
			best = dist
			nearest = player
	return nearest


## Un jugador vivo al azar, uniforme (anclas de anillo de spawn), o null.
## Orden del RNG: un pick_random por llamada.
func random_player(tree: SceneTree) -> Node3D:
	var alive: Array[Node3D] = alive_players(tree)
	return alive.pick_random() if not alive.is_empty() else null


func alive_players(tree: SceneTree) -> Array[Node3D]:
	var alive: Array[Node3D] = []
	for player: Node3D in _players_this_tick(tree):
		if _is_standing(player):
			alive.append(player)
	return alive


func alive_player_count(tree: SceneTree) -> int:
	return alive_players(tree).size()


## Tira la foto por tick. Llámala cuando la party cambie fuera del borde
## normal del tick (un espacio derribado o reanimado, una sesión nueva).
func invalidate_players() -> void:
	_players_snapshot_frame = -1
	_players_snapshot.clear()


## Quien lee la foto vuelve a revisar el grupo en vez de confiar en la
## caché: este archivo promete que un raider derribado sale del grupo, y una
## foto vieja rompería esa promesa justo en el frame en que alguien cae.
static func _is_standing(player: Node3D) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() \
			and player.is_in_group(&"player")


func _players_this_tick(tree: SceneTree) -> Array[Node3D]:
	var frame := Engine.get_physics_frames()
	if frame != _players_snapshot_frame:
		_players_snapshot_frame = frame
		_players_snapshot.clear()
		for node: Node in tree.get_nodes_in_group(&"player"):
			var player := node as Node3D
			if player != null:
				_players_snapshot.append(player)
	return _players_snapshot


# --- Acciones del InputMap por espacio --------------------------------------

## (Re)crea "p<slot>_<acción>" para cada espacio de co-op, atada solo a su
## dispositivo: los de teclado clonan los eventos de teclado del proyecto y
## los de control reciben stick+botones fijados a su id. Primero se borran
## las acciones viejas, así cambiar dispositivos entre partidas queda limpio.
func _rebuild_slot_actions() -> void:
	_clear_slot_actions()
	if not is_coop():
		return
	for slot: int in player_count:
		var device := device_for_slot(slot)
		for base: StringName in BASE_ACTIONS:
			var slot_action := action(slot, base)
			InputMap.add_action(slot_action, 0.5)
			if device == KEYBOARD_DEVICE:
				for event: InputEvent in InputMap.action_get_events(base):
					if event is InputEventKey or event is InputEventMouseButton:
						InputMap.action_add_event(slot_action, event.duplicate())
			else:
				for event: InputEvent in _pad_events_for(base, device):
					InputMap.action_add_event(slot_action, event)


func _clear_slot_actions() -> void:
	for slot: int in MAX_PLAYERS:
		for base: StringName in BASE_ACTIONS:
			var slot_action := StringName("p%d_%s" % [slot, base])
			if InputMap.has_action(slot_action):
				InputMap.erase_action(slot_action)


## Eventos de control para una acción base, fijados a `device`: stick
## izquierdo para moverse y botones para el resto (como los atajos de
## cualquier control de project.godot).
func _pad_events_for(base: StringName, device: int) -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	match base:
		&"move_forward":
			events.append(_axis_event(device, JOY_AXIS_LEFT_Y, -1.0))
		&"move_back":
			events.append(_axis_event(device, JOY_AXIS_LEFT_Y, 1.0))
		&"move_left":
			events.append(_axis_event(device, JOY_AXIS_LEFT_X, -1.0))
		&"move_right":
			events.append(_axis_event(device, JOY_AXIS_LEFT_X, 1.0))
		&"jump":
			events.append(_button_event(device, PAD_JUMP_BUTTON))
		&"sprint":
			events.append(_button_event(device, PAD_SPRINT_BUTTON))
			events.append(_button_event(device, JOY_BUTTON_LEFT_SHOULDER))
		&"interact":
			events.append(_button_event(device, PAD_INTERACT_BUTTON))
		&"map_overlay":
			events.append(_button_event(device, PAD_MAP_BUTTON))
		&"camera_mode":
			events.append(_button_event(device, JOY_BUTTON_RIGHT_STICK))
		&"camera_zoom_in":
			events.append(_button_event(device, JOY_BUTTON_DPAD_UP))
		&"camera_zoom_out":
			events.append(_button_event(device, JOY_BUTTON_DPAD_DOWN))
	return events


func _axis_event(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


func _button_event(device: int, button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	return event
