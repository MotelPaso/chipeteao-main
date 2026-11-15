class_name MapPostcard
extends Control
## Postal dibujada de un mapa para la Colección: cielo, sol, dos filas de
## cerros y suelo, pintados con la paleta de 4 colores del bioma en
## MapCatalog (suelo, sombra, acento, cielo). No usa ninguna imagen: se dibuja
## sola en _draw, así un bioma nuevo tiene postal sin trabajo extra.

@export_group("Postal")
## Altura del horizonte, como fracción del alto (0 = arriba).
@export_range(0.2, 0.9) var horizon: float = 0.62
## Radio del sol, como fracción del alto.
@export_range(0.02, 0.4) var sun_radius: float = 0.16
## Centro del sol, como fracción del ancho y del alto.
@export var sun_position: Vector2 = Vector2(0.72, 0.34)
## Alto de los cerros del fondo y del frente, como fracción del alto.
@export_range(0.0, 0.6) var far_hill_height: float = 0.3
@export_range(0.0, 0.6) var near_hill_height: float = 0.2
## Grosor del contorno de tinta de los cerros y del sol, en píxeles.
@export var outline_width: float = 3.0
## Cuánto se oscurecen los cerros del fondo (0-1).
@export_range(0.0, 1.0) var far_hill_darken: float = 0.15

## Colores del bioma: suelo, sombra, acento, cielo.
var _palette: Array[Color] = [
	Color(0.3, 0.56, 0.3), Color(0.15, 0.34, 0.19), Color(0.9, 0.7, 0.3), Color(0.79, 0.83, 0.72)]


func _ready() -> void:
	resized.connect(queue_redraw)


## Pinta la postal con la paleta de una fila de MapCatalog (4 colores). Con
## menos colores conserva los que ya tiene.
func show_palette(palette: Array) -> void:
	for i: int in mini(palette.size(), _palette.size()):
		if palette[i] is Color:
			_palette[i] = palette[i]
	queue_redraw()


func _draw() -> void:
	var ground := _palette[0]
	var shade := _palette[1]
	var accent := _palette[2]
	var sky := _palette[3]
	var horizon_y := size.y * horizon
	draw_rect(Rect2(Vector2.ZERO, size), sky)
	var sun := Vector2(size.x * sun_position.x, size.y * sun_position.y)
	draw_circle(sun, size.y * sun_radius + outline_width, UiTheme.INK)
	draw_circle(sun, size.y * sun_radius, accent)
	_draw_hills(horizon_y, size.y * far_hill_height, 2.0, 0.6,
			shade.lightened(far_hill_darken))
	_draw_hills(horizon_y + size.y * 0.06, size.y * near_hill_height, 3.0, 2.1, shade)
	var floor_top := horizon_y + size.y * 0.1
	draw_rect(Rect2(0.0, floor_top, size.x, size.y - floor_top), ground)
	draw_line(Vector2(0.0, floor_top), Vector2(size.x, floor_top), UiTheme.INK, outline_width)


## Una fila de cerros redondos: `waves` ondas a lo ancho, corridas `phase`.
func _draw_hills(base_y: float, height: float, waves: float, phase: float,
		color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 48
	for i: int in steps + 1:
		var t := float(i) / float(steps)
		var lift := (sin(t * TAU * waves * 0.5 + phase) * 0.5 + 0.5) * height
		points.append(Vector2(t * size.x, base_y - lift))
	var fill := points.duplicate()
	fill.append(Vector2(size.x, size.y))
	fill.append(Vector2(0.0, size.y))
	draw_colored_polygon(fill, color)
	draw_polyline(points, UiTheme.INK, outline_width, true)
