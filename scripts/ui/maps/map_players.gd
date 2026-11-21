class_name MapPlayers
extends GridContainer
## Panel «Jugadores» del mapa de Tab: una fila por ranura con la chapa del
## jugador en el color de su flecha en el mapa, su personaje, su barra de vida
## y sus puntos. Los caídos se quedan en la lista, marcados: saber que un
## compañero está en 0 de vida al otro lado del mapa es casi todo el propósito
## de este panel en co-op.

@export_group("Filas")
## Ancho mínimo de una fila con espacio, en píxeles: de aquí sale si las filas
## van en una o en dos columnas.
@export var row_min_width: float = 300.0
## Ancho mínimo de una fila en una celda chica, en píxeles.
@export var compact_row_min_width: float = 156.0
## Una fila más angosta que esto no escribe el nombre del personaje.
@export var name_min_row_width: float = 230.0
## Tamaño de la barra de vida con espacio, en píxeles.
@export var bar_size: Vector2 = Vector2(90.0, 16.0)
## Tamaño de la barra de vida en una celda chica, en píxeles.
@export var compact_bar_size: Vector2 = Vector2(54.0, 14.0)
## Radio de las esquinas de la barra, en píxeles.
@export var bar_corner_radius: int = 6
## Separación entre las piezas de una fila, en píxeles.
@export var row_separation: int = 8
@export_group("Letra")
## Tamaño de letra con espacio, en píxeles.
@export var font_size: int = 14
## Tamaño de letra en una celda chica, en píxeles.
@export var compact_font_size: int = 12
@export_group("Colores")
## Color del nombre del personaje y de su vida: tinta, porque van sobre una
## tarjeta de color.
@export var name_color: Color = UiTheme.INK
## Color de los puntos: tinta, porque van sobre una tarjeta de color.
@export var points_color: Color = UiTheme.INK
## Color de la chapa de un jugador caído.
@export var knocked_out_color: Color = UiTheme.ACCENT_RED
## Barra de vida cuando el HUD no está para dar su rampa de color.
@export var bar_color: Color = UiTheme.ACCENT_MINT
@export_group("Textos")
## Chapa del jugador; %d es su número (1-4).
@export var tag_format: String = UiTheme.PLAYER_TAG
## Chapa mientras está caído.
@export var knocked_out_format: String = "J%d K.O."
## Vida: actual y máxima. Solo se escribe cuando hay espacio.
@export var hp_format: String = "%d/%d"
## Puntos del jugador.
@export var points_format: String = UiTheme.POINTS_AMOUNT
## Nombre de una ranura sin personaje.
@export var empty_text: String = "—"

## En una celda chica se omite la vida en números y la letra se achica.
var compact: bool = false:
	set(value):
		if value == compact:
			return
		compact = value
		_apply_look()

## Una entrada por ranura: {tag, name, bar, fill, hp, points} con sus nodos y
## `down`, si la chapa está pintada de caído.
var _rows: Array[Dictionary] = []


func _ready() -> void:
	resized.connect(_fit_columns)


## Pone al día las filas; arma las que falten para `count` jugadores.
func show_party(count: int) -> void:
	while _rows.size() < count:
		_add_row(_rows.size())
	for slot in _rows.size():
		_refresh_row(slot)


func _add_row(slot: int) -> void:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", row_separation)
	_own(box)
	add_child(box)
	var tag := Label.new()
	UiTheme.style_badge(tag, UiTheme.INK, MapDraw.player_color(slot))
	_own(tag)
	box.add_child(tag)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_color", name_color)
	_own(name_label)
	box.add_child(name_label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = bar_size
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	_own(bar)
	box.add_child(bar)
	var fill := UiTheme.style_bar(bar, bar_color, bar_corner_radius)
	var hp := Label.new()
	hp.add_theme_color_override("font_color", name_color)
	_own(hp)
	box.add_child(hp)
	var points := Label.new()
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points.add_theme_font_override("font", UiTheme.display_font())
	points.add_theme_color_override("font_color", points_color)
	_own(points)
	box.add_child(points)
	_rows.append({"tag": tag, "name": name_label, "bar": bar, "fill": fill, "hp": hp,
			"points": points, "down": false})
	_apply_look()


func _refresh_row(slot: int) -> void:
	var row: Dictionary = _rows[slot]
	var body := PartySlots.raider_at(get_tree(), slot)
	var character := CharacterCatalog.by_id_or_default(Coop.character_for_slot(slot))
	(row["name"] as Label).text = String(character.get("display_name", empty_text))
	var health := Health.find_in(body) if body != null else null
	var current := health.current_hp if health != null else 0.0
	var maximum := health.max_hp if health != null else 1.0
	var down := body == null or body.is_in_group(&"downed_players") or current <= 0.0
	var tag: Label = row["tag"]
	tag.text = (knocked_out_format if down else tag_format) % (slot + 1)
	# La chapa se vuelve a pintar solo cuando el jugador cae o se levanta.
	if down != bool(row["down"]):
		row["down"] = down
		UiTheme.style_badge(tag, UiTheme.INK,
				knocked_out_color if down else MapDraw.player_color(slot))
	var bar: ProgressBar = row["bar"]
	bar.max_value = maxf(maximum, 1.0)
	bar.value = current
	UiTheme.recolor_fill(row["fill"], _hp_color(current, maximum))
	(row["hp"] as Label).text = hp_format % [ceili(current), roundi(maximum)]
	var points: Variant = body.get("points") if body != null else null
	(row["points"] as Label).text = points_format % (int(points) if points != null else 0)


## La rampa de color de la barra de vida del HUD, para que una vida baja se
## vea igual aquí que allá. La pide por el grupo "hud".
func _hp_color(current: float, maximum: float) -> Color:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method(&"hp_color"):
		return hud.call(&"hp_color", current, maximum)
	return bar_color


func _apply_look() -> void:
	var letter := compact_font_size if compact else font_size
	for row: Dictionary in _rows:
		for key: String in ["tag", "name", "hp", "points"]:
			(row[key] as Label).add_theme_font_size_override("font_size", letter)
		(row["hp"] as Label).visible = not compact
		(row["bar"] as Control).custom_minimum_size = compact_bar_size if compact else bar_size
	_fit_columns()


## Una o dos columnas según el ancho, y el nombre solo si la fila da para él.
func _fit_columns() -> void:
	var minimum := compact_row_min_width if compact else row_min_width
	columns = clampi(int(size.x / maxf(minimum, 1.0)), 1, 2)
	var show_names := size.x / float(columns) >= name_min_row_width
	for row: Dictionary in _rows:
		(row["name"] as Control).visible = show_names


## Cada Control que se crea en código: nunca toma foco (Tab es ui_focus_next)
## ni recibe el mouse (el mundo sigue vivo detrás).
func _own(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
