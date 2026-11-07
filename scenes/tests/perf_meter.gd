class_name PerfMeter
extends RefCounted
## Medidor del costo por frame que lleva el arnés de soak.
##
## POR QUÉ EXISTE. Todo soak corre con --fixed-fps 60: el tiempo de juego
## avanza 1/60 s por frame y el siguiente frame corre tan rápido como pueda
## la máquina. Así, el tiempo REAL por frame de un soak headless es el costo
## de CPU de un frame (scripts, física, árbol de escena) sin renderer, y el
## de un soak con ventana suma la GPU. La insignia de FPS del HUD solo da el
## número, no qué frame costó cuánto ni qué tan grande era la horda.
##
## QUÉ IMPRIME. Una línea `Perf` cada WINDOW_FRAMES frames dibujados (los
## percentiles de esa ventana junto a la horda y los conteos de nodos, para
## leer una ventana lenta contra lo que había en pantalla) y un `Perf summary`
## al salir. Los tiempos son milisegundos de reloj real entre dos _process
## seguidos del arnés. No usa Performance.TIME_PROCESS ni
## TIME_PHYSICS_PROCESS: no describen el frame en que se leen.
##
## CON VENTANA el reloj real incluye la GPU, pero en Mac solo es confiable
## en PANTALLA COMPLETA: un frame en ventana pasa por la sincronización del
## compositor aun con --disable-vsync, y --fullscreen corre sin tope. Tampoco
## usa el tiempo de GPU de RenderingServer: en Metal marca 0.00.
##
## Solo MIDE. Nada aquí cambia la partida ni lo que afirma un soak.

## Frames dibujados por línea Perf: 10 s de juego con --fixed-fps 60.
const WINDOW_FRAMES: int = 600
## Frames que se saltan antes de registrar: el frame de arranque carga la
## escena de la partida y todos sus preloads, y sería el máximo de cada soak.
const WARMUP_FRAMES: int = 30
## Un frame más lento que esto (ms) es un tirón que el jugador nota (dos vsync de 60 Hz).
const HITCH_MS: float = 33.3

var _last_usec: int = 0
var _frames: int = 0
var _window: PackedFloat32Array = PackedFloat32Array()
var _all: PackedFloat32Array = PackedFloat32Array()
var _hitches: int = 0
var _tree: SceneTree = null


func _init(tree: SceneTree) -> void:
	_tree = tree


## Lo llama el _process del arnés, una vez por frame dibujado.
func tick() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
		return
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_frames += 1
	if _frames <= WARMUP_FRAMES:
		return
	_window.append(ms)
	_all.append(ms)
	if ms > HITCH_MS:
		_hitches += 1
	if _window.size() >= WINDOW_FRAMES:
		_print_window()


func _print_window() -> void:
	var stats := _stats(_window)
	print(("Perf t=%.0f ms avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f"
			+ " enemies=%d nodes=%d orphans=%d"
			+ " draws=%d prims=%d objs3d=%d bodies=%d pairs=%d") % [
			RunState.run_time, stats[0], stats[1], stats[2], stats[3], stats[4],
			_tree.get_node_count_in_group(&"enemies"),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	_window.clear()


## Se imprime una vez, desde el _exit_tree del arnés.
func summary() -> void:
	if _all.is_empty():
		print("Perf summary: frames=0")
		return
	var stats := _stats(_all)
	var total := 0.0
	for ms in _all:
		total += ms
	print("Perf summary: frames=%d wall=%.1fs ms avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f hitches=%d" % [
			_all.size(), total / 1000.0, stats[0], stats[1], stats[2], stats[3],
			stats[4], _hitches])



## [promedio, p50, p95, p99, máximo] de una muestra de tiempos de frame.
static func _stats(sample: PackedFloat32Array) -> Array[float]:
	var sorted := sample.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += ms
	var last := sorted.size() - 1
	return [total / float(sorted.size()),
			sorted[int(last * 0.50)], sorted[int(last * 0.95)],
			sorted[int(last * 0.99)], sorted[last]]
