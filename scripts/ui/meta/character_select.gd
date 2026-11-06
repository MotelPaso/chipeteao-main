extends Control
## Selector de personaje (GDD 5/7), la escena de entrada del juego: elige un
## raider (y en co-op local, el grupo) e Iniciar incursión carga Run.tscn.
## Las cartas salen de CharacterCatalog en tiempo de ejecución, así que un
## personaje nuevo es una fila del catálogo; la elección queda en el autoload
## GameConfig.
##
## Meta-progresión (GDD 8): SaveData controla el plantel. Las cartas
## bloqueadas se ven grises con un candado y su precio en esquirlas; con saldo
## suficiente, un clic convierte la carta en la confirmación "¿Desbloquear por
## N esquirlas? [Sí]" (un segundo clic cancela), y sin saldo la carta destella
## en rojo y se sacude. Toda partida empieza en el Bosque Hueco y recorre la
## lista de mapas, así que aquí solo se eligen el raider, el grupo y la
## Cacería diaria. El saldo de esquirlas va arriba a la derecha.
##
## Aspecto: todo sale de UiTheme (fondo de niebla animado, título espaciado
## que pulsa, cartas con brillo según su estado, botón principal destacado,
## entrada escalonada y ScreenFade en cada cambio de escena). El contenido de
## las cartas lo arma CardFactory; sus styleboxes de estado son
## UiTheme.style_card, el mismo aspecto que las cartas de mejora.
##
## Layout: título y subtítulo fijos arriba y la fila de botones abajo (el
## botón principal se alcanza con cualquier tamaño de ventana); el medio
## (co-op y cuadrícula) se desplaza, y la cuadrícula calcula sus columnas
## según el ancho de la ventana y el tamaño del plantel.

## Tamaño (píxeles) de cada carta: alcanza para la pasiva más larga del
## catálogo más dos líneas de descripción; la cuadrícula se desplaza.
const CARD_SIZE := Vector2(184, 244)
## Topes de líneas: cada bloque de texto de la carta se recorta con puntos
## suspensivos en vez de pasarse del borde. La pasiva cambia cómo se juega,
## así que tiene hasta cuatro líneas; la carta bloqueada usa un tope menor
## porque también lleva el precio y la pista. La descripción no tiene tope
## fijo: usa la altura que SOBRA y se recorta allí. El texto completo de ambas
## está siempre en el tooltip de la carta.
const PASSIVE_MAX_LINES := 4
const LOCKED_PASSIVE_MAX_LINES := 2
const UNLOCK_HINT_MAX_LINES := 2

## Tamaño (píxeles) de los botones de cantidad de jugadores del co-op.
const SEGMENT_BUTTON_SIZE := Vector2(64, 36)
## Las cartas no elegidas quedan algo atenuadas para que la elegida se lea de
## un vistazo.
const UNSELECTED_DIM := Color(0.8, 0.82, 0.86)
## Margen lateral (píxeles) del MarginContainer Layout de la escena, para que
## el cálculo de columnas mida el ancho real de la cuadrícula. Debe coincidir
## con margin_left/margin_right de Layout en CharacterSelect.tscn.
const LAYOUT_SIDE_MARGIN := 24.0
## La cuadrícula nunca baja de estas columnas y apunta a no pasar de estas
## filas antes de ensancharse (una más alta se desplaza).
const GRID_MIN_COLUMNS := 4
const GRID_TARGET_ROWS := 3

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _cards_grid: GridContainer = %CardsGrid
## HFlowContainer: los botones bajan a una segunda línea en una ventana
## angosta en vez de salirse.
@onready var _button_row: HFlowContainer = %ButtonRow
@onready var _start_button: Button = %StartButton
@onready var _quests_button: Button = %QuestsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _shards_label: Label = %ShardsLabel
@onready var _version_label: Label = %VersionLabel

## Botón de carta por id de personaje jugable, para restilizar la selección.
var _cards_by_id: Dictionary[String, Button] = {}
## Id del personaje cuya carta muestra la confirmación de desbloqueo.
var _pending_unlock_id: String = ""
var _title_tween: Tween = null
var _entrance_tween: Tween = null
## Suscripciones a autoloads e Input guardadas como campos para que
## _exit_tree las suelte a mano (sobreviven a esta escena; las de nodo a
## nodo no).
var _on_shards_changed: Callable
var _on_pads_changed: Callable

## --- Estado del lobby co-op (co-op local, 1-4 jugadores) -----------------
## Tamaño del grupo elegido; 1 = el flujo solo.
var _coop_count: int = 1
## Id de personaje por slot (el índice 0 refleja
## GameConfig.selected_character_id).
var _coop_characters: Array[String] = []
## Slot al que asigna el próximo clic en una carta (avanza solo).
var _editing_slot: int = 0
var _coop_buttons: Array[Button] = []
var _slot_buttons: Array[Button] = []
var _coop_row: HBoxContainer = null
var _slot_row: HBoxContainer = null
var _coop_hint: Label = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_coop_rows()
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.pressed.connect(_on_card_pressed.bind(String(character.id)))
		UiTheme.attach_motion(card, 1.03)
		card.mouse_exited.connect(_resettle_card.bind(String(character.id)))
		_keep_pivot_centered(card)
		_cards_grid.add_child(card)
		_cards_by_id[String(character.id)] = card
	_update_grid_columns()
	resized.connect(_update_grid_columns)
	_apply_chrome()
	# attach_motion es idempotente (gana la primera llamada): el botón
	# principal reclama su crecer/aplastar más fuerte ANTES de que
	# style_button ponga el de por defecto.
	UiTheme.attach_motion(_start_button, 1.05, 0.93)
	UiTheme.style_button(_start_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_quests_button)
	UiTheme.style_button(_settings_button)
	_start_button.pressed.connect(_on_start_pressed)
	_quests_button.pressed.connect(_on_quests_pressed)
	_build_extra_buttons()
	# Indicación de botones en la esquina inferior izquierda, que está libre
	# (la fila de botones va centrada y la versión abajo a la derecha). Va
	# ANTES del panel de ajustes en el árbol para que su atenuado la cubra.
	var hints := InputHints.build([["ui_accept", "Elegir"]])
	add_child(hints)
	move_child(hints, _settings_panel.get_index())
	hints.pin_bottom_left()
	# El SettingsPanel compartido (la misma escena que usa la pausa) cubre
	# toda la pantalla; al cerrarse, el foco vuelve a Iniciar.
	_settings_button.pressed.connect(_settings_panel.open)
	_settings_panel.closed.connect(func() -> void: _start_button.grab_focus())
	_on_shards_changed = func(_balance: int) -> void: _refresh_shards()
	SaveData.shards_changed.connect(_on_shards_changed)
	_refresh_shards()
	_version_label.text = "v%s" % String(
			ProjectSettings.get_setting("application/config/version", "0.0.0"))
	# Reabrir en la misma sesión conserva la elección anterior; un id
	# desconocido o bloqueado vuelve al personaje por defecto.
	var remembered := String(
			CharacterCatalog.by_id_or_default(GameConfig.selected_character_id).id)
	if not SaveData.is_unlocked(remembered):
		remembered = CharacterCatalog.DEFAULT_ID
	_select(remembered)
	# Recuerda el último grupo; los controles pueden haberse conectado o
	# desconectado desde entonces, así que la cantidad se vuelve a validar.
	_restore_coop_session()
	_start_button.grab_focus()
	_play_entrance()


## Las suscripciones a autoloads y a Input sobreviven a esta escena, así que
## se sueltan a mano; lo demás muere con el árbol de nodos.
func _exit_tree() -> void:
	if _on_shards_changed.is_valid() \
			and SaveData.shards_changed.is_connected(_on_shards_changed):
		SaveData.shards_changed.disconnect(_on_shards_changed)
	if _on_pads_changed.is_valid() \
			and Input.joy_connection_changed.is_connected(_on_pads_changed):
		Input.joy_connection_changed.disconnect(_on_pads_changed)


## --- Tamaño de la cuadrícula (el plantel crece con filas del catálogo) ---

## Las columnas salen del tamaño del plantel (apuntando a GRID_TARGET_ROWS
## filas), acotadas por lo que cabe en la ventana: agregar un raider ensancha
## la cuadrícula en vez de empujar filas (y el botón principal) fuera.
func _update_grid_columns() -> void:
	var separation := float(_cards_grid.get_theme_constant(&"h_separation"))
	var available := get_viewport_rect().size.x - LAYOUT_SIDE_MARGIN * 2.0
	var fits := maxi(1, floori((available + separation) / (CARD_SIZE.x + separation)))
	var wanted := maxi(GRID_MIN_COLUMNS, ceili(
			float(CharacterCatalog.CHARACTER_LIBRARY.size()) / float(GRID_TARGET_ROWS)))
	var columns := clampi(wanted, 1, fits)
	if _cards_grid.columns != columns:
		_cards_grid.columns = columns
	_link_focus()


## Las cartas escalan desde su centro, pero su tamaño solo se conoce después
## del primer layout; seguir `resized` mantiene el pivote centrado en vez de
## tomarlo una vez al construir, cuando todavía es cero.
func _keep_pivot_centered(control: Control) -> void:
	control.resized.connect(func() -> void:
		control.pivot_offset = control.size * 0.5)


## --- Lobby co-op (fila de jugadores y personaje por slot) ----------------

func _build_coop_rows() -> void:
	var vbox := _cards_grid.get_parent()
	var grid_index := _cards_grid.get_index()
	_coop_row = HBoxContainer.new()
	_coop_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_coop_row.add_theme_constant_override("separation", 8)
	var tag := CardFactory.label("Jugadores", 14, UiTheme.TEXT_DIM)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coop_row.add_child(tag)
	for count in range(1, Coop.MAX_PLAYERS + 1):
		var count_button := Button.new()
		count_button.custom_minimum_size = SEGMENT_BUTTON_SIZE
		count_button.text = str(count)
		count_button.add_theme_font_size_override("font_size", 15)
		count_button.pressed.connect(_on_coop_count_pressed.bind(count))
		UiTheme.attach_motion(count_button, 1.06)
		_coop_row.add_child(count_button)
		_coop_buttons.append(count_button)
	_coop_hint = CardFactory.label("", 11, UiTheme.TEXT_FAINT)
	_coop_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coop_row.add_child(_coop_hint)
	vbox.add_child(_coop_row)
	vbox.move_child(_coop_row, grid_index)
	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.add_theme_constant_override("separation", 8)
	_slot_row.visible = false
	vbox.add_child(_slot_row)
	vbox.move_child(_slot_row, grid_index + 1)
	_on_pads_changed = func(_device: int, _connected: bool) -> void: _refresh_coop_rows()
	Input.joy_connection_changed.connect(_on_pads_changed)
	_refresh_coop_rows()


func _restore_coop_session() -> void:
	_coop_characters = Coop.character_ids.duplicate()
	_set_coop_count(mini(Coop.player_count, _max_supported_players()), true)


## J1 juega con teclado y mouse (o con cualquier control en solo); cada
## jugador extra necesita su propio control conectado.
func _max_supported_players() -> int:
	return mini(Input.get_connected_joypads().size() + 1, Coop.MAX_PLAYERS)


func _on_coop_count_pressed(count: int) -> void:
	if count > _max_supported_players():
		_reject_card(_coop_buttons[count - 1])
		# El número es lo que FALTA, no el total del grupo: con un control ya
		# conectado, un grupo de 4 necesita dos más, no tres.
		var missing := maxi(count - 1 - Input.get_connected_joypads().size(), 1)
		_coop_hint.text = "Conecta %d control(es) para %d jugadores" % [missing, count]
		_coop_hint.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
		return
	_set_coop_count(count)


func _set_coop_count(count: int, silent: bool = false) -> void:
	_coop_count = clampi(count, 1, Coop.MAX_PLAYERS)
	# Llena los slots nuevos con la elección solo actual y limpia ids viejos
	# o bloqueados.
	_coop_characters.resize(_coop_count)
	for i in _coop_count:
		# by_id, nunca by_id_or_default: un id que salió del catálogo hay que
		# REEMPLAZARLO aquí, y la fila de respaldo reportaría el desbloqueo
		# del personaje por DEFECTO y dejaría pasar el id basura a Coop.
		var row := CharacterCatalog.by_id(_coop_characters[i])
		if row.is_empty() or not SaveData.is_unlocked(String(row.id)):
			_coop_characters[i] = String(CharacterCatalog.by_id_or_default(
					GameConfig.selected_character_id).id)
	_editing_slot = mini(_editing_slot, _coop_count - 1)
	if not silent:
		Sfx.play(&"card_pick")
	_refresh_coop_rows()
	_refresh_all_cards()
	_refresh_start_button()


func _refresh_coop_rows() -> void:
	var supported := _max_supported_players()
	if _coop_count > supported:
		# Se desconectó un control en el lobby: vuelve a lo que funciona.
		_set_coop_count(supported, true)
		return
	for i in _coop_buttons.size():
		var count := i + 1
		var selected := count == _coop_count
		var usable := count <= supported
		_coop_buttons[i].add_theme_color_override("font_color",
				UiTheme.ACCENT_AMBER if selected
				else (UiTheme.TEXT_NORMAL if usable else UiTheme.TEXT_FAINT))
		UiTheme.style_card(_coop_buttons[i],
				UiTheme.ACCENT_AMBER if selected
				else (UiTheme.BORDER_DIM if usable else UiTheme.BORDER_LOCKED),
				3 if selected else 2, selected)
	var pads := Input.get_connected_joypads().size()
	if _coop_count > 2:
		_coop_hint.text = "J1 teclado+mouse · J2-J%d control · %d control(es)" \
				% [_coop_count, pads]
	elif _coop_count == 2:
		# "J2-J2" se lee como un rango vacío: con dos jugadores se nombra el
		# único slot de control.
		_coop_hint.text = "J1 teclado+mouse · J2 control · %d control(es)" % pads
	else:
		_coop_hint.text = ("%d control(es) conectado(s)" % pads) if pads > 0 \
				else "Conecta controles para co-op local"
	_coop_hint.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
	_refresh_slot_row()


## Un botón por slot del grupo con su raider asignado; el resaltado es el
## slot que configura el próximo clic en una carta.
func _refresh_slot_row() -> void:
	_slot_row.visible = _coop_count > 1
	# Un botón de slot reconstruye esta fila desde su propio `pressed`, así
	# que el dueño del foco suele ser uno de los botones por morir: se
	# recuerda y el foco pasa a la fila nueva, o la navegación con control
	# quedaría sin salida. remove_child antes de queue_free porque liberar es
	# diferido: si no, los botones viejos ocupan lugar el resto del frame.
	var focus_owner := get_viewport().gui_get_focus_owner()
	var had_focus := focus_owner != null and _slot_buttons.has(focus_owner)
	for button: Button in _slot_buttons:
		_slot_row.remove_child(button)
		button.queue_free()
	_slot_buttons.clear()
	if _coop_count <= 1:
		_link_focus()
		return
	for slot in _coop_count:
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(150, 36)
		var character := CharacterCatalog.by_id_or_default(_coop_characters[slot])
		slot_button.text = "J%d: %s" % [slot + 1, String(character.display_name)]
		slot_button.add_theme_font_size_override("font_size", 13)
		slot_button.pressed.connect(func() -> void:
			_editing_slot = slot
			Sfx.play(&"card_pick")
			_refresh_slot_row()
			_refresh_all_cards())
		UiTheme.attach_motion(slot_button, 1.05)
		var tint := Color(character.tint)
		var editing := slot == _editing_slot
		slot_button.add_theme_color_override("font_color",
				tint.lightened(0.35) if editing else UiTheme.TEXT_NORMAL)
		UiTheme.style_card(slot_button, tint if editing else UiTheme.BORDER_DIM,
				3 if editing else 2, editing)
		_slot_row.add_child(slot_button)
		_slot_buttons.append(slot_button)
	if had_focus:
		_slot_buttons[clampi(_editing_slot, 0, _slot_buttons.size() - 1)].grab_focus()
	_link_focus()


func _refresh_start_button() -> void:
	if _coop_count > 1:
		_start_button.text = "Iniciar incursión — %d jugadores" % _coop_count
	else:
		var picked := CharacterCatalog.by_id_or_default(GameConfig.selected_character_id)
		_start_button.text = "Iniciar incursión — %s" % String(picked.display_name)


## Tipografía del título, el subtítulo y las esquirlas, y el pulso lento de
## brillo del título (el movimiento dice "vivo", nunca "ocupado").
func _apply_chrome() -> void:
	UiTheme.style_title(_title_label, 52, UiTheme.ACCENT_AMBER, 10, 12)
	_subtitle_label.add_theme_font_override("font", UiTheme.spaced_font(2))
	_subtitle_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	UiTheme.style_badge(_shards_label, UiTheme.SHARD_BLUE,
			UiTheme.PANEL_BG, UiTheme.SHARD_BLUE.darkened(0.45))
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	_title_tween = create_tween().set_loops()
	_title_tween.tween_property(_title_label, "modulate",
			Color(1.14, 1.1, 1.0), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_tween.tween_property(_title_label, "modulate",
			Color.WHITE, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Aparición escalonada de las secciones al abrir (~0.4 s). Las secciones
## animan su propio modulate y las cartas el suyo, así que restilizar la
## selección nunca pelea con la entrada.
func _play_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	var sections: Array[Control] = [_title_label, _subtitle_label,
			_coop_row, _slot_row, _cards_grid, _button_row]
	# Oculta al instante, pero espera un frame al primer layout para que los
	# pivotes se centren en tamaños reales antes de escalar.
	for section: Control in sections:
		section.modulate.a = 0.0
	await get_tree().process_frame
	_entrance_tween = create_tween().set_parallel()
	_entrance_tween.set_ignore_time_scale(true)
	for i in sections.size():
		var section := sections[i]
		section.pivot_offset = section.size * 0.5
		section.scale = Vector2(0.96, 0.96)
		var delay := 0.05 * i
		_entrance_tween.tween_property(section, "modulate:a", 1.0, 0.22) \
				.set_delay(delay)
		_entrance_tween.tween_property(section, "scale", Vector2.ONE, 0.26) \
				.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_shards() -> void:
	_shards_label.text = UiTheme.SHARDS_BALANCE % SaveData.shards
	UiTheme.pop(_shards_label, 1.12, 0.22)


## La selección solo se ofrece para personajes desbloqueados
## (_on_card_pressed manda los clics bloqueados al flujo de desbloqueo). En
## co-op el clic asigna el raider al slot resaltado y avanza al siguiente,
## así cuatro clics arman un grupo completo.
func _select(character_id: String) -> void:
	if _coop_count > 1:
		_coop_characters[_editing_slot] = character_id
		if _editing_slot == 0:
			GameConfig.selected_character_id = character_id
		_editing_slot = (_editing_slot + 1) % _coop_count
		_refresh_slot_row()
	else:
		GameConfig.selected_character_id = character_id
	_refresh_all_cards()
	_refresh_start_button()


func _on_card_pressed(character_id: String) -> void:
	if SaveData.is_unlocked(character_id):
		_cancel_pending_unlock()
		_select(character_id)
		return
	if _pending_unlock_id == character_id:
		# Un segundo clic en la carta de confirmación cancela.
		_cancel_pending_unlock()
		_refresh_all_cards()
		return
	var cost := int(CharacterCatalog.by_id(character_id).get("unlock_cost", 0))
	if SaveData.can_afford(cost):
		_pending_unlock_id = character_id
		_refresh_all_cards()
	else:
		_reject_card(_cards_by_id[character_id],
				_rest_modulate(_card_selected(character_id)))


func _on_unlock_confirmed(character_id: String) -> void:
	_pending_unlock_id = ""
	if SaveData.purchase_character(character_id):
		Sfx.play(&"chest_open")  # fanfarria de desbloqueo: el sonido del cofre
		_select(character_id)  # también refresca todas las cartas
	else:
		_refresh_all_cards()
	# El «Sí» recién presionado se libera con el refresco y el foco se va con
	# él: se le pasa a la carta donde estaba el botón.
	var card := _cards_by_id.get(character_id) as Button
	if card != null:
		card.grab_focus()


func _cancel_pending_unlock() -> void:
	_pending_unlock_id = ""


func _on_start_pressed() -> void:
	# Un inicio normal nunca es la Cacería diaria (la marca su propio botón).
	GameConfig.daily_mode = false
	# Congela el grupo en el autoload Coop: slot 0 con teclado y mouse, el
	# resto un control conectado cada uno (en el orden del sistema). En solo
	# se configura 1, así una sesión co-op anterior no se cuela.
	var pads := Input.get_connected_joypads()
	# Normalmente joy_connection_changed achica el grupo, pero un control
	# puede morir entre esa señal y este clic: se revisa la lista AQUÍ en vez
	# de indexarla a ciegas, y el jugador ve el grupo más chico antes de
	# confirmarlo.
	var usable := mini(_coop_count, pads.size() + 1)
	if usable < _coop_count:
		_set_coop_count(usable, true)
		_coop_hint.text = "Se desconectó un control — vuelves al modo solo" if usable <= 1 \
				else "Se desconectó un control — ahora son %d jugadores" % usable
		_reject_card(_start_button)
		return
	var slot_devices: Array[int] = [Coop.KEYBOARD_DEVICE]
	for extra in range(1, _coop_count):
		slot_devices.append(pads[extra - 1])
	var slot_characters: Array[String] = []
	if _coop_count > 1:
		for i in _coop_count:
			slot_characters.append(_coop_characters[i])
	else:
		slot_characters.append(GameConfig.selected_character_id)
	Coop.configure(_coop_count, slot_devices, slot_characters)
	# Una sola escena para toda partida: Run.tscn es dueña del bloque
	# persistente y cambia la arena por etapa. Toda partida abre en el
	# bosque, así que no hay mapa que elegir.
	GameConfig.start_map_id = MapCatalog.DEFAULT_ID
	ScreenFade.transition(func() -> void:
		# RunState sigue corriendo mientras esta pantalla sin pausa está
		# arriba: la partida nueva parte de cero (igual que Reintentar).
		RunState.reset()
		get_tree().change_scene_to_file(ScenePaths.RUN))


func _on_quests_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().change_scene_to_file(ScenePaths.QUEST_LOG))


## Botones de las pantallas meta agregados en código junto a Misiones:
## Colección, Armería y Cacería diaria (con la mejor marca del día).
func _build_extra_buttons() -> void:
	var collection_button := _extra_button("Colección", func() -> void:
		ScreenFade.transition(func() -> void:
			get_tree().change_scene_to_file(ScenePaths.COLLECTION)))
	_button_row.move_child(collection_button, _quests_button.get_index() + 1)
	var armory_button := _extra_button("Armería", func() -> void:
		ScreenFade.transition(func() -> void:
			get_tree().change_scene_to_file(ScenePaths.RELIC_SHOP)))
	_button_row.move_child(armory_button, collection_button.get_index() + 1)
	var best := SaveData.stat("daily_best_" + _today_id())
	var daily_button := _extra_button(
			"Cacería diaria" if best <= 0 else "Cacería diaria — mejor %d" % best,
			_on_daily_pressed)
	UiTheme.style_button(daily_button, UiTheme.ACCENT_AMBER)
	_button_row.move_child(daily_button, _start_button.get_index() + 1)


func _extra_button(label_text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = _quests_button.custom_minimum_size
	button.add_theme_font_size_override("font_size", 20)
	UiTheme.style_button(button)
	button.pressed.connect(on_pressed)
	_button_row.add_child(button)
	return button


## --- Cacería diaria -------------------------------------------------------

func _today_id() -> String:
	return Time.get_date_string_from_system()


## Lanza la Cacería diaria con semilla: el personaje sale de la fecha (de
## forma determinista, entre los desbloqueados de ESTE jugador) y la semilla
## hace iguales el mundo, las cartas y las apariciones para todos ese día.
## Siempre solo. Se puede reintentar: queda la mejor marca del día.
func _on_daily_pressed() -> void:
	var date_id := _today_id()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(date_id)
	var characters: Array[String] = []
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		if SaveData.is_unlocked(String(character.id)):
			characters.append(String(character.id))
	if characters.is_empty():
		return
	GameConfig.daily_mode = true
	GameConfig.daily_seed = int(hash(date_id))
	GameConfig.daily_date = date_id
	GameConfig.selected_character_id = characters[rng.randi() % characters.size()]
	# La diaria empieza en el bosque como toda partida; lo que la hace igual
	# para todos ese día es la semilla, no el mapa.
	GameConfig.selected_map_id = MapCatalog.DEFAULT_ID
	GameConfig.start_map_id = MapCatalog.DEFAULT_ID
	Coop.configure(1, [Coop.KEYBOARD_DEVICE] as Array[int],
			[GameConfig.selected_character_id] as Array[String])
	ScreenFade.transition(func() -> void:
		RunState.reset()
		get_tree().change_scene_to_file(ScenePaths.RUN))


## --- Contenido de las cartas (se rehace al cambiar bloqueo o selección) --

func _refresh_all_cards() -> void:
	for id: String in _cards_by_id:
		_populate_card(_cards_by_id[id], CharacterCatalog.by_id(id))
	_link_focus()


## --- Navegación con control y teclado -------------------------------------

## Vecinos de foco de la cuadrícula y de la fila de botones, cableados a
## mano. Con la búsqueda automática de Godot, ui_down desde una carta de las
## columnas 3+ cae en "Cacería diaria" o "Misiones" (quedan bajo esas
## columnas; Iniciar queda bajo las columnas 1-2) y desde ahí se atasca en
## "Armería": con control no se llegaría a Iniciar. Por eso:
##   - abajo desde una carta va a la carta de abajo, o a Iniciar al final de
##     la columna (pasando por el «Sí» si la carta pide desbloquear);
##   - arriba desde la fila superior va a la fila del grupo, sobre la
##     cuadrícula;
##   - la fila de botones va a izquierda y derecha, nunca abajo, y arriba
##     vuelve al raider elegido.
## Se vuelve a correr tras todo lo que rehace cartas, slots o columnas.
func _link_focus() -> void:
	var cards: Array[Button] = []
	for child: Node in _cards_grid.get_children():
		if child is Button:
			cards.append(child as Button)
	var columns := maxi(_cards_grid.columns, 1)
	var above_grid := _party_focus_target()
	for i in cards.size():
		var card := cards[i]
		var below: Control = cards[i + columns] if i + columns < cards.size() \
				else _start_button
		if i < columns and above_grid != null:
			card.focus_neighbor_top = card.get_path_to(above_grid)
		var yes := _inline_button(card)
		if yes == null:
			card.focus_neighbor_bottom = card.get_path_to(below)
			continue
		card.focus_neighbor_bottom = card.get_path_to(yes)
		yes.focus_neighbor_top = yes.get_path_to(card)
		yes.focus_neighbor_bottom = yes.get_path_to(below)
		yes.focus_neighbor_left = yes.get_path_to(yes)
		yes.focus_neighbor_right = yes.get_path_to(yes)
	var row: Array[Button] = []
	for child: Node in _button_row.get_children():
		if child is Button and (child as Button).visible:
			row.append(child as Button)
	var picked: Button = _cards_by_id.get(GameConfig.selected_character_id) as Button
	if picked == null and not cards.is_empty():
		picked = cards[0]
	for j in row.size():
		var button := row[j]
		if picked != null:
			button.focus_neighbor_top = button.get_path_to(picked)
		button.focus_neighbor_bottom = button.get_path_to(button)
		button.focus_neighbor_left = button.get_path_to(row[maxi(j - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(row[mini(j + 1, row.size() - 1)])


## A dónde va "arriba" desde la fila superior de cartas: el slot en edición
## en co-op; si no, el botón de cantidad de jugadores elegido.
func _party_focus_target() -> Control:
	if _slot_row != null and _slot_row.visible and not _slot_buttons.is_empty():
		return _slot_buttons[clampi(_editing_slot, 0, _slot_buttons.size() - 1)]
	if _coop_buttons.is_empty():
		return null
	return _coop_buttons[clampi(_coop_count - 1, 0, _coop_buttons.size() - 1)]


## El «Sí» que muestra una carta mientras pide desbloquear, o null.
func _inline_button(card: Button) -> Button:
	for node: Node in card.find_children("*", "Button", true, false):
		return node as Button
	return null


## El texto completo de la carta al pasar el mouse: la carta recorta la
## pasiva y la descripción para caber, el tooltip nunca.
func _card_tooltip(character: Dictionary) -> String:
	var lines: Array[String] = [
		"%s — %s" % [String(character.display_name), String(character.weapon_display_name)],
		String(character.passive_description),
	]
	var blurb := String(character.get("blurb", ""))
	if not blurb.is_empty():
		lines.append_array(["", blurb])
	if not SaveData.is_unlocked(String(character.id)):
		var price := UiTheme.SHARDS_AMOUNT % int(character.get("unlock_cost", 0))
		var hint := String(character.get("unlock_hint", ""))
		lines.append_array(["", price if hint.is_empty() else "%s, o %s" % [price, hint]])
	return "\n".join(lines)


## queue_free es diferido, así que la caja de contenido saliente seguiría
## ocupando lugar (apilada bajo la nueva) el resto del frame; sacarla antes
## hace de cada reconstrucción un cambio limpio aunque se haga clic rápido.
func _clear_card(card: Button) -> void:
	for child: Node in card.get_children():
		card.remove_child(child)
		child.queue_free()


func _populate_card(card: Button, character: Dictionary) -> void:
	_clear_card(card)
	card.tooltip_text = _card_tooltip(character)
	var character_id := String(character.id)
	if not SaveData.is_unlocked(character_id):
		if _pending_unlock_id == character_id:
			_populate_confirm_card(card, character)
		else:
			_populate_locked_card(card, character)
		_settle_card(card, _pending_unlock_id == character_id)
		return
	var box := CardFactory.card_box(card)
	box.add_child(CardFactory.portrait_swatch(Color(character.tint),
			String(character.display_name)))
	# Se envuelve, nunca se recorta: el nombre de un raider no se traduce ni
	# se acorta (GLOSARIO, regla 5). Dos líneas son mejor que puntos
	# suspensivos comiéndose un nombre propio.
	var name_label := CardFactory.label(
			String(character.display_name), 20, UiTheme.TEXT_BRIGHT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	box.add_child(CardFactory.label(
			String(character.weapon_display_name), 12, UiTheme.TEXT_DIM))
	# Los dos bloques de texto tienen tope: sin él, una pasiva larga empuja
	# la descripción fuera de la carta.
	var passive := CardFactory.label(
			String(character.passive_description), 12, Color(0.85, 0.78, 0.5))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passive.max_lines_visible = PASSIVE_MAX_LINES
	passive.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(passive)
	var blurb := CardFactory.label(String(character.blurb), 11, Color(0.6, 0.62, 0.68))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# La pasiva tiene prioridad; la descripción usa el espacio que sobra y se
	# recorta allí en vez de desbordar (sin max_lines_visible: con recorte, un
	# Label con ajuste de línea muestra las líneas que caben en su alto).
	blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blurb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(blurb)
	# Co-op: una carta se ve elegida si CUALQUIER slot la eligió, y muestra
	# cuáles ("J1 · J3") para ver el grupo de un vistazo.
	var selected := _card_selected(character_id)
	if _coop_count > 1 and selected:
		var owners: Array[String] = []
		for slot in _coop_count:
			if _coop_characters[slot] == character_id:
				owners.append(UiTheme.PLAYER_TAG % (slot + 1))
		box.add_child(CardFactory.label(" · ".join(owners), 11, UiTheme.ACCENT_AMBER))
	var tint := Color(character.tint)
	UiTheme.style_card(card, tint if selected else UiTheme.BORDER_DIM,
			3 if selected else 2, selected)
	_settle_card(card, selected)


## La única respuesta a "¿esta carta se ve elegida?", compartida por el
## repintado y por el movimiento de hover que restaura la pose de reposo.
func _card_selected(character_id: String) -> bool:
	if not SaveData.is_unlocked(character_id):
		return _pending_unlock_id == character_id
	if _coop_count > 1:
		return _coop_characters.has(character_id)
	return character_id == GameConfig.selected_character_id


func _rest_modulate(selected: bool) -> Color:
	return Color.WHITE if selected else UNSELECTED_DIM


## Movimiento de selección: la carta elegida sube un poco y se aclara
## mientras las demás se atenúan. Un tween por carta guardado en la
## metadata, para que los clics rápidos no apilen animaciones; es el único
## dueño de la pose de reposo, así que también cancela (y endereza) un
## vaivén de rechazo en curso.
func _settle_card(card: Button, selected: bool) -> void:
	card.pivot_offset = card.size * 0.5
	UiTheme.kill_meta_tween(card, &"ui_settle_tween")
	card.rotation_degrees = 0.0
	var tween := card.create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_parallel()
	tween.tween_property(card, "scale",
			Vector2.ONE * (1.035 if selected else 1.0), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate", _rest_modulate(selected), 0.16)
	card.set_meta(&"ui_settle_tween", tween)


## El movimiento de hover compartido de UiTheme siempre devuelve un botón a
## escala 1.0, lo que borraría la elevación de la carta elegida al salir el
## mouse. Reasentarla después de matar el tween de hover deja un solo
## ganador en vez de dos tweens compitiendo por la misma propiedad.
func _resettle_card(character_id: String) -> void:
	var card: Button = _cards_by_id.get(character_id)
	if card == null:
		return
	UiTheme.kill_meta_tween(card, &"ui_motion_tween")
	_settle_card(card, _card_selected(character_id))


## Carta bloqueada: candado en lugar del retrato, nombre y arma atenuados, y
## el precio en esquirlas como llamada a la acción.
func _populate_locked_card(card: Button, character: Dictionary) -> void:
	var box := CardFactory.card_box(card)
	box.add_child(CardFactory.lock_glyph())
	box.add_child(CardFactory.label(
			String(character.display_name), 20, UiTheme.TEXT_FAINT))
	box.add_child(CardFactory.label(String(character.weapon_display_name), 12,
			UiTheme.TEXT_FAINT.darkened(0.15)))
	# Chip de precio: una píldora azul de esquirla para que el costo se lea
	# como un botón. Va justo bajo el nombre y el arma, que ocupan una línea
	# en toda carta, así el precio queda a la misma altura en toda la fila sin
	# importar cuánto se envuelvan la pasiva o la pista. SHRINK_CENTER
	# mantiene la píldora de su propio tamaño.
	var cost := CardFactory.label(UiTheme.SHARDS_AMOUNT % int(character.get("unlock_cost", 0)),
			13, UiTheme.SHARD_BLUE)
	cost.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_badge(cost, UiTheme.SHARD_BLUE,
			Color(0.07, 0.1, 0.14, 0.9), UiTheme.SHARD_BLUE.darkened(0.5))
	box.add_child(cost)
	var hint_text := String(character.get("unlock_hint", ""))
	if not hint_text.is_empty():
		# Los personajes que también se desbloquean con un jefe muestran los
		# dos caminos: el precio y, justo debajo, la pista vaga del catálogo
		# hacia el jefe oculto.
		var hint := CardFactory.label(
				"o %s" % hint_text, 10, UiTheme.SHARD_BLUE.darkened(0.25))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.max_lines_visible = UNLOCK_HINT_MAX_LINES
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(hint)
	var passive := CardFactory.label(String(character.passive_description), 12,
			UiTheme.TEXT_FAINT.darkened(0.15))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passive.max_lines_visible = LOCKED_PASSIVE_MAX_LINES
	passive.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(passive)
	UiTheme.style_card(card, UiTheme.BORDER_LOCKED, 2, false)


## La confirmación de compra en la que se convierte la carta bloqueada
## cuando alcanza el saldo.
func _populate_confirm_card(card: Button, character: Dictionary) -> void:
	var box := CardFactory.card_box(card)
	box.add_child(CardFactory.portrait_swatch(Color(character.tint),
			String(character.display_name)))
	box.add_child(CardFactory.label(
			String(character.display_name), 20, UiTheme.TEXT_BRIGHT))
	var ask := CardFactory.label(
			"¿Desbloquear por %d esquirlas?" % int(character.get("unlock_cost", 0)),
			13, UiTheme.SHARD_BLUE)
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ask)
	var yes := Button.new()
	yes.text = "Sí"
	yes.custom_minimum_size = Vector2(0.0, 36.0)
	yes.pressed.connect(_on_unlock_confirmed.bind(String(character.id)))
	UiTheme.style_button(yes, UiTheme.SHARD_BLUE, true)
	box.add_child(yes)
	var hint := CardFactory.label("clic en la carta para cancelar", 10, UiTheme.TEXT_FAINT)
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(hint)
	UiTheme.style_card(card, UiTheme.SHARD_BLUE, 3)


## Respuesta de "no alcanza": destello rojo rápido y un vaivén de rotación
## (la rotación no pelea con el layout del GridContainer como lo haría la
## posición). El destello vuelve al modulate de REPOSO de la carta (una carta
## no elegida está atenuada, y terminar en blanco la dejaría más clara que
## sus vecinas) y comparte la metadata de _settle_card para que los dos
## nunca animen a la vez.
func _reject_card(card: Button, rest_modulate: Color = Color.WHITE) -> void:
	UiTheme.reject(card, UiTheme.REJECT_SWINGS, UiTheme.REJECT_SWING_TIMES,
			rest_modulate, &"ui_settle_tween")
