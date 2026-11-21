extends ScrollContainer
## La columna de paneles del mapa de Tab (MapOverlay.tscn > Side): recorta los
## paneles para que nunca se salgan de la celda del jugador, y no tiene barras
## porque nada del mapa recibe el mouse ni el foco (Tab es ui_focus_next).
## Si los paneles no caben ni en el escalón más apretado, MapOverlay prende
## `auto_scroll` y la columna se desliza sola: se queda quieta arriba, baja
## despacio hasta el fondo, espera y vuelve. Así lo de abajo también se lee.
## Sin class_name: map_overlay.gd la precarga como tipo (MapSideScroll).

@export_group("Deslizamiento")
## Segundos que la columna se queda quieta arriba y abajo.
@export var scroll_pause: float = 2.0
## Velocidad a la que baja y sube la columna, en píxeles por segundo.
@export var scroll_speed: float = 30.0

## Encendido, la columna se desliza cuando sus paneles no caben; apagado,
## vuelve arriba y se queda ahí.
var auto_scroll: bool = false:
	set(value):
		auto_scroll = value
		if not value:
			rewind()

## Segundos dentro del ciclo arriba-abajo-arriba.
var _scroll_time: float = 0.0


func _process(delta: float) -> void:
	if not auto_scroll or not is_visible_in_tree() or get_child_count() == 0:
		return
	var reach := (get_child(0) as Control).get_combined_minimum_size().y - size.y
	if reach <= 0.5:
		rewind()
		return
	var travel := reach / maxf(scroll_speed, 1.0)
	_scroll_time = fmod(_scroll_time + delta, 2.0 * (scroll_pause + travel))
	scroll_vertical = roundi(reach * _along(_scroll_time, travel))


## Vuelve arriba y reinicia el ciclo (al abrir el mapa).
func rewind() -> void:
	_scroll_time = 0.0
	scroll_vertical = 0


## Dónde va la columna en el ciclo, de 0 (arriba) a 1 (abajo): quieta arriba,
## baja, quieta abajo y sube; la bajada y la subida arrancan y frenan suave.
func _along(time: float, travel: float) -> float:
	var down_end := scroll_pause + travel
	var up_start := down_end + scroll_pause
	if time < scroll_pause:
		return 0.0
	if time < down_end:
		return smoothstep(0.0, 1.0, (time - scroll_pause) / travel)
	if time < up_start:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (time - up_start) / travel)
