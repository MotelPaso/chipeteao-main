class_name WeatherBadge
extends Label
## Chip con el clima activo y sus segundos restantes, colgado bajo el reloj
## (es hijo de %TimerLabel, así viaja con él). Se lee del director (grupo
## "world_director", propiedad active_weather) en vez de que él lo empuje: el
## chip es una vista. El color del texto de la escena es el de un grupo de
## clima sin color propio. El nombre sale de la columna display_name de
## WeatherDirector.WEATHER_CATALOG (weather_director.gd); un id sin fila se
## muestra tal cual.

## Segundos entre lecturas del clima.
@export var refresh_seconds: float = 0.2
## Texto del chip: nombre del clima y segundos restantes.
@export var text_format: String = "%s %ds"
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
	var live: Variant = director.get("active_weather") if director != null else null
	var weather := live as Dictionary if live is Dictionary else {}
	if weather.is_empty():
		visible = false
		_signature = ""
		return
	var weather_id := String(weather.get("id", ""))
	var seconds := ceili(maxf(float(weather.get("time_left", 0.0)), 0.0))
	var signature := "%s|%d" % [weather_id, seconds]
	if signature == _signature:
		return
	_signature = signature
	visible = true
	text = text_format % [_display_name(weather_id), seconds]
	add_theme_color_override("font_color",
			group_colors.get(String(weather.get("group", "")), _default_color))


func _display_name(weather_id: String) -> String:
	return String(WeatherDirector.weather_row(weather_id).get("display_name", weather_id))
