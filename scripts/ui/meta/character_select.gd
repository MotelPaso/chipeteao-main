extends Control
## Selector de personaje (GDD 5/7), la escena de entrada del juego: elige un
## raider (y en co-op local, el grupo) e Iniciar incursión carga Run.tscn.
## Las cartas (CharacterCard.tscn) salen de CharacterCatalog en tiempo de
## ejecución, así que un personaje nuevo es una fila del catálogo; la elección
## queda en el autoload GameConfig.
##
## Meta-progresión (GDD 8): SaveData controla el plantel. Las cartas
## bloqueadas muestran un candado y su precio en esquirlas; con saldo
## suficiente, un clic convierte la carta en la confirmación "¿Desbloquear por
## N esquirlas? [Sí]" (un segundo clic cancela), y sin saldo la carta destella
## en rojo y se sacude. Toda partida empieza en el Bosque Hueco y recorre la
## lista de mapas, así que aquí solo se eligen el raider, el grupo (CoopLobby)
## y la Cacería diaria (DailyHunt).
##
## Partes: CharacterCard dibuja cada carta, CoopLobby es dueño del grupo de
## co-op y DailyHunt prepara la diaria. Este script cablea la selección, el
## desbloqueo, la navegación con control y los botones de la escena.
##
## Layout: título y subtítulo fijos arriba y la fila de botones abajo (el
## botón principal se alcanza con cualquier tamaño de ventana); el medio
## (co-op y cuadrícula) se desplaza, y la cuadrícula calcula sus columnas
## según el ancho de la ventana y el tamaño del plantel.

const CARD_SCENE: PackedScene = preload("res://scenes/ui/meta/character_select/CharacterCard.tscn")

@export_group("Cuadrícula")
## La cuadrícula nunca baja de estas columnas, aunque la ventana sea angosta
## (entonces se desplaza).
@export var grid_min_columns: int = 4
## Filas a las que apunta antes de ensancharse: agregar un raider ensancha la
## cuadrícula en vez de empujar filas (y el botón principal) fuera.
@export var grid_target_rows: int = 3

@export_group("Movimiento")
## Brillo (modulate) al que sube el título en su pulso lento.
@export var title_glow_color: Color = Color(1.14, 1.1, 1.0)
## Duración (segundos) de cada mitad del pulso del título.
@export var title_glow_time: float = 1.6
## Retraso (segundos) entre secciones en la entrada escalonada.
@export var entrance_stagger: float = 0.05
## Duración (segundos) del fundido de entrada de cada sección.
@export var entrance_fade_time: float = 0.22
## Duración (segundos) de la escala de entrada de cada sección.
@export var entrance_scale_time: float = 0.26
## Escala desde la que entra cada sección.
@export var entrance_start_scale: float = 0.96
## Escala del botón Iniciar al pasar el mouse.
@export var start_hover_grow: float = 1.05
## Escala del botón Iniciar al presionarlo.
@export var start_press_squash: float = 0.93
## Escala máxima del golpe del saldo de esquirlas al cambiar.
@export var shards_pop_peak: float = 1.12
## Duración del golpe del saldo de esquirlas, en segundos.
@export var shards_pop_time: float = 0.22

@export_group("Textos")
## Botón Iniciar en solo (%s = nombre del raider).
@export var start_solo_format: String = "Iniciar incursión — %s"
## Botón Iniciar en co-op (%d = jugadores).
@export var start_party_format: String = "Iniciar incursión — %d jugadores"
## Botón de la Cacería diaria cuando ya hay marca hoy (%d = mejor puntaje);
## sin marca se ve el texto del botón en la escena.
@export var daily_best_format: String = "Cacería diaria — mejor %d"
## Versión abajo a la derecha (%s = application/config/version).
@export var version_format: String = "v%s"
## Indicación del botón de aceptar, abajo a la izquierda.
@export var choose_hint: String = "Elegir"

## Carta por id de personaje jugable, para restilizar la selección.
var _cards_by_id: Dictionary[String, CharacterCard] = {}
## Id del personaje cuya carta muestra la confirmación de desbloqueo.
var _pending_unlock_id: String = ""
var _title_tween: Tween = null
var _entrance_tween: Tween = null
## Suscripción a SaveData guardada para soltarla en _exit_tree (el autoload
## sobrevive a esta escena).
var _on_shards_changed: Callable

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
## Sus márgenes laterales descuentan el ancho que recibe la cuadrícula.
@onready var _layout: MarginContainer = %Layout
@onready var _lobby: CoopLobby = %CoopLobby
@onready var _cards_grid: GridContainer = %CardsGrid
## HFlowContainer: los botones bajan a una segunda línea en una ventana
## angosta en vez de salirse.
@onready var _button_row: HFlowContainer = %ButtonRow
@onready var _start_button: Button = %StartButton
@onready var _daily_button: Button = %DailyButton
@onready var _quests_button: Button = %QuestsButton
@onready var _collection_button: Button = %CollectionButton
@onready var _armory_button: Button = %ArmoryButton
@onready var _settings_button: Button = %SettingsButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _shards_label: Label = %ShardsLabel
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_lobby.party_changed.connect(_on_party_changed)
	_lobby.slots_rebuilt.connect(_link_focus)
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		var character_id := String(character.id)
		var card := CARD_SCENE.instantiate() as CharacterCard
		_cards_grid.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(character_id))
		# Después de add_child: el hover de UiTheme (conectado en el _ready de
		# la carta) tiene que correr antes que el reasentado.
		card.mouse_exited.connect(_resettle_card.bind(character_id))
		card.unlock_confirmed.connect(_on_unlock_confirmed)
		_cards_by_id[character_id] = card
	_update_grid_columns()
	resized.connect(_update_grid_columns)
	_apply_chrome()
	_style_buttons()
	# Indicación de botones en la esquina inferior izquierda, que está libre
	# (la fila de botones va centrada y la versión abajo a la derecha). Va
	# ANTES del panel de ajustes en el árbol para que su atenuado la cubra.
	var hints := InputHints.build([["ui_accept", choose_hint]])
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
	_version_label.text = version_format % String(
			ProjectSettings.get_setting("application/config/version", "0.0.0"))
	# Reabrir en la misma sesión conserva la elección anterior; un id
	# desconocido o bloqueado vuelve al personaje por defecto.
	var remembered := String(
			CharacterCatalog.by_id_or_default(GameConfig.selected_character_id).id)
	if not SaveData.is_unlocked(remembered):
		remembered = CharacterCatalog.DEFAULT_ID
	_select(remembered)
	_lobby.restore_session()
	_start_button.grab_focus()
	_play_entrance()


func _exit_tree() -> void:
	if _on_shards_changed.is_valid() \
			and SaveData.shards_changed.is_connected(_on_shards_changed):
		SaveData.shards_changed.disconnect(_on_shards_changed)


## --- Tamaño de la cuadrícula (el plantel crece con filas del catálogo) ---

## Las columnas salen del tamaño del plantel (apuntando a grid_target_rows
## filas), acotadas por lo que cabe en la ventana.
func _update_grid_columns() -> void:
	if _cards_grid.get_child_count() == 0:
		return
	var card_width := (_cards_grid.get_child(0) as Control).custom_minimum_size.x
	var separation := float(_cards_grid.get_theme_constant(&"h_separation"))
	var side_margins := _layout.get_theme_constant(&"margin_left") \
			+ _layout.get_theme_constant(&"margin_right")
	var available := get_viewport_rect().size.x - float(side_margins)
	var fits := maxi(1, floori((available + separation) / (card_width + separation)))
	var wanted := maxi(grid_min_columns, ceili(
			float(CharacterCatalog.CHARACTER_LIBRARY.size()) / float(grid_target_rows)))
	var columns := clampi(wanted, 1, fits)
	if _cards_grid.columns != columns:
		_cards_grid.columns = columns
	_link_focus()


## --- Botones y cromo -------------------------------------------------------

## Aspecto y acciones de los botones de la escena. attach_motion es
## idempotente (gana la primera llamada): Iniciar reclama su crecer/aplastar
## más fuerte ANTES de que style_button ponga el de por defecto.
func _style_buttons() -> void:
	UiTheme.attach_motion(_start_button, start_hover_grow, start_press_squash)
	UiTheme.style_button(_start_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_quests_button)
	UiTheme.style_button(_settings_button)
	_start_button.pressed.connect(_on_start_pressed)
	_quests_button.pressed.connect(_open_scene.bind(ScenePaths.QUEST_LOG))
	UiTheme.style_button(_collection_button)
	_collection_button.pressed.connect(_open_scene.bind(ScenePaths.COLLECTION))
	UiTheme.style_button(_armory_button)
	_armory_button.pressed.connect(_open_scene.bind(ScenePaths.RELIC_SHOP))
	var best := DailyHunt.best_today()
	if best > 0:
		_daily_button.text = daily_best_format % best
	UiTheme.style_button(_daily_button, UiTheme.ACCENT_AMBER)
	_daily_button.pressed.connect(_on_daily_pressed)


## La píldora del saldo (en el color de texto que tiene en la escena) y el
## pulso lento de brillo del título (el movimiento dice "vivo", nunca
## "ocupado"). La tipografía del título y del subtítulo vive en la escena.
func _apply_chrome() -> void:
	var badge := _shards_label.get_theme_color(&"font_color")
	UiTheme.style_badge(_shards_label, badge, UiTheme.PANEL_BG,
			badge.darkened(UiTheme.BADGE_EDGE_DARKEN))
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	_title_tween = create_tween().set_loops()
	_title_tween.tween_property(_title_label, "modulate",
			title_glow_color, title_glow_time).set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
	_title_tween.tween_property(_title_label, "modulate",
			Color.WHITE, title_glow_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Aparición escalonada de las secciones al abrir. Las secciones animan su
## propio modulate y las cartas el suyo, así que restilizar la selección
## nunca pelea con la entrada.
func _play_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	var sections: Array[Control] = [_title_label, _subtitle_label]
	sections.append_array(_lobby.entrance_rows())
	sections.append_array([_cards_grid, _button_row])
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
		section.scale = Vector2.ONE * entrance_start_scale
		var delay := entrance_stagger * i
		_entrance_tween.tween_property(section, "modulate:a", 1.0, entrance_fade_time) \
				.set_delay(delay)
		_entrance_tween.tween_property(section, "scale", Vector2.ONE, entrance_scale_time) \
				.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_shards() -> void:
	_shards_label.text = UiTheme.SHARDS_BALANCE % SaveData.shards
	UiTheme.pop(_shards_label, shards_pop_peak, shards_pop_time)


func _refresh_start_button() -> void:
	if _lobby.is_party():
		_start_button.text = start_party_format % _lobby.party_size()
	else:
		var picked := CharacterCatalog.by_id_or_default(GameConfig.selected_character_id)
		_start_button.text = start_solo_format % String(picked.display_name)


## --- Selección y desbloqueo -----------------------------------------------

## La selección solo se ofrece para personajes desbloqueados
## (_on_card_pressed manda los clics bloqueados al flujo de desbloqueo). En
## co-op el clic asigna el raider al slot resaltado del lobby.
func _select(character_id: String) -> void:
	if _lobby.is_party():
		_lobby.assign(character_id)
	else:
		GameConfig.selected_character_id = character_id
	_refresh_all_cards()
	_refresh_start_button()


func _on_party_changed() -> void:
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
		_cards_by_id[character_id].reject(_card_selected(character_id))


func _on_unlock_confirmed(character_id: String) -> void:
	_pending_unlock_id = ""
	if SaveData.purchase_character(character_id):
		Sfx.play(&"chest_open")  # fanfarria de desbloqueo: el sonido del cofre
		_select(character_id)  # también refresca todas las cartas
	else:
		_refresh_all_cards()
	# El «Sí» recién presionado se oculta con el refresco y el foco se va con
	# él: se le pasa a su carta.
	var card := _cards_by_id.get(character_id) as CharacterCard
	if card != null:
		card.grab_focus()


func _cancel_pending_unlock() -> void:
	_pending_unlock_id = ""


## Repinta cada carta con su cara (desbloqueada, bloqueada o confirmando) y
## si se ve elegida; en co-op, con los jugadores que la eligieron.
func _refresh_all_cards() -> void:
	for character_id: String in _cards_by_id:
		var face := CharacterCard.Face.UNLOCKED
		if not SaveData.is_unlocked(character_id):
			face = CharacterCard.Face.CONFIRM if _pending_unlock_id == character_id \
					else CharacterCard.Face.LOCKED
		var selected := _card_selected(character_id)
		var owners: Array[int] = []
		if face == CharacterCard.Face.UNLOCKED and selected and _lobby.is_party():
			owners = _lobby.owner_slots(character_id)
		_cards_by_id[character_id].show_character(CharacterCatalog.by_id(character_id),
				face, selected, owners)
	_link_focus()


## La única respuesta a "¿esta carta se ve elegida?", compartida por el
## repintado y por el reasentado tras el hover. Co-op: elegida si CUALQUIER
## slot la eligió.
func _card_selected(character_id: String) -> bool:
	if not SaveData.is_unlocked(character_id):
		return _pending_unlock_id == character_id
	if _lobby.is_party():
		return _lobby.has_character(character_id)
	return character_id == GameConfig.selected_character_id


## Al salir el mouse, la carta vuelve a su pose de reposo (ver
## CharacterCard.resettle).
func _resettle_card(character_id: String) -> void:
	var card := _cards_by_id.get(character_id) as CharacterCard
	if card == null:
		return
	card.resettle(_card_selected(character_id))


## --- Iniciar, Cacería diaria y pantallas meta ----------------------------

func _on_start_pressed() -> void:
	# Un inicio normal nunca es la Cacería diaria (la marca su propio botón).
	GameConfig.daily_mode = false
	if not _lobby.commit_party():
		UiTheme.reject(_start_button)
		return
	GameConfig.start_map_id = MapCatalog.DEFAULT_ID
	_launch_run()


func _on_daily_pressed() -> void:
	if DailyHunt.configure_today():
		_launch_run()


## Toda partida arranca en Run.tscn, que es dueña del bloque persistente y
## cambia la arena por etapa.
func _launch_run() -> void:
	ScreenFade.transition(func() -> void:
		# RunState sigue corriendo mientras esta pantalla sin pausa está
		# arriba: la partida nueva parte de cero (igual que Reintentar).
		RunState.reset()
		get_tree().change_scene_to_file(ScenePaths.RUN))


func _open_scene(scene_path: String) -> void:
	ScreenFade.transition(func() -> void:
		get_tree().change_scene_to_file(scene_path))


## --- Navegación con control y teclado -------------------------------------

## Vecinos de foco de la cuadrícula y de la fila de botones, cableados a
## mano. Con la búsqueda automática de Godot, ui_down desde una carta de las
## columnas 3+ cae en "Cacería diaria" o "Misiones" (quedan bajo esas
## columnas; Iniciar queda bajo las columnas 1-2) y desde ahí se atasca en
## "Armería": con control no se llegaría a Iniciar. Por eso:
##   - abajo desde una carta va a la carta de abajo, o a Iniciar al final de
##     la columna (pasando por el «Sí» si la carta pide desbloquear);
##   - arriba desde la fila superior va al lobby co-op, sobre la cuadrícula;
##   - la fila de botones va a izquierda y derecha, nunca abajo, y arriba
##     vuelve al raider elegido.
## Se vuelve a correr tras todo lo que rehace cartas, slots o columnas.
func _link_focus() -> void:
	var cards: Array[CharacterCard] = []
	for child: Node in _cards_grid.get_children():
		if child is CharacterCard:
			cards.append(child as CharacterCard)
	var columns := maxi(_cards_grid.columns, 1)
	var above_grid := _lobby.focus_target()
	for i in cards.size():
		var card := cards[i]
		var below: Control = cards[i + columns] if i + columns < cards.size() \
				else _start_button
		if i < columns and above_grid != null:
			card.focus_neighbor_top = card.get_path_to(above_grid)
		var yes := card.unlock_button()
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
