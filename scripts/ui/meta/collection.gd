extends Control
## Colección: el submenú del completista. Seis tarjetas grandes (Personajes,
## Enemigos, Mapas, Objetos, Tomos, Armas), cada una con su dibujo y su avance
## («3 / 12»), y arriba el porcentaje total. Elegir una abre su cuadrícula
## (CollectionBrowser.tscn); Volver y ui_cancel (B / Escape) regresan al menú
## principal.
##
## Cada tarjeta (MenuTile.tscn) es dueña de su aspecto y su movimiento, y su
## texto y color están en su instancia (Collection.tscn). Este script las
## conecta, escribe su avance, cablea el foco del control y devuelve el foco a
## la tarjeta desde la que saliste. Los datos los arma CollectionEntries.

## Edita aquí: qué categoría de CollectionEntries abre cada tarjeta, por el
## nombre de su nodo en Collection.tscn. El orden es el de la cuadrícula.
const TILE_CATEGORIES: Dictionary[StringName, String] = {
	&"RaidersTile": CollectionEntries.RAIDERS,
	&"EnemiesTile": CollectionEntries.ENEMIES,
	&"MapsTile": CollectionEntries.MAPS,
	&"ItemsTile": CollectionEntries.ITEMS,
	&"TomesTile": CollectionEntries.TOMES,
	&"WeaponsTile": CollectionEntries.WEAPONS,
}

@export_group("Textos")
## Insignia de arriba (%d = descubiertos, %d = total, %d = porcentaje).
@export var badge_format: String = "%d / %d — %d%%"
## Avance de cada tarjeta (%d = descubiertas, %d = total).
@export var tile_progress_format: String = "%d / %d"
## Indicación del botón de aceptar.
@export var choose_hint: String = "Elegir"
## Indicación del botón de cancelar.
@export var back_hint: String = "Volver"

@export_group("Movimiento")
## Espera (segundos) entre la primera tarjeta y la segunda en la entrada.
@export var tile_stagger: float = 0.05
## Cuánto se acorta cada espera respecto de la anterior (1 = todas iguales).
@export_range(0.1, 1.0) var tile_stagger_shrink: float = 0.8
## Duración (segundos) del fundido del título y del pie en la entrada.
@export var entrance_fade_time: float = 0.18

## Nombre de la tarjeta desde la que se salió, para devolverle el foco al
## volver (vive mientras dure la sesión).
static var _last_tile: StringName = &"RaidersTile"

var _tiles: Array[MenuTile] = []
var _entrance_tween: Tween = null

@onready var _layout: Control = %Layout
@onready var _top_bar: Control = %TopBar
@onready var _grid: GridContainer = %Tiles
@onready var _badge_label: Label = %BadgeLabel
@onready var _footer: Control = %Footer
@onready var _hints_slot: HBoxContainer = %HintsSlot
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UiTheme.style_button(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	_hints_slot.add_child(InputHints.build([
			["ui_accept", choose_hint], ["ui_cancel", back_hint]]))
	var found := 0
	var total := 0
	for tile_name: StringName in TILE_CATEGORIES:
		var tile := _grid.get_node_or_null(NodePath(tile_name)) as MenuTile
		if tile == null:
			push_warning("Collection: no tile named '%s' in %%Tiles" % tile_name)
			continue
		var category := TILE_CATEGORIES[tile_name]
		var progress := CollectionEntries.progress(category)
		found += progress.x
		total += progress.y
		tile.set_stat(tile_progress_format % [progress.x, progress.y])
		tile.pressed.connect(_open.bind(tile, category))
		_tiles.append(tile)
	_badge_label.text = badge_format % [found, total,
			roundi(100.0 * float(found) / float(maxi(total, 1)))]
	_link_focus()
	var remembered := _grid.get_node_or_null(NodePath(_last_tile)) as Control
	if remembered != null:
		remembered.grab_focus()
	elif not _tiles.is_empty():
		_tiles[0].grab_focus()
	else:
		_back_button.grab_focus()
	# Una sola entrada: las tarjetas entran una tras otra y el resto funde; el
	# contenido no se desliza además.
	MenuNav.arrive(_layout, false)
	_play_entrance()


## Esc / B sale, igual que en el resto de los menús.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _open(tile: MenuTile, category: String) -> void:
	CollectionBrowser.category = category
	if MenuNav.go(_layout, ScenePaths.COLLECTION_BROWSER, MenuNav.Direction.FORWARD):
		_last_tile = tile.name


func _on_back_pressed() -> void:
	MenuNav.go(_layout, ScenePaths.MAIN_MENU, MenuNav.Direction.BACK)


## Las tarjetas entran una tras otra con esperas que se acortan (se leen como
## una ola, no como una fila); el título y el pie solo funden. Decorativa: el
## foco y los clics funcionan desde el primer frame.
func _play_entrance() -> void:
	var delay := 0.0
	var step := tile_stagger
	for tile: MenuTile in _tiles:
		tile.play_entrance(delay)
		delay += step
		step *= tile_stagger_shrink
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = create_tween().set_parallel()
	_entrance_tween.set_ignore_time_scale(true)
	for section: Control in [_top_bar, _footer]:
		section.modulate.a = 0.0
		_entrance_tween.tween_property(section, "modulate:a", 1.0, entrance_fade_time) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Vecinos de foco a mano: las tarjetas en su cuadrícula (los bordes no dan la
## vuelta), bajo la última fila está Volver, y de Volver se sube a la última
## tarjeta usada.
func _link_focus() -> void:
	var columns := maxi(_grid.columns, 1)
	for i in _tiles.size():
		var tile := _tiles[i]
		var column := i % columns
		var last_in_row := column == columns - 1 or i + 1 >= _tiles.size()
		_wire(tile, SIDE_LEFT, _tiles[i - 1] if column > 0 else tile)
		_wire(tile, SIDE_RIGHT, tile if last_in_row else _tiles[i + 1])
		_wire(tile, SIDE_TOP, _tiles[i - columns] if i >= columns else tile)
		_wire(tile, SIDE_BOTTOM,
				_tiles[i + columns] if i + columns < _tiles.size() else _back_button)
		tile.focus_entered.connect(_wire.bind(_back_button, SIDE_TOP, tile))
	_wire(_back_button, SIDE_LEFT, _back_button)
	_wire(_back_button, SIDE_RIGHT, _back_button)
	_wire(_back_button, SIDE_BOTTOM, _back_button)
	if not _tiles.is_empty():
		_wire(_back_button, SIDE_TOP, _tiles[-1])


static func _wire(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))
