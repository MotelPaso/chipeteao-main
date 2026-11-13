class_name CoopLobby
extends VBoxContainer
## Lobby de co-op local del selector de personaje (CoopLobby.tscn, 1-4
## jugadores): la fila "Jugadores" con los botones de cantidad y el aviso de
## controles, y la fila de slots, un botón por jugador con su raider; el
## resaltado es el slot al que asigna el próximo clic en una carta. J1 juega
## con teclado y mouse y cada jugador extra necesita su propio control, así
## que la cantidad se valida contra los controles conectados y se achica sola
## si uno se desconecta. Con 1 jugador todo es el flujo solo.

## Cambió la cantidad de jugadores o el raider de un slot: el selector
## refresca las cartas y el texto de Iniciar.
signal party_changed
## Se rehicieron los botones de slot: el selector vuelve a cablear el foco.
signal slots_rebuilt

@export_group("Botones de cantidad")
## Escala de un botón de cantidad al pasar el mouse.
@export var count_hover_grow: float = 1.06
## Texto y borde de la cantidad elegida.
@export var count_selected_color: Color = UiTheme.ACCENT_AMBER
## Texto de una cantidad que se puede elegir.
@export var count_usable_color: Color = UiTheme.TEXT_NORMAL
## Texto de una cantidad que pide más controles de los conectados.
@export var count_unusable_color: Color = UiTheme.TEXT_FAINT
## Borde de una cantidad que se puede elegir.
@export var count_usable_border: Color = UiTheme.BORDER_DIM
## Borde de una cantidad sin controles suficientes.
@export var count_unusable_border: Color = UiTheme.BORDER_LOCKED
## Grosor del borde de la cantidad elegida, en píxeles.
@export var count_selected_border_width: int = 3
## Grosor del borde de las demás cantidades, en píxeles.
@export var count_idle_border_width: int = 2

@export_group("Botones de slot")
## Tamaño mínimo (píxeles) de cada botón de slot.
@export var slot_button_size: Vector2 = Vector2(150, 36)
## Tamaño de fuente del texto de un slot.
@export var slot_font_size: int = 13
## Escala de un botón de slot al pasar el mouse.
@export var slot_hover_grow: float = 1.05
## Cuánto se aclara el tinte del raider para el texto del slot en edición (0-1).
@export_range(0.0, 1.0) var slot_editing_lighten: float = 0.35
## Color del texto de los slots que no se están editando.
@export var slot_idle_color: Color = UiTheme.TEXT_NORMAL
## Color del borde de los slots que no se están editando.
@export var slot_idle_border: Color = UiTheme.BORDER_DIM
## Grosor del borde del slot en edición, en píxeles.
@export var slot_editing_border_width: int = 3
## Grosor del borde de los demás slots, en píxeles.
@export var slot_idle_border_width: int = 2

@export_group("Textos")
## Aviso cuando faltan controles (%d = controles que faltan, %d = jugadores).
@export var missing_pads_format: String = "Conecta %d control(es) para %d jugadores"
## Aviso con 3-4 jugadores (%d = último jugador, %d = controles conectados).
@export var party_hint_format: String = "J1 teclado+mouse · J2-J%d control · %d control(es)"
## Aviso con 2 jugadores (%d = controles conectados).
@export var duo_hint_format: String = "J1 teclado+mouse · J2 control · %d control(es)"
## Aviso en solo con controles conectados (%d = controles).
@export var pads_hint_format: String = "%d control(es) conectado(s)"
## Aviso en solo sin controles.
@export var no_pads_hint: String = "Conecta controles para co-op local"
## Texto de un botón de slot (%d = jugador, %s = raider).
@export var slot_text_format: String = "J%d: %s"
## Aviso al presionar Iniciar si se desconectó un control y queda uno solo.
@export var lost_pad_solo_text: String = "Se desconectó un control — vuelves al modo solo"
## Mismo aviso cuando sigue habiendo grupo (%d = jugadores que quedan).
@export var lost_pad_party_format: String = "Se desconectó un control — ahora son %d jugadores"

## Tamaño del grupo; 1 = el flujo solo.
var _count: int = 1
## Id de personaje por slot (el slot 0 refleja GameConfig.selected_character_id).
var _characters: Array[String] = []
## Slot al que asigna el próximo clic en una carta (avanza solo).
var _editing_slot: int = 0
var _slot_buttons: Array[Button] = []
## Suscripción a Input guardada para soltarla en _exit_tree (Input sobrevive
## a esta escena).
var _on_pads_changed: Callable

@onready var _players_row: HBoxContainer = %PlayersRow
@onready var _slot_row: HBoxContainer = %SlotRow
@onready var _hint: Label = %CoopHint
## Un botón por cantidad de jugadores, de 1 a Coop.MAX_PLAYERS.
@onready var _count_buttons: Array[Button] = [%Count1 as Button, %Count2 as Button,
		%Count3 as Button, %Count4 as Button]


func _ready() -> void:
	if _count_buttons.size() != Coop.MAX_PLAYERS:
		push_warning("CoopLobby: %d count buttons for Coop.MAX_PLAYERS=%d"
				% [_count_buttons.size(), Coop.MAX_PLAYERS])
	for i in _count_buttons.size():
		var button := _count_buttons[i]
		button.pressed.connect(_on_count_pressed.bind(i + 1))
		UiTheme.attach_motion(button, count_hover_grow)
	_on_pads_changed = func(_device: int, _connected: bool) -> void: _refresh_rows()
	Input.joy_connection_changed.connect(_on_pads_changed)
	_refresh_rows()


func _exit_tree() -> void:
	if _on_pads_changed.is_valid() \
			and Input.joy_connection_changed.is_connected(_on_pads_changed):
		Input.joy_connection_changed.disconnect(_on_pads_changed)


## Jugadores del grupo (1 = solo).
func party_size() -> int:
	return _count


## True con 2 jugadores o más.
func is_party() -> bool:
	return _count > 1


## True si algún slot del grupo eligió ese raider.
func has_character(character_id: String) -> bool:
	return _characters.has(character_id)


## Slots (desde 0) que eligieron ese raider.
func owner_slots(character_id: String) -> Array[int]:
	var slots: Array[int] = []
	for slot in _count:
		if _characters[slot] == character_id:
			slots.append(slot)
	return slots


## Raider del slot que se está editando (el que cambia el próximo clic en una
## carta); en solo, el raider elegido.
func editing_character_id() -> String:
	if _characters.is_empty():
		return GameConfig.selected_character_id
	return _characters[clampi(_editing_slot, 0, _characters.size() - 1)]


## Asigna el raider al slot en edición y avanza al siguiente, así cuatro
## clics arman un grupo completo. El slot 0 también es la elección de
## GameConfig.
func assign(character_id: String) -> void:
	_characters[_editing_slot] = character_id
	if _editing_slot == 0:
		GameConfig.selected_character_id = character_id
	_editing_slot = (_editing_slot + 1) % _count
	_refresh_slot_row()


## Recupera el último grupo de Coop (Reintentar o volver de una partida lo
## repite); los controles pueden haber cambiado, así que la cantidad se
## vuelve a validar.
func restore_session() -> void:
	_characters = Coop.character_ids.duplicate()
	_set_count(mini(Coop.player_count, _max_supported_players()), true)


## A dónde va "arriba" desde la fila superior de cartas: el slot en edición
## en co-op; si no, el botón de la cantidad elegida.
func focus_target() -> Control:
	if _slot_row.visible and not _slot_buttons.is_empty():
		return _slot_buttons[clampi(_editing_slot, 0, _slot_buttons.size() - 1)]
	if _count_buttons.is_empty():
		return null
	return _count_buttons[clampi(_count - 1, 0, _count_buttons.size() - 1)]


## Las dos filas, para la entrada escalonada del selector.
func entrance_rows() -> Array[Control]:
	return [_players_row, _slot_row]


## Congela el grupo en el autoload Coop: slot 0 con teclado y mouse, el resto
## un control conectado cada uno (en el orden del sistema); en solo se
## configura 1, así una sesión co-op anterior no se cuela. Normalmente
## joy_connection_changed ya achicó el grupo, pero un control puede morir
## entre esa señal y este clic: si faltan controles, achica el grupo, lo
## avisa y devuelve false para que el jugador lo vea antes de confirmar.
func commit_party() -> bool:
	var pads := Input.get_connected_joypads()
	var usable := mini(_count, pads.size() + 1)
	if usable < _count:
		_set_count(usable, true)
		_hint.text = lost_pad_solo_text if usable <= 1 \
				else lost_pad_party_format % usable
		return false
	var slot_devices: Array[int] = [Coop.KEYBOARD_DEVICE]
	for extra in range(1, _count):
		slot_devices.append(pads[extra - 1])
	var slot_characters: Array[String] = []
	if _count > 1:
		for i in _count:
			slot_characters.append(_characters[i])
	else:
		slot_characters.append(GameConfig.selected_character_id)
	Coop.configure(_count, slot_devices, slot_characters)
	return true


## J1 juega con teclado y mouse (o con cualquier control en solo); cada
## jugador extra necesita su propio control conectado.
func _max_supported_players() -> int:
	return mini(Input.get_connected_joypads().size() + 1, Coop.MAX_PLAYERS)


func _on_count_pressed(count: int) -> void:
	if count > _max_supported_players():
		UiTheme.reject(_count_buttons[count - 1])
		# El número es lo que FALTA, no el total del grupo: con un control ya
		# conectado, un grupo de 4 necesita dos más, no tres.
		var missing := maxi(count - 1 - Input.get_connected_joypads().size(), 1)
		_hint.text = missing_pads_format % [missing, count]
		return
	_set_count(count)


func _set_count(count: int, silent: bool = false) -> void:
	_count = clampi(count, 1, Coop.MAX_PLAYERS)
	# Llena los slots nuevos con la elección solo actual y limpia ids viejos
	# o bloqueados.
	_characters.resize(_count)
	for i in _count:
		# by_id, nunca by_id_or_default: un id que salió del catálogo hay que
		# REEMPLAZARLO aquí, y la fila de respaldo reportaría el desbloqueo del
		# personaje por DEFECTO y dejaría pasar el id basura a Coop.
		var row := CharacterCatalog.by_id(_characters[i])
		if row.is_empty() or not SaveData.is_unlocked(String(row.id)):
			_characters[i] = String(CharacterCatalog.by_id_or_default(
					GameConfig.selected_character_id).id)
	_editing_slot = mini(_editing_slot, _count - 1)
	if not silent:
		Sfx.play(&"card_pick")
	_refresh_rows()
	party_changed.emit()


func _refresh_rows() -> void:
	var supported := _max_supported_players()
	if _count > supported:
		# Se desconectó un control en el lobby: vuelve a lo que funciona.
		_set_count(supported, true)
		return
	for i in _count_buttons.size():
		var count := i + 1
		var selected := count == _count
		var usable := count <= supported
		_count_buttons[i].add_theme_color_override("font_color",
				count_selected_color if selected
				else (count_usable_color if usable else count_unusable_color))
		UiTheme.style_card(_count_buttons[i],
				count_selected_color if selected
				else (count_usable_border if usable else count_unusable_border),
				count_selected_border_width if selected else count_idle_border_width,
				selected)
	var pads := Input.get_connected_joypads().size()
	if _count > 2:
		_hint.text = party_hint_format % [_count, pads]
	elif _count == 2:
		# "J2-J2" se lee como un rango vacío: con dos jugadores se nombra el
		# único slot de control.
		_hint.text = duo_hint_format % pads
	else:
		_hint.text = (pads_hint_format % pads) if pads > 0 else no_pads_hint
	_refresh_slot_row()


## Rehace los botones de slot. Un botón de slot rehace esta fila desde su
## propio `pressed`, así que el dueño del foco suele ser uno de los botones
## por morir: se recuerda y el foco pasa a la fila nueva, o la navegación con
## control quedaría sin salida. remove_child antes de queue_free porque
## liberar es diferido: si no, los botones viejos ocupan lugar el resto del
## frame.
func _refresh_slot_row() -> void:
	_slot_row.visible = _count > 1
	var focus_owner := get_viewport().gui_get_focus_owner()
	var had_focus := focus_owner != null and _slot_buttons.has(focus_owner)
	for button: Button in _slot_buttons:
		_slot_row.remove_child(button)
		button.queue_free()
	_slot_buttons.clear()
	if _count <= 1:
		slots_rebuilt.emit()
		return
	for slot in _count:
		var slot_button := Button.new()
		slot_button.custom_minimum_size = slot_button_size
		var character := CharacterCatalog.by_id_or_default(_characters[slot])
		slot_button.text = slot_text_format % [slot + 1, String(character.display_name)]
		slot_button.add_theme_font_size_override("font_size", slot_font_size)
		slot_button.pressed.connect(func() -> void:
			_editing_slot = slot
			Sfx.play(&"card_pick")
			_refresh_slot_row()
			party_changed.emit())
		UiTheme.attach_motion(slot_button, slot_hover_grow)
		var tint := Color(character.tint)
		var editing := slot == _editing_slot
		slot_button.add_theme_color_override("font_color",
				tint.lightened(slot_editing_lighten) if editing else slot_idle_color)
		UiTheme.style_card(slot_button, tint if editing else slot_idle_border,
				slot_editing_border_width if editing else slot_idle_border_width, editing)
		_slot_row.add_child(slot_button)
		_slot_buttons.append(slot_button)
	if had_focus:
		_slot_buttons[clampi(_editing_slot, 0, _slot_buttons.size() - 1)].grab_focus()
	slots_rebuilt.emit()
