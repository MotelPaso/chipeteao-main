class_name MapStats
extends GridContainer
## Las estadísticas del jugador en el mapa de Tab: una celda por fila de
## MapOverlay.STAT_ROWS, con el nombre a la izquierda y el valor a la derecha.
## Va sobre una tarjeta de color, así que todo es tinta: un valor que subió o
## bajó se escribe dentro de una chapa oscura (verde si subió, rojo si bajó),
## como el dato vivo de las tarjetas del menú, y uno en cero queda apagado.
## Así se ve de un vistazo qué cambió. Las columnas salen del ancho
## disponible, de modo que la misma grilla sirve en solitario y en una celda
## de co-op.

@export_group("Celdas")
## Ancho mínimo de una estadística (nombre y valor) con espacio, en píxeles.
## De aquí sale cuántas columnas caben.
@export var cell_min_width: float = 230.0
## Ancho mínimo de una estadística (nombre y valor) en una celda chica, en píxeles.
@export var compact_cell_min_width: float = 148.0
## Tope de columnas, por ancho que sea el panel.
@export var max_columns: int = 4
## Separación entre el nombre y el valor, en píxeles.
@export var name_value_gap: int = 8
@export_group("Letra")
## Tamaño de letra con espacio, en píxeles.
@export var font_size: int = 15
## Tamaño de letra en una celda chica, en píxeles.
@export var compact_font_size: int = 12
@export_group("Colores")
## Color del nombre de una estadística con valor.
@export var name_color: Color = UiTheme.INK
## Color del nombre y del valor de una estadística en cero.
@export var idle_color: Color = Color(UiTheme.INK, 0.5)
## Color del texto de un valor que subió, dentro de su chapa.
@export var raised_color: Color = UiTheme.ACCENT_MINT
## Color del texto de un valor que bajó, dentro de su chapa.
@export var lowered_color: Color = UiTheme.ACCENT_RED
@export_group("Chapa del valor")
## Fondo de la chapa de un valor que cambió.
@export var chip_color: Color = UiTheme.TILE_BG
## Radio de sus esquinas, en píxeles.
@export var chip_radius: int = 8
## Margen interior de la chapa (horizontal, vertical), en píxeles. Un valor en
## cero guarda el mismo margen sin fondo, para que los números queden alineados.
@export var chip_margin: Vector2 = Vector2(8.0, 0.0)
@export_group("Textos")
## Valor de una estadística que no se pudo leer.
@export var empty_text: String = "—"

## En una celda chica las filas en cero se ocultan y la letra se achica.
var compact: bool = false:
	set(value):
		if value == compact:
			return
		compact = value
		_apply_look()

var _rows: Array[Dictionary] = []
## Fondo del valor: la chapa y su gemelo vacío, compartidos por todas las celdas.
var _chip_box: StyleBoxFlat = null
var _idle_box: StyleBoxEmpty = null
## Una entrada por fila: {box, name, value, sign} con sus nodos y el signo de
## lo último que mostró (-1, 0, 1).
var _cells: Array[Dictionary] = []


func _ready() -> void:
	resized.connect(_fit_columns)


## Las filas a mostrar, en orden (MapOverlay.STAT_ROWS). Una sola vez.
func setup(rows: Array[Dictionary]) -> void:
	_rows = rows
	_chip_box = UiTheme.flat(chip_color, chip_radius)
	_idle_box = StyleBoxEmpty.new()
	for box: StyleBox in [_chip_box, _idle_box]:
		box.content_margin_left = chip_margin.x
		box.content_margin_right = chip_margin.x
		box.content_margin_top = chip_margin.y
		box.content_margin_bottom = chip_margin.y
	for row: Dictionary in rows:
		var box := HBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", name_value_gap)
		_own(box)
		add_child(box)
		var name_label := Label.new()
		name_label.text = String(row.label)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Un nombre largo se recorta con puntos antes que ensanchar la celda.
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_own(name_label)
		box.add_child(name_label)
		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_override("font", UiTheme.display_font())
		_own(value_label)
		box.add_child(value_label)
		_cells.append({"box": box, "name": name_label, "value": value_label, "sign": 0})
	_apply_look()


## Escribe los valores de `stats`; null deja todo en empty_text.
func show_stats(stats: PlayerStats) -> void:
	for index in _cells.size():
		var cell: Dictionary = _cells[index]
		var row: Dictionary = _rows[index]
		var raw: Variant = stats.get(String(row.property)) if stats != null else null
		var bonus := _bonus(float(raw), String(row.show)) if raw != null else 0.0
		var value_label: Label = cell["value"]
		value_label.text = _bonus_text(bonus, String(row.show)) if raw != null else empty_text
		# El signo se mide contra el valor de partida de la fila, si tiene uno.
		var base: Variant = stats.get(String(row.get("base_property", ""))) \
				if stats != null and row.has("base_property") else null
		var gain := bonus - (_bonus(float(base), String(row.show)) if base != null else 0.0)
		cell["sign"] = signi(roundi(gain * 100.0)) if raw != null else 0
		_paint(cell)


## Lo que la fila le suma al jugador, como número con signo: una fracción para
## los porcentajes (0.25 = +25%) y la cantidad tal cual para "flat".
##   "multiplier"    multiplicador que parte en 1.0   (1.25 -> 0.25)
##   "fraction"      fracción que parte en 0          (0.1 -> 0.1)
##   "attack_speed"  el multiplicador de enfriamiento leído como velocidad de
##                   ataque y en POSITIVO (GLOSARIO regla 7): 0.8 -> 0.25
##   "flat"          número entero                    (3 -> 3)
func _bonus(value: float, shown: String) -> float:
	match shown:
		"multiplier":
			return value - 1.0
		"attack_speed":
			return 1.0 / maxf(value, 0.01) - 1.0
	return value


func _bonus_text(bonus: float, shown: String) -> String:
	if shown == "flat":
		return "%+d" % roundi(bonus)
	return "%+d%%" % roundi(bonus * 100.0)


## Colores, chapa y visibilidad de una celda según el signo de su valor.
func _paint(cell: Dictionary) -> void:
	var sign_now := int(cell["sign"])
	var value_label: Label = cell["value"]
	var name_label: Label = cell["name"]
	var value_color := idle_color
	if sign_now > 0:
		value_color = raised_color
	elif sign_now < 0:
		value_color = lowered_color
	value_label.add_theme_color_override("font_color", value_color)
	value_label.add_theme_stylebox_override("normal", _idle_box if sign_now == 0 else _chip_box)
	name_label.add_theme_color_override("font_color", idle_color if sign_now == 0 else name_color)
	(cell["box"] as Control).visible = not (compact and sign_now == 0)


func _apply_look() -> void:
	var letter := compact_font_size if compact else font_size
	for index in _cells.size():
		var cell: Dictionary = _cells[index]
		var row: Dictionary = _rows[index]
		# En una celda chica, el nombre corto de la fila si tiene uno.
		(cell["name"] as Label).text = String(row.get("short", row.label)) if compact \
				else String(row.label)
		(cell["name"] as Label).add_theme_font_size_override("font_size", letter)
		(cell["value"] as Label).add_theme_font_size_override("font_size", letter)
		_paint(cell)
	_fit_columns()


## Tantas columnas como celdas de ancho mínimo caben.
func _fit_columns() -> void:
	var minimum := compact_cell_min_width if compact else cell_min_width
	columns = clampi(int(size.x / maxf(minimum, 1.0)), 1, max_columns)


## Cada Control que se crea en código: nunca toma foco (Tab es ui_focus_next)
## ni recibe el mouse (el mundo sigue vivo detrás).
func _own(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
