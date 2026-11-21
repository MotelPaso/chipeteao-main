class_name MapChip
extends HBoxContainer
## Una ficha de los paneles del mapa de Tab (MapChip.tscn): la misma casilla
## de color de las franjas del HUD, en chico, seguida del nombre completo y de
## su etiqueta (nivel, copias, pilas o segundos). Así el mapa también sirve
## para aprender qué es cada casilla del HUD. En una celda chica el nombre se
## oculta y queda la casilla con su etiqueta.

## Lo que la ficha pinta aparte de la etiqueta (nombre, glifo, color e
## icono), como texto: si cambia, la ficha se vuelve a pintar entera.
var _look: String = ""

@onready var _tile: LoadoutTile = $Tile
@onready var _name: Label = $Name
@onready var _tag: Label = $Tag


func _ready() -> void:
	_tag.add_theme_font_override("font", UiTheme.display_font())


## Pinta la ficha para `entry`, una entrada de las franjas del HUD: {glyph,
## library, entry_id, color, corner, tip, icon}. Llamar después de agregarla
## al árbol.
func show_entry(entry: Dictionary, compact: bool) -> void:
	_look = _look_of(entry)
	# La esquina va aparte, en Tag: dentro de una casilla tan chica no se lee.
	var tile_entry := entry.duplicate()
	tile_entry["corner"] = ""
	_tile.show_entry(tile_entry)
	_name.text = String(entry.tip)
	_name.visible = not compact
	set_tag(String(entry.corner))


## Pone al día la ficha con `entry`, de la misma biblioteca e id que la que
## muestra: si solo cambió la etiqueta escribe esa; si cambió algo más (un
## arma que evoluciona cambia nombre, glifo y color), la pinta de nuevo.
func update_entry(entry: Dictionary, compact: bool) -> void:
	if _look_of(entry) != _look:
		show_entry(entry, compact)
		return
	set_tag(String(entry.corner))


## Cambia la etiqueta; un texto vacío la oculta.
func set_tag(text: String) -> void:
	_tag.text = text
	_tag.visible = not text.is_empty()


static func _look_of(entry: Dictionary) -> String:
	return "%s|%s|%s|%s" % [entry.get("tip", ""), entry.get("glyph", ""),
			entry.get("color", Color.WHITE), entry.get("icon", "")]
