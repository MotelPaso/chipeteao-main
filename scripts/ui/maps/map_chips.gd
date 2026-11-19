class_name MapChips
extends HFlowContainer
## Una tira de fichas (MapChip) que salta de línea cuando no cabe: el equipo
## del jugador o sus power-ups activos en el mapa de Tab. Recibe las mismas
## entradas que las franjas del HUD y solo rehace las fichas cuando cambia
## cuáles son; si son las mismas, cada ficha se pone al día en su lugar: la
## etiqueta (los segundos de un power-up) o, si cambió, su nombre, glifo y
## color (un arma que evoluciona sigue siendo la misma ficha).

const CHIP_SCENE := preload("res://scenes/ui/maps/MapChip.tscn")

@export_group("Fichas")
## Espacio en blanco entre familias (armas, tomos, objetos), en píxeles.
@export var family_gap: float = 6.0
@export_group("Textos")
## Lo que se muestra cuando no hay ninguna ficha.
@export var empty_text: String = "—"
## Color del texto que se muestra cuando no hay ninguna ficha.
@export var empty_color: Color = Color(UiTheme.INK, 0.5)
## Tamaño de letra de ese texto, en píxeles.
@export var empty_font_size: int = 14

## En una celda chica las fichas van sin nombre.
var compact: bool = false:
	set(value):
		if value == compact:
			return
		compact = value
		_shown = ""

## Las fichas en pantalla, como texto: cambia solo cuando hay que rehacerlas.
var _shown: String = "?"
var _chips: Array[MapChip] = []


## Muestra `entries` (ver MapChip.show_entry), en orden.
func show_entries(entries: Array[Dictionary]) -> void:
	var shape := "%s|" % compact
	for entry: Dictionary in entries:
		shape += "%s/%s;" % [entry.library, entry.entry_id]
	if shape != _shown:
		_shown = shape
		_rebuild(entries)
		return
	for index in mini(entries.size(), _chips.size()):
		_chips[index].update_entry(entries[index], compact)


func _rebuild(entries: Array[Dictionary]) -> void:
	for child: Node in get_children():
		# Primero fuera del contenedor: queue_free() recién actúa al final del
		# cuadro, y las fichas viejas se acomodarían junto a las nuevas.
		remove_child(child)
		child.queue_free()
	_chips.clear()
	if entries.is_empty():
		add_child(_empty_label())
		return
	var last_library := ""
	for entry: Dictionary in entries:
		var library := String(entry.library)
		if not last_library.is_empty() and library != last_library:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(family_gap, 0.0)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(spacer)
		last_library = library
		var chip: MapChip = CHIP_SCENE.instantiate()
		add_child(chip)
		chip.show_entry(entry, compact)
		_chips.append(chip)


func _empty_label() -> Label:
	var label := Label.new()
	label.text = empty_text
	label.add_theme_color_override("font_color", empty_color)
	label.add_theme_font_size_override("font_size", empty_font_size)
	label.focus_mode = Control.FOCUS_NONE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
