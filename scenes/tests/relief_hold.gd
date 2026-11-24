class_name ReliefHold
extends RefCounted
## La SONDA DE LLEGADA de ReliefProbe, solo con BONK_HOLD_AT=high|ravine|bridge:
## deja al raider quieto en su punto (ReliefProbe lo elige) y cuenta las
## LLEGADAS: enemigos que aparecieron 3 m o más arriba o abajo de su nivel y
## se le acercaron a 3 m (y a no más de 1.5 m de altura). Imprime una línea
## `Probe hold:` por ventana de 20 s y un resumen al salir; el resumen dice
## además cuántos enemigos lo alcanzaron en total (`reached`), hayan aparecido
## en su nivel o en otro. Si la receta de la etapa no tiene ese lugar, lo dice
## en `Probe hold: at=… missing` y no lo retiene.

const ENV := "BONK_HOLD_AT"
const PLACES: Array[String] = ["high", "ravine", "bridge"]
## La sonda (ver la cabecera), en metros y segundos.
const SPAWN_GAP: float = 3.0
const ARRIVE_RANGE: float = 3.0
const ARRIVE_LEVEL: float = 1.5
const WINDOW: float = 20.0
const WINDOWS_FROM: float = 30.0
## Metros que el raider retenido puede correrse antes de volver a su punto.
const DRIFT: float = 1.0

## El lugar pedido (high, ravine o bridge), o "" sin BONK_HOLD_AT.
var place: String = ""
## Dónde está retenido el líder, y si lo está.
var point: Vector3 = Vector3.INF
var holding: bool = false

## Enemigos ya vistos: true si aparecieron a otro nivel (candidatos a llegada).
var _candidates: Dictionary[int, bool] = {}
var _arrived: Dictionary[int, bool] = {}
## Enemigos que se le acercaron al retenido, hayan aparecido donde sea.
var _reached: Dictionary[int, bool] = {}
var _window: int = 0
var _window_arrivals: int = 0
var _arrivals: int = 0
var _empty_windows: int = 0


func _init() -> void:
	place = OS.get_environment(ENV).strip_edges()
	if not place.is_empty() and not PLACES.has(place):
		push_error("ArenaProbe: %s must be one of %s, got '%s'" % [ENV, PLACES, place])
		place = ""


## Una etapa nueva: nadie está retenido todavía.
func reset() -> void:
	holding = false
	point = Vector3.INF


## Retiene a `lead` en `at` (Vector3.INF: la receta `recipe` no tiene ese lugar).
func start(at: Vector3, recipe: StringName, lead: CharacterBody3D) -> void:
	point = at
	if point == Vector3.INF:
		# La receta de esta etapa no tiene ese lugar (un mapa sin cañón ni
		# puente): se dice en su línea y el raider no se retiene.
		print("Probe hold: at=%s missing (recipe=%s has no such place)" % [place, recipe])
		return
	holding = true
	_candidates.clear()
	_arrived.clear()
	_reached.clear()
	_window = 0
	_window_arrivals = 0
	lead.global_position = point + Vector3.UP * 0.2
	lead.velocity = Vector3.ZERO
	print("Probe hold: at=%s point=(%.1f, %.1f, %.1f)" % [place, point.x, point.y, point.z])


## True si el líder retenido se corrió y tiene que volver a su punto.
func drifted(lead: Node3D) -> bool:
	return Vector2(lead.global_position.x - point.x,
			lead.global_position.z - point.z).length() > DRIFT


## Cuenta las llegadas de este frame; `clock` es el reloj de la etapa.
func watch(tree: SceneTree, lead: CharacterBody3D, clock: float) -> void:
	var at := lead.global_position
	for node: Node in tree.get_nodes_in_group(&"enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var id := body.get_instance_id()
		var where := body.global_position
		if not _candidates.has(id):
			_candidates[id] = absf(where.y - point.y) >= SPAWN_GAP
		var close := Vector2(where.x - at.x, where.z - at.z).length() <= ARRIVE_RANGE \
				and absf(where.y - at.y) <= ARRIVE_LEVEL
		if close:
			_reached[id] = true
		if not _candidates[id] or _arrived.has(id):
			continue
		if close:
			_arrived[id] = true
			_arrivals += 1
			_window_arrivals += 1
	# Ventanas de 20 s que empiezan en el segundo 10: 10-30, 30-50, …
	var window := floori((clock - (WINDOWS_FROM - WINDOW)) / WINDOW)
	if window > _window:
		_close_window(false, clock)
		_window = window
		_window_arrivals = 0


## La ventana a medias y el resumen, al cerrar el soak.
func report(clock: float) -> void:
	_close_window(true, clock)
	print("Probe hold summary: at=%s arrivals=%d candidates=%d empty_after_%d=%d reached=%d" % [
			place, _arrivals, _candidates.values().count(true),
			int(WINDOWS_FROM), _empty_windows, _reached.size()])


## El medio del tramo de fondo más largo del cañón de `layout`, o
## Vector3.INF si no hay cañón. Lo parten los puentes y los collados: se
## recorre el eje metro a metro y se queda con la racha más larga a fondo
## completo que no cae bajo un tablero.
static func ravine_point(layout: ReliefLayout, terrain: Terrain) -> Vector3:
	var ravine := layout.ravine
	if ravine == null:
		return Vector3.INF
	var best := Vector2.ZERO
	var run_from := -1.0
	var along := 0.0
	while along <= ravine.length + 1.0:
		var deep := along <= ravine.length \
				and layout.ravine_drop(along) >= ravine.depth - 0.01
		for crossing: ReliefLayout.Crossing in layout.crossings:
			if absf(along - crossing.s) <= crossing.width * 0.5:
				deep = false
		if deep and run_from < 0.0:
			run_from = along
		elif not deep and run_from >= 0.0:
			if along - run_from > best.y - best.x:
				best = Vector2(run_from, along)
			run_from = -1.0
		along += 1.0
	if best.y <= best.x:
		return Vector3.INF
	var flat := layout.ravine_frame((best.x + best.y) * 0.5)[0]
	return Vector3(flat.x, terrain.height_at(flat.x, flat.y), flat.y)


func _close_window(partial: bool, clock: float) -> void:
	if not holding:
		return
	var from := WINDOWS_FROM - WINDOW + float(_window) * WINDOW
	var to := minf(from + WINDOW, clock)
	if to - from < 1.0:
		return
	print("Probe hold: at=%s window=%d-%ds arrivals=%d%s" % [place, int(from), int(round(to)),
			_window_arrivals, " (partial)" if partial else ""])
	if not partial and from >= WINDOWS_FROM and _window_arrivals == 0:
		_empty_windows += 1
