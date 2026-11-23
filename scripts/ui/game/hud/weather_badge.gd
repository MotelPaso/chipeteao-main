class_name WeatherBadge
extends Label
## Chips con los climas activos y sus segundos restantes, colgados bajo el
## reloj (es hijo de %TimerLabel, así viaja con él). Luna, lluvia y desastre
## pueden coincidir: este Label muestra el primero y crea una copia de sí
## mismo debajo por cada clima extra. Se lee del director (grupo
## "world_director", propiedad active_weathers) en vez de que él lo empuje: el
## chip es una vista. El color del texto de la escena es el de un grupo de
## clima sin color propio. El nombre sale de la columna display_name de
## WeatherCatalog (weather_catalog.gd); un id sin fila se muestra tal cual.

@export_group("Chip")
## Segundos entre lecturas del clima.
@export var refresh_seconds: float = 0.2
## Texto del chip: nombre del clima y segundos restantes.
@export var text_format: String = "%s %ds"
## Píxeles entre un chip y el de abajo cuando hay varios climas a la vez.
@export var stack_gap: float = 6.0
## Color del texto por GRUPO de clima (moon, rain, disaster), no por id: tres
## colores se leen como tres tipos de peligro; nueve se leerían como decoración.
@export var group_colors: Dictionary[String, Color] = {
	"moon": Color(0.85, 0.75, 1.0),
	"rain": Color(0.55, 0.9, 1.0),
	"disaster": Color(1.0, 0.55, 0.3),
}

var _signature: String = ""
var _refresh_left: float = 0.0
var _default_color: Color = Color.WHITE
## Copias de este chip para el segundo y tercer clima.
var _extra_chips: Array[Label] = []


func _ready() -> void:
	_default_color = get_theme_color(&"font_color")
	UiTheme.style_badge(self, _default_color)


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	_refresh()


func _refresh() -> void:
	var director := get_tree().get_first_node_in_group("world_director")
	var live: Variant = director.get("active_weathers") if director != null else null
	var weathers: Array = live as Array if live is Array else []
	var signature := ""
	for weather: Dictionary in weathers:
		signature += "%s|%d;" % [String(weather.get("id", "")), _seconds(weather)]
	if signature == _signature:
		return
	_signature = signature
	visible = not weathers.is_empty()
	for i in weathers.size():
		_show_on(self if i == 0 else _extra_chip(i - 1), weathers[i])
	for i in range(maxi(weathers.size() - 1, 0), _extra_chips.size()):
		_extra_chips[i].visible = false


func _show_on(chip: Label, weather: Dictionary) -> void:
	chip.visible = true
	chip.text = text_format % [_display_name(String(weather.get("id", ""))), _seconds(weather)]
	chip.add_theme_color_override("font_color",
			group_colors.get(String(weather.get("group", "")), _default_color))


## La copia número `index` (0 = la del segundo clima), creada la primera vez.
func _extra_chip(index: int) -> Label:
	while _extra_chips.size() <= index:
		var chip := Label.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_font_override("font", get_theme_font(&"font"))
		chip.add_theme_font_size_override("font_size", get_theme_font_size(&"font_size"))
		UiTheme.style_badge(chip, _default_color)
		add_child(chip)
		_extra_chips.append(chip)
	var extra := _extra_chips[index]
	extra.position = Vector2(0.0, (size.y + stack_gap) * float(index + 1))
	return extra


func _seconds(weather: Dictionary) -> int:
	return ceili(maxf(float(weather.get("time_left", 0.0)), 0.0))


func _display_name(weather_id: String) -> String:
	return String(WeatherDirector.weather_row(weather_id).get("display_name", weather_id))
