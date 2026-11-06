class_name PerfProbe
extends Label
## Sonda de depuración (no es para el jugador), arriba a la derecha: FPS y
## conteos de enemigos, gemas, disparos y proyectiles enemigos, más el estado
## de los pools, para verificar rendimiento. Viene apagada: se enciende con
## `enabled` o lanzando el juego con BONK_PERF=1. El texto queda en inglés
## como los logs.

## Variable de entorno que enciende la sonda (verificación headless).
const ENV := "BONK_PERF"
const TEXT_FORMAT := "FPS %d | enemies %d | gems %d | shots %d | bolts %d\npools (created/parked): %s"

## Muestra la sonda (solo para desarrollo).
@export var enabled: bool = false
## Segundos entre lecturas.
@export var refresh_seconds: float = 0.25

var _refresh_left: float = 0.0


func _ready() -> void:
	visible = enabled or OS.get_environment(ENV) == "1"
	set_process(visible)


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	var tree := get_tree()
	text = TEXT_FORMAT % [
			Engine.get_frames_per_second(),
			tree.get_node_count_in_group(&"enemies"),
			tree.get_node_count_in_group(&"xp_gems"),
			tree.get_node_count_in_group(&"player_shots"),
			tree.get_node_count_in_group(&"enemy_bolts"),
			Pools.stats_line()]
