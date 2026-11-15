extends Control
## Menú principal, la escena de entrada del juego: cuatro tarjetas grandes
## (Cacería, Misiones, Colección, Armería) más Ajustes y Salir. Solo Cacería
## lleva al selector de personaje; las otras abren su pantalla, que vuelve
## aquí con su botón Volver o con ui_cancel (B / Escape).
##
## Cada tarjeta (MenuTile.tscn) es dueña de su aspecto y su movimiento; este
## script las conecta, escribe su dato vivo (misiones por reclamar, saldo de
## esquirlas), le pasa a Cacería la foto del raider elegido y cablea el foco
## del control. El foco vuelve a la tarjeta desde
## la que saliste.

@export_group("Textos")
## Dato de la tarjeta Misiones con recompensas esperando (%d = cuántas).
@export var quests_claimable_format: String = "%d por reclamar"
## Versión abajo a la derecha (%s = application/config/version).
@export var version_format: String = "v%s"
## Indicación del botón de aceptar, abajo a la izquierda.
@export var choose_hint: String = "Elegir"

@export_group("Movimiento")
## Retraso (segundos) entre una tarjeta y la siguiente en la entrada.
@export var tile_stagger: float = 0.05
## Escala máxima del golpe del saldo de esquirlas al cambiar.
@export var shards_pop_peak: float = 1.12
## Duración del golpe del saldo de esquirlas, en segundos.
@export var shards_pop_time: float = 0.22

## Nombre de la tarjeta desde la que se salió del menú, para devolverle el
## foco al volver (vive mientras dure la sesión).
static var _last_tile: StringName = &"HuntButton"

@onready var _layout: Control = %Layout
@onready var _hunt: MenuTile = %HuntButton
@onready var _quests: MenuTile = %QuestsButton
@onready var _collection: MenuTile = %CollectionButton
@onready var _armory: MenuTile = %ArmoryButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _shards_label: Label = %ShardsLabel
@onready var _version_label: Label = %VersionLabel
@onready var _hints_slot: HBoxContainer = %HintsSlot
@onready var _studio: PortraitStudio = %PortraitStudio


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hunt.pressed.connect(_open.bind(_hunt, ScenePaths.CHARACTER_SELECT))
	_quests.pressed.connect(_open.bind(_quests, ScenePaths.QUEST_LOG))
	_collection.pressed.connect(_open.bind(_collection, ScenePaths.COLLECTION))
	_armory.pressed.connect(_open.bind(_armory, ScenePaths.RELIC_SHOP))
	UiTheme.style_button(_settings_button)
	UiTheme.style_button(_quit_button)
	_settings_button.pressed.connect(_settings_panel.open)
	_settings_panel.closed.connect(func() -> void: _settings_button.grab_focus())
	_quit_button.pressed.connect(_on_quit_pressed)
	# En el navegador no hay ventana que cerrar.
	_quit_button.visible = not OS.has_feature("web")
	_hints_slot.add_child(InputHints.build([["ui_accept", choose_hint]]))
	_version_label.text = version_format % String(
			ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_refresh_stats()
	_show_hunt_raider()
	_link_focus()
	var remembered := get_node_or_null("%" + String(_last_tile)) as Control
	(remembered if remembered != null else _hunt).grab_focus()
	# Una sola entrada: al volver de una sección entra la pantalla entera; solo
	# al abrir el juego las tarjetas entran una tras otra.
	if not MenuNav.arrive(_layout):
		_play_entrance()


func _open(tile: MenuTile, scene_path: String) -> void:
	if MenuNav.go(_layout, scene_path, MenuNav.Direction.FORWARD):
		_last_tile = tile.name


func _on_quit_pressed() -> void:
	Settings.flush_save()
	get_tree().quit()


## Los datos vivos de las tarjetas: se leen una vez al abrir, porque nada los
## cambia mientras esta pantalla está arriba.
func _refresh_stats() -> void:
	_shards_label.text = UiTheme.SHARDS_BALANCE % SaveData.shards
	var claimable := 0
	for quest: Dictionary in QuestCatalog.QUEST_LIBRARY:
		var quest_id := String(quest.id)
		if SaveData.is_quest_completed(quest_id) and not SaveData.is_quest_claimed(quest_id):
			claimable += 1
	_quests.set_stat(quests_claimable_format % claimable if claimable > 0 else "")
	_armory.set_stat(UiTheme.SHARDS_AMOUNT % SaveData.shards)


## La tarjeta Cacería muestra al raider elegido en esta sesión (al abrir el
## juego, el inicial). Si su modelo no existe, muestra al inicial. La foto la
## saca PortraitStudio; si ya la sacó el selector, se usa esa sin repetirla.
func _show_hunt_raider() -> void:
	var row := CharacterCatalog.by_id_or_default(GameConfig.selected_character_id)
	var model := String(row.get("model_scene", ""))
	if not model.is_empty() and not ResourceLoader.exists(model, "PackedScene"):
		row = CharacterCatalog.by_id(CharacterCatalog.DEFAULT_ID)
	var raider_id := String(row.id)
	var face := PortraitStudio.cached_face(raider_id)
	if face != null:
		_hunt.art_texture = face
		return
	_studio.face_ready.connect(func(character_id: String, photo: Texture2D) -> void:
		if character_id == raider_id:
			_hunt.set_art(photo))
	_studio.shoot_rows([row] as Array[Dictionary])


## Las tarjetas entran una tras otra, de izquierda a derecha (solo al abrir
## el juego: es un momento que se ve una vez por sesión).
func _play_entrance() -> void:
	var tiles: Array[MenuTile] = [_hunt, _quests, _collection, _armory]
	for i in tiles.size():
		tiles[i].play_entrance(tile_stagger * i)


## Vecinos de foco a mano: las tarjetas en fila (los extremos no dan la
## vuelta), abajo de cualquier tarjeta está Ajustes, y de la fila de abajo se
## sube a la última tarjeta usada.
func _link_focus() -> void:
	var tiles: Array[Control] = [_hunt, _quests, _collection, _armory]
	var below: Control = _settings_button
	for i in tiles.size():
		var tile := tiles[i]
		_wire(tile, SIDE_LEFT, tiles[maxi(i - 1, 0)])
		_wire(tile, SIDE_RIGHT, tiles[mini(i + 1, tiles.size() - 1)])
		_wire(tile, SIDE_TOP, tile)
		_wire(tile, SIDE_BOTTOM, below)
	var last_right: Control = _quit_button if _quit_button.visible else _settings_button
	_wire(_settings_button, SIDE_LEFT, _settings_button)
	_wire(_settings_button, SIDE_RIGHT, last_right)
	_wire(_settings_button, SIDE_TOP, _hunt)
	_wire(_settings_button, SIDE_BOTTOM, _settings_button)
	_wire(_quit_button, SIDE_LEFT, _settings_button)
	_wire(_quit_button, SIDE_RIGHT, _quit_button)
	_wire(_quit_button, SIDE_TOP, _armory)
	_wire(_quit_button, SIDE_BOTTOM, _quit_button)


static func _wire(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))
