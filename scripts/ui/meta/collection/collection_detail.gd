class_name CollectionDetail
extends PanelContainer
## Panel de detalle de la Colección (CollectionDetail.tscn): la entrada que el
## jugador está mirando, en grande, con su nombre, una línea corta, la
## descripción y sus estadísticas (cada una con su icono). Las cartas de la
## cuadrícula son compactas; el texto largo vive aquí.
##
## El dibujo grande es un CollectionArt. Encima puede ir UN retrato 3D
## giratorio: el CharacterPortrait del selector para un raider desbloqueado, o
## un EnemyPortrait para un enemigo descubierto. Se crea solo cuando hace
## falta, así nunca hay más de un SubViewport vivo.
##
## La pantalla solo pasa la entrada de CollectionEntries (show_entry); el
## panel decide cómo se ve y cómo entra.

const RAIDER_PORTRAIT_SCENE: PackedScene = preload(
		"res://scenes/ui/meta/character_select/CharacterPortrait.tscn")
const ENEMY_PORTRAIT_SCENE: PackedScene = preload(
		"res://scenes/ui/meta/collection/EnemyPortrait.tscn")
const STAT_CHIP_SCENE: PackedScene = preload("res://scenes/ui/meta/StatIconChip.tscn")

@export_group("Panel")
## Cuánto se oscurece el color de la entrada para el borde del panel (0-1).
@export_range(0.0, 1.0) var border_darken: float = 0.2
## Margen interior del panel (horizontal, vertical), en píxeles.
@export var panel_margin: Vector2 = Vector2(16.0, 14.0)

@export_group("Líneas")
## Lado de la ficha del icono de cada línea de estadística, en píxeles.
@export var line_chip_size: float = 34.0
## Tamaño de fuente de cada línea, en píxeles.
@export var line_font_size: int = 15
## Color del texto de cada línea.
@export var line_color: Color = UiTheme.TEXT_NORMAL
## Separación entre la ficha y su texto, en píxeles.
@export var line_separation: int = 10
## Ancho mínimo del texto de cada línea, en píxeles: evita que una línea
## recién creada se parta letra por letra antes de conocer su ancho real.
@export var line_min_text_width: float = 160.0

@export_group("Movimiento")
## Píxeles que se desliza el contenido al cambiar de entrada (0 = solo fundido).
@export var slide_distance: float = 14.0
## Alfa (0-1) desde el que funde el contenido al cambiar de entrada.
@export_range(0.0, 1.0) var fade_from: float = 0.0
## Duración (segundos) del cambio de entrada.
@export var swap_time: float = 0.18

## Id de la entrada que muestra el panel.
var entry_id: String = ""

var _style: StyleBoxFlat = null
var _swap_tween: Tween = null
var _raider_portrait: CharacterPortrait = null
var _enemy_portrait: EnemyPortrait = null

@onready var _body: Control = $Body
@onready var _content: VBoxContainer = $Body/Content
@onready var _art: CollectionArt = %Art
@onready var _live_slot: Control = %LiveSlot
@onready var _name: Label = %Name
@onready var _caption: Label = %Caption
@onready var _text: Label = %Text
@onready var _lines: VBoxContainer = %Lines


func _ready() -> void:
	_style = UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM,
			panel_margin.x, panel_margin.y)
	add_theme_stylebox_override("panel", _style)
	# Content se desliza dentro de Body, que no es un contenedor (así el layout
	# no pelea con el deslizamiento): Content toma el tamaño de Body, y Body
	# copia su alto mínimo para que el panel nunca quede más chico que su
	# contenido.
	_body.resized.connect(_fit_content)
	_content.minimum_size_changed.connect(_fit_content)
	_fit_content()


## Muestra esa entrada de CollectionEntries. Si cambió, el contenido entra con
## un fundido y un deslizamiento corto; `animate` apagado lo deja quieto.
func show_entry(entry: Dictionary, animate: bool = true) -> void:
	# Al cerrar la pantalla, la carta con foco lo pierde cuando este panel ya
	# salió del árbol: no queda nada que mostrar.
	if not is_inside_tree():
		return
	var changed := String(entry.id) != entry_id
	# La primera entrada aparece quieta: la anima la entrada de la pantalla.
	var first := entry_id.is_empty()
	entry_id = String(entry.id)
	var tint: Color = entry.get("tint", UiTheme.BORDER_DIM)
	_style.border_color = tint.darkened(border_darken)
	_name.text = String(entry.get("name", ""))
	var caption := String(entry.get("caption", ""))
	_caption.text = caption
	# Vacía se vuelve invisible pero conserva su alto: el texto de abajo no
	# salta al pasar de una entrada a otra.
	_caption.modulate.a = 0.0 if caption.is_empty() else 1.0
	_text.text = String(entry.get("body", ""))
	if not changed:
		return
	_art.show_entry(entry)
	_fill_lines(entry.get("lines", []))
	_show_live(entry)
	if animate and not first:
		_play_swap()


## Pone en el dibujo grande la foto de la entrada que se muestra (la misma de
## su carta). Se ignora si la foto es de otra entrada.
func set_photo(photo_entry_id: String, photo: Texture2D) -> void:
	if photo_entry_id == entry_id:
		_art.set_photo(photo)


## True mientras hay un retrato 3D vivo (para los arneses de prueba).
func shows_live_model() -> bool:
	return (_raider_portrait != null and _raider_portrait.visible) \
			or (_enemy_portrait != null and _enemy_portrait.visible)


func _fill_lines(lines: Array) -> void:
	for child: Node in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	# Si ninguna línea lleva icono (un mapa, un arma), no se reserva su hueco.
	var any_icon := false
	for line: Variant in lines:
		if line is Dictionary and not String((line as Dictionary).get("stat", "")).is_empty():
			any_icon = true
	for line: Variant in lines:
		if not line is Dictionary:
			continue
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", line_separation)
		var stat := String((line as Dictionary).get("stat", ""))
		var chip := STAT_CHIP_SCENE.instantiate() as StatIconChip
		chip.chip_size = line_chip_size
		chip.show_stat(stat)
		# Una línea sin stat conserva el hueco de la ficha: los textos quedan
		# alineados en una sola columna.
		chip.modulate.a = 0.0 if stat.is_empty() else 1.0
		chip.visible = any_icon
		row.add_child(chip)
		var label := Label.new()
		label.text = String((line as Dictionary).get("text", ""))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.x = line_min_text_width
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", line_font_size)
		label.add_theme_color_override("font_color", line_color)
		row.add_child(label)
		_lines.add_child(row)
	# Las líneas nuevas cambian el alto mínimo del contenido en este mismo
	# frame; se vuelve a ajustar cuando el layout ya se asentó, o Content
	# quedaría con el alto de un estado intermedio.
	_fit_content.call_deferred()


## El retrato 3D giratorio, cuando la entrada tiene modelo y está descubierta.
## Un retrato que no aplica se oculta (un SubViewport oculto no dibuja).
func _show_live(entry: Dictionary) -> void:
	var art := String(entry.get("art", ""))
	var open := not bool(entry.get("locked", false))
	var raider := open and art == CollectionEntries.ART_RAIDER and entry.has("row")
	var enemy := open and art == CollectionEntries.ART_ENEMY \
			and not String(entry.get("scene", "")).is_empty()
	if raider:
		if _raider_portrait == null:
			_raider_portrait = RAIDER_PORTRAIT_SCENE.instantiate() as CharacterPortrait
			_live_slot.add_child(_raider_portrait)
			_raider_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_raider_portrait.show_character(entry.row as Dictionary)
	if _raider_portrait != null:
		_raider_portrait.visible = raider
		_raider_portrait.process_mode = Node.PROCESS_MODE_INHERIT if raider \
				else Node.PROCESS_MODE_DISABLED
	if enemy:
		if _enemy_portrait == null:
			_enemy_portrait = ENEMY_PORTRAIT_SCENE.instantiate() as EnemyPortrait
			_live_slot.add_child(_enemy_portrait)
		_enemy_portrait.show_enemy(String(entry.scene))
	elif _enemy_portrait != null:
		_enemy_portrait.clear()


## Entrada del contenido nuevo. Si llega otro cambio a medio camino, sigue
## desde donde va en vez de volver a empezar: recorrer cartas rápido con el
## control no hace parpadear el panel.
func _play_swap() -> void:
	var running := _swap_tween != null and _swap_tween.is_valid() \
			and _swap_tween.is_running()
	if running:
		_swap_tween.kill()
	else:
		_content.modulate.a = fade_from
		_content.position.x = slide_distance
	_swap_tween = create_tween().set_parallel()
	_swap_tween.set_ignore_time_scale(true)
	_swap_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_swap_tween.tween_property(_content, "modulate:a", 1.0, swap_time)
	_swap_tween.tween_property(_content, "position:x", 0.0, swap_time)


func _fit_content() -> void:
	if not is_inside_tree():
		return
	_body.custom_minimum_size.y = _content.get_combined_minimum_size().y
	_content.size = _body.size
