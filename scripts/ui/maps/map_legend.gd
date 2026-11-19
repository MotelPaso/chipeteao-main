class_name MapLegend
extends HFlowContainer
## Leyenda del mapa de Tab: una fila por tipo de marcador que está a la vista
## AHORA, con la misma forma y el mismo color con que se dibuja en el mapa.
## Lista solo lo que hay: una leyenda con los trece tipos tapa medio mapa en
## una celda de co-op, y la mayoría no estaría en pantalla. Los nombres y las
## formas salen de MapDraw.MARKER_LABELS y MARKER_STYLES: un tipo agregado ahí
## aparece aquí sin tocar nada.

@export_group("Filas")
## Lado del recuadro donde se dibuja la muestra de cada fila, en píxeles.
@export var swatch_side: float = 16.0
## Tamaño de la muestra respecto del `size` del marcador en MARKER_STYLES.
@export var swatch_scale: float = 1.2
## Separación entre la muestra y su texto, en píxeles.
@export var row_separation: int = 5
@export_group("Letra")
## Tamaño de letra con espacio, en píxeles.
@export var font_size: int = 14
## Tamaño de letra en una celda chica, en píxeles.
@export var compact_font_size: int = 12
## Color del texto. La leyenda va sobre el fondo, no sobre una tarjeta.
@export var text_color: Color = UiTheme.TEXT_BRIGHT
## Grosor del contorno de tinta del texto, en píxeles.
@export var outline_size: int = 5

## En una celda chica la letra se achica.
var compact: bool = false:
	set(value):
		if value == compact:
			return
		compact = value
		_shown = []

## Tipos que la leyenda muestra ahora, en orden.
var _shown: Array[StringName] = [&"?"]


## Muestra una fila por cada tipo de `kinds` (ver MapDraw.legend_kinds). Solo
## rehace las filas cuando la lista cambió.
func show_kinds(kinds: Array[StringName]) -> void:
	if kinds == _shown:
		return
	_shown = kinds.duplicate()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for kind: StringName in kinds:
		add_child(_row(kind))


func _row(kind: StringName) -> Control:
	var style: Dictionary = MapDraw.MARKER_STYLES[kind]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", row_separation)
	_own(row)
	var swatch := Control.new()
	swatch.custom_minimum_size = Vector2(swatch_side, swatch_side)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_own(swatch)
	swatch.draw.connect(_draw_swatch.bind(swatch, style))
	row.add_child(swatch)
	var label := Label.new()
	label.text = MapDraw.MARKER_LABELS[kind]
	label.add_theme_font_size_override("font_size", compact_font_size if compact else font_size)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_outline_color", UiTheme.OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", outline_size)
	_own(label)
	row.add_child(label)
	return row


## La muestra: el marcador tal como sale en el mapa, apuntando hacia arriba.
func _draw_swatch(swatch: Control, style: Dictionary) -> void:
	# Las formas de MARKER_STYLES miden distinto con el mismo `size`; se
	# normaliza para que ninguna muestra se salga de su recuadro.
	var radius := minf(float(style["size"]) * swatch_scale, swatch_side * 0.34)
	MapDraw.draw_glyph(swatch, swatch.size * 0.5, String(style["shape"]), style["color"], radius)


## Cada Control que se crea en código: nunca toma foco (Tab es ui_focus_next)
## ni recibe el mouse (el mundo sigue vivo detrás).
func _own(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
