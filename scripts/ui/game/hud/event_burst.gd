class_name EventBurst
extends PanelContainer
## Aviso de los eventos del pulso por minuto. Cuando salen varios a la vez
## los muestra juntos, sin fondo: una fila por evento, que entran una tras
## otra con su color. Con uno solo, el HUD usa el cartel
## normal (AnnounceBanner). Quien llama pasa el tipo de cada fila
## ("weather", "horde"); el color lo decide este nodo.

@export_group("Filas")
## Tamaño de letra de cada fila, en píxeles.
@export var row_font_size: int = 20
## Texto antes de cada fila.
@export var row_bullet: String = ""
## Color de las filas de clima (lunas, lluvias, desastres).
@export var weather_color: Color = Color(0.78, 0.62, 1.0)
## Color de la fila de horda.
@export var horde_color: Color = UiTheme.ACCENT_RED
## Color de las filas sin tipo.
@export var other_color: Color = Color(1.0, 1.0, 1.0)
@export_group("Tiempos")
## Segundos entre la entrada de una fila y la siguiente.
@export var row_stagger: float = 0.3
## Segundos que tarda cada fila en aparecer.
@export var row_fade_in: float = 0.2
## Escala del golpe de cada fila al entrar.
@export var row_pop_scale: float = 1.15
## Segundos en pantalla después de que entra la última fila.
@export var hold_time: float = 3.5
## Segundos de desvanecido.
@export var fade_out_time: float = 0.6

var _tween: Tween
var _rows: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)


## Muestra una fila por evento; cada fila es {"text", "kind"}.
func show_events(rows: Array[Dictionary]) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for child: Node in _rows.get_children():
		child.queue_free()
	var labels: Array[Label] = []
	for row: Dictionary in rows:
		var label := _make_label(row_bullet + String(row["text"]), row_font_size,
				_kind_color(String(row.get("kind", ""))))
		label.modulate.a = 0.0
		_rows.add_child(label)
		labels.append(label)
	visible = true
	modulate.a = 1.0
	reset_size()
	_tween = create_tween()
	for label: Label in labels:
		_tween.tween_interval(row_stagger)
		_tween.tween_callback(UiTheme.pop.bind(label, row_pop_scale, 0.25))
		_tween.tween_property(label, "modulate:a", 1.0, row_fade_in)
	_tween.tween_interval(hold_time)
	_tween.tween_property(self, "modulate:a", 0.0, fade_out_time)
	_tween.tween_callback(hide)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UiTheme.display_font(1))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	return label


func _kind_color(kind: String) -> Color:
	match kind:
		"weather":
			return weather_color
		"horde":
			return horde_color
	return other_color
