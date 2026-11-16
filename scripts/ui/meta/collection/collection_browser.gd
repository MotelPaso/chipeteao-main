class_name CollectionBrowser
extends Control
## Pantalla de una categoría de la Colección (CollectionBrowser.tscn):
## Personajes, Enemigos, Mapas, Objetos, Tomos o Armas. Se ve como el selector
## de personaje: una cuadrícula de cartas compactas a la izquierda y el
## detalle de la carta mirada a la derecha. Aquí no se elige nada: solo se
## mira.
##
## Qué categoría mostrar lo deja el submenú en `category` antes de cambiar de
## escena. Las entradas las arma CollectionEntries; esta pantalla crea una
## CollectionCard por entrada, cablea el foco (CollectionFocus), pide las
## fotos (PortraitStudio para raiders, EnemyStudio para enemigos) y le pasa al
## detalle la carta con foco o mouse.
##
## Volver y ui_cancel (B / Escape) regresan al submenú de la Colección.

const CARD_SCENE: PackedScene = preload("res://scenes/ui/meta/collection/CollectionCard.tscn")

@export_group("Cuadrícula")
## Mínimo de columnas de la cuadrícula.
@export var grid_min_columns: int = 4
## Ancho máximo de una carta, en píxeles: con más espacio se suman columnas.
@export var card_max_width: float = 230.0

@export_group("Movimiento")
## Espera (segundos) entre la primera carta y la segunda en la entrada.
@export var card_stagger: float = 0.05
## Cuánto se acorta cada espera respecto de la anterior (1 = todas iguales).
@export_range(0.1, 1.0) var card_stagger_shrink: float = 0.8
## Desde esta carta todas entran juntas: una cuadrícula larga no se abre
## como una fila de espera.
@export var card_stagger_cap: int = 6
## Duración (segundos) del fundido de la barra, el detalle y el pie.
@export var entrance_fade_time: float = 0.18

@export_group("Textos")
## Subtítulo con el avance de la categoría (%d = descubiertas, %d = total).
@export var progress_format: String = "%d / %d descubiertos"
## Indicación del botón de cancelar.
@export var back_hint: String = "Volver"

## Categoría que muestra la pantalla (un id de CollectionEntries). La escribe
## el submenú antes de abrirla.
static var category: String = CollectionEntries.RAIDERS
## Última carta mirada en cada categoría, para devolverle el foco al volver
## (vive mientras dure la sesión).
static var _last_entry: Dictionary[String, String] = {}

var _entries: Array[Dictionary] = []
var _by_id: Dictionary[String, Dictionary] = {}
var _cards: Array[CollectionCard] = []
var _entrance_tween: Tween = null

@onready var _layout: Control = %Layout
@onready var _top_bar: Control = %TopBar
@onready var _back_button: Button = %BackButton
@onready var _title_label: Label = %TitleLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _scroll: ScrollContainer = %ContentScroll
@onready var _grid_pad: MarginContainer = %GridPad
@onready var _cards_grid: GridContainer = %CardsGrid
@onready var _detail: CollectionDetail = %CollectionDetail
@onready var _footer: Control = %Footer
@onready var _hints_slot: HBoxContainer = %HintsSlot
@onready var _raider_studio: PortraitStudio = %PortraitStudio
@onready var _enemy_studio: EnemyStudio = %EnemyStudio


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UiTheme.style_button(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	_hints_slot.add_child(InputHints.build([["ui_cancel", back_hint]]))
	# Un control que recorre las cartas debe ver siempre la enfocada.
	_scroll.follow_focus = true
	_entries = CollectionEntries.entries(category)
	_title_label.text = String(CollectionEntries.CATEGORY_TITLES.get(category, ""))
	var progress := CollectionEntries.progress(category)
	_progress_label.text = progress_format % [progress.x, progress.y]
	_build_cards()
	_scroll.resized.connect(_update_grid_columns)
	_update_grid_columns()
	_request_photos()
	var start := _resume_card()
	if start != null:
		_detail.show_entry(_by_id[start.entry_id], false)
		_show_detail_photo(start.entry_id)
		start.grab_focus()
	else:
		_back_button.grab_focus()
	# Una sola entrada: las cartas entran una tras otra y el resto funde; el
	# contenido no se desliza además.
	MenuNav.arrive(_layout, false)
	_play_entrance()


## Esc / B vuelve al submenú, igual que en el resto de los menús.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	MenuNav.go(_layout, ScenePaths.COLLECTION, MenuNav.Direction.BACK)


func _build_cards() -> void:
	for entry: Dictionary in _entries:
		var card := CARD_SCENE.instantiate() as CollectionCard
		_cards_grid.add_child(card)
		card.show_entry(entry)
		card.highlighted.connect(_on_card_highlighted)
		_by_id[String(entry.id)] = entry
		_cards.append(card)


## Reparte las columnas según el ancho libre: tantas como hagan falta para que
## ninguna carta pase de card_max_width, nunca menos de grid_min_columns ni
## más de las que caben con el ancho mínimo de carta.
func _update_grid_columns() -> void:
	if _cards.is_empty():
		return
	var card_min_width := _cards[0].custom_minimum_size.x
	var separation := float(_cards_grid.get_theme_constant(&"h_separation"))
	var available := _scroll.size.x - float(
			_grid_pad.get_theme_constant(&"margin_left")
			+ _grid_pad.get_theme_constant(&"margin_right"))
	var fits := maxi(1, floori((available + separation) / (card_min_width + separation)))
	var wanted := maxi(grid_min_columns,
			ceili((available + separation) / (card_max_width + separation)))
	var columns := clampi(wanted, 1, fits)
	if _cards_grid.columns != columns:
		_cards_grid.columns = columns
	CollectionFocus.link(_cards, _cards_grid.columns, _back_button, _resume_card())


## Fotos de las cartas: las que ya están en memoria se ponen al instante; las
## que faltan las saca el estudio de a una y avisan con su señal.
func _request_photos() -> void:
	match category:
		CollectionEntries.RAIDERS:
			var rows: Array[Dictionary] = []
			for entry: Dictionary in _entries:
				var face := PortraitStudio.cached_face(String(entry.id))
				if face != null:
					_card_for(String(entry.id)).set_photo(face)
				else:
					rows.append(entry.row as Dictionary)
			_raider_studio.face_ready.connect(_on_photo_ready)
			_raider_studio.shoot_rows(rows)
		CollectionEntries.ENEMIES:
			for entry: Dictionary in _entries:
				var photo := EnemyStudio.cached_photo(String(entry.id))
				if photo != null:
					_card_for(String(entry.id)).set_photo(photo)
			_enemy_studio.photo_ready.connect(_on_photo_ready)
			_enemy_studio.shoot_entries(_entries)


func _on_photo_ready(entry_id: String, photo: Texture2D) -> void:
	var card := _card_for(entry_id)
	if card != null:
		card.set_photo(photo)
	_detail.set_photo(entry_id, photo)


func _on_card_highlighted(entry_id: String) -> void:
	if not _by_id.has(entry_id):
		return
	_last_entry[category] = entry_id
	_detail.show_entry(_by_id[entry_id])
	_show_detail_photo(entry_id)
	_back_button.focus_neighbor_bottom = _back_button.get_path_to(_card_for(entry_id))


## La foto ya sacada de esa entrada, para el dibujo grande del detalle.
func _show_detail_photo(entry_id: String) -> void:
	var photo: Texture2D = null
	match category:
		CollectionEntries.RAIDERS:
			photo = PortraitStudio.cached_face(entry_id)
		CollectionEntries.ENEMIES:
			photo = EnemyStudio.cached_photo(entry_id)
	_detail.set_photo(entry_id, photo)


func _card_for(entry_id: String) -> CollectionCard:
	for card: CollectionCard in _cards:
		if card.entry_id == entry_id:
			return card
	return null


## La carta que recibe el foco al abrir: la última mirada en esta categoría,
## o la primera.
func _resume_card() -> CollectionCard:
	var remembered := _card_for(String(_last_entry.get(category, "")))
	if remembered != null:
		return remembered
	return _cards[0] if not _cards.is_empty() else null


## Entrada al abrir. Las cartas son las protagonistas: entran una tras otra
## con esperas que se acortan, así el grupo se lee como una ola; desde la
## carta card_stagger_cap todas llegan juntas. La barra, el detalle y el pie
## solo funden, a la vez. Es decorativa: el foco y los clics funcionan desde
## el primer frame.
func _play_entrance() -> void:
	for i in _cards.size():
		_cards[i].play_entrance(_card_delay(i))
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = create_tween().set_parallel()
	_entrance_tween.set_ignore_time_scale(true)
	for section: Control in [_top_bar, _detail, _footer]:
		section.modulate.a = 0.0
		_entrance_tween.tween_property(section, "modulate:a", 1.0, entrance_fade_time) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Espera de la carta número `index` (desde 0): cada paso es más corto que el
## anterior (card_stagger_shrink) y se detiene en card_stagger_cap.
func _card_delay(index: int) -> float:
	var delay := 0.0
	var step := card_stagger
	for i in mini(index, card_stagger_cap):
		delay += step
		step *= card_stagger_shrink
	return delay
