class_name ReliefProbe
extends RefCounted
## Lo que ArenaProbe hace de más en una arena con RELIEVE POR ZONAS (hoy, el
## Bosque Hueco). Vive en su propio archivo para no engordar arena_probe.gd,
## que solo lo crea, lo avanza y le pregunta por dónde caminar. En una arena
## sin relieve por zonas no hace ni imprime nada.
##
## 1. BARRE, al empezar cada etapa y otra vez a los 120 s (ReliefSweeps):
##    las líneas `Relief graph:` y `Relief sweep:` que lee tools/verificar.sh.
##    Si a los 120 s el mundo está congelado por una cinemática, espera.
## 2. RUTEA: route() le da al bot el próximo punto del camino a su destino
##    por rampas y puentes (ReliefNav), en vez de la línea recta.
## 3. PASEA: antes del recorrido de siempre, lleva al raider a la zona más
##    alta y de una cabecera del puente a la otra, y lo dice:
##      Probe relief: stood on raised zone …
##      Probe relief: crossed bridge …
## 4. RETIENE, solo con BONK_HOLD_AT=high|ravine|bridge: deja al raider
##    quieto a 8 m del corte más alto de la zona más alta, en el medio del
##    fondo del cañón o en el medio del puente más largo, y cuenta las
##    LLEGADAS: enemigos que aparecieron 3 m o más arriba o abajo de su nivel
##    y se le acercaron a 3 m (y a no más de 1.5 m de altura). Imprime una
##    línea `Probe hold:` por ventana de 20 s y un resumen al salir; el
##    resumen dice además cuántos enemigos lo alcanzaron en total
##    (`reached`), hayan aparecido en su nivel o en otro.

const HOLD_ENV := "BONK_HOLD_AT"
const HOLD_PLACES: Array[String] = ["high", "ravine", "bridge"]
## Solo depuración: BONK_RELIEF_DUMP=x,z[,radio] imprime el grafo alrededor
## de ese punto (ReliefSweeps.dump).
const DUMP_ENV := "BONK_RELIEF_DUMP"
## Frames tras el cambio de etapa antes de barrer: los transforms de los
## props ya llegaron a la física (igual que el barrido de máscara).
const START_FRAMES: int = 10
## Segundo del reloj de la etapa en que la colocación se barre otra vez.
const PLACEMENT_AGAIN_AT: float = 120.0
## La sonda de llegada (ver la cabecera), en metros y segundos.
const HOLD_INSET: float = 8.0
const HOLD_SPAWN_GAP: float = 3.0
const HOLD_ARRIVE_RANGE: float = 3.0
const HOLD_ARRIVE_LEVEL: float = 1.5
const HOLD_WINDOW: float = 20.0
const HOLD_WINDOWS_FROM: float = 30.0
## Radio y ventana de altura con que se busca la celda abierta del punto
## alto, en metros.
const HIGH_SNAP: float = 7.0
const HIGH_LEVEL: float = 2.0
## Metros que el raider retenido puede correrse antes de volver a su punto.
const HOLD_DRIFT: float = 1.0
## El paseo: a cuántos metros cuenta que llegó a un punto y cuántos segundos
## le da a cada tramo antes de pasar al siguiente.
const TOUR_REACHED: float = 2.5
const TOUR_LEG_TIMEOUT: float = 70.0
## Ventana de altura que cuenta como "sobre el puente": metros bajo el
## tablero (más abajo es haberse caído) y metros sobre él (un salto).
const DECK_LEVEL: float = 1.2
const DECK_JUMP: float = 2.6

var nav := ReliefNav.new()
var sweeps := ReliefSweeps.new()

var _tree: SceneTree = null
var _hold_at: String = ""
var _start_frame: int = -1
var _active: bool = false
var _clock: float = 0.0
var _placement_again: bool = false
## Frames seguidos con la arena dentro de la física (ver tick).
var _thawed_frames: int = 0
var _terrain: Terrain = null
var _layout: ReliefLayout = null
var _tour: Array[Vector3] = []
var _tour_index: int = 0
var _tour_leg_time: float = 0.0
var _stood: bool = false
var _crossed: bool = false
## Por qué cabecera entró el raider a cada puente (una entrada por cruce):
## +1, -1 o 0 si no está encima.
var _deck_sides := PackedInt32Array()
var _hold_point: Vector3 = Vector3.INF
var _holding: bool = false
## Enemigos ya vistos: true si aparecieron a otro nivel (candidatos a llegada).
var _candidates: Dictionary[int, bool] = {}
var _arrived: Dictionary[int, bool] = {}
## Enemigos que se le acercaron al retenido, hayan aparecido donde sea.
var _reached: Dictionary[int, bool] = {}
var _window: int = 0
var _window_arrivals: int = 0
var _arrivals: int = 0
var _empty_windows: int = 0


func _init(tree: SceneTree) -> void:
	_tree = tree
	_hold_at = OS.get_environment(HOLD_ENV).strip_edges()
	if not _hold_at.is_empty() and not HOLD_PLACES.has(_hold_at):
		push_error("ArenaProbe: %s must be one of %s, got '%s'" % [HOLD_ENV, HOLD_PLACES, _hold_at])
		_hold_at = ""


## Una etapa nueva: lo de la anterior ya no vale y el barrido se agenda.
func on_stage_changed(frames: int) -> void:
	_start_frame = frames + START_FRAMES
	_active = false
	_clock = 0.0
	_placement_again = false
	_thawed_frames = 0
	_tour.clear()
	_tour_index = 0
	_holding = false
	_hold_point = Vector3.INF
	_deck_sides.clear()
	nav.reset()


## Una vez por frame de física del arnés. True si este frame corrió un
## barrido: su costo es del arnés y el PerfMeter no lo cuenta.
func tick(delta: float, frames: int, lead: CharacterBody3D, raiders: Array[RID]) -> bool:
	var swept := false
	if _start_frame >= 0 and frames >= _start_frame:
		_start_frame = -1
		_begin(lead, raiders)
		swept = _active
	if not _active:
		return swept
	_clock += delta
	if not _placement_again and _clock >= PLACEMENT_AGAIN_AT:
		# Con el mundo congelado (la cinemática de un jefe: WorldFreeze saca la
		# arena de la física) los rayos no tocan nada. Se barre cuando vuelve.
		_thawed_frames = 0 if _world_frozen() else _thawed_frames + 1
		if _thawed_frames >= START_FRAMES:
			_placement_again = true
			sweeps.placement("120")
			swept = true
	if lead == null:
		return swept
	_watch_feats(lead)
	if _holding:
		_watch_hold(lead)
	elif _tour_index < _tour.size():
		_advance_tour(delta, lead)
	return swept


## Hacia dónde tiene que caminar el cuerpo del puesto `slot` para llegar a
## `goal`: el propio `goal` si la arena no tiene relieve por zonas.
func route(slot: int, from: Vector3, goal: Vector3, delta: float) -> Vector3:
	return nav.steer(slot, from, goal, delta) if _active else goal


## True si el próximo paso del puesto `slot` es una subida que pide salto.
func wants_jump(slot: int) -> bool:
	return _active and nav.wants_jump(slot)


## El punto adonde el arnés tiene que llevar al líder antes que a cualquier
## otra cosa (el paseo), o Vector3.INF si no hay ninguno.
func forced_goal() -> Vector3:
	if not _active or _holding or _tour_index >= _tour.size():
		return Vector3.INF
	return _tour[_tour_index]


## True mientras BONK_HOLD_AT retiene al líder en su punto.
func hold_active() -> bool:
	return _active and _holding


## Dónde está retenido el líder (válido con hold_active()).
func hold_point() -> Vector3:
	return _hold_point


## True si el líder retenido se corrió y tiene que volver a su punto.
func hold_drifted(lead: Node3D) -> bool:
	return Vector2(lead.global_position.x - _hold_point.x,
			lead.global_position.z - _hold_point.z).length() > HOLD_DRIFT


## Las líneas de cierre del soak.
func report() -> void:
	if _layout == null:
		return
	print("Probe relief: tour stood=%s crossed=%s legs=%d/%d" % [
			_stood, _crossed, _tour_index, _tour.size()])
	if _hold_at.is_empty():
		return
	_close_window(true)
	print("Probe hold summary: at=%s arrivals=%d candidates=%d empty_after_%d=%d reached=%d" % [
			_hold_at, _arrivals, _candidates.values().count(true),
			int(HOLD_WINDOWS_FROM), _empty_windows, _reached.size()])


# --- arranque ----------------------------------------------------------------------

func _begin(lead: CharacterBody3D, raiders: Array[RID]) -> void:
	var arena := RunRoot.stage_parent(_tree) as Node3D
	if arena == null or not sweeps.run(_tree, arena, raiders):
		return
	_active = true
	nav.graph = sweeps.graph
	var dump := OS.get_environment(DUMP_ENV).split_floats(",", false)
	if dump.size() >= 2:
		sweeps.dump(Vector2(dump[0], dump[1]), int(dump[2]) if dump.size() > 2 else 10)
	_terrain = Terrain.find(_tree)
	_layout = _terrain.relief_layout()
	_stood = false
	_crossed = false
	if _hold_at.is_empty():
		_plan_tour()
	elif lead != null:
		_start_hold(lead)


## True mientras la arena de la etapa está desactivada (WorldFreeze).
func _world_frozen() -> bool:
	var arena := RunRoot.stage_parent(_tree)
	return arena != null and arena.process_mode == Node.PROCESS_MODE_DISABLED


## El punto a HOLD_INSET metros hacia dentro del corte más alto de la zona
## más alta; el centro de esa zona si ese punto no se alcanza.
func _high_point() -> Vector3:
	var top := 0
	for index in _layout.zones.size():
		if _layout.zones[index].top:
			top = index
	var best: ReliefLayout.CutPath = null
	for cut: ReliefLayout.CutPath in _layout.cuts:
		if cut.zone == top and (best == null or cut.height > best.height + 0.01):
			best = cut
	var flat := _layout.zones[top].center
	if best != null:
		# El medio del tramo que mide la altura completa: lejos de las rampas.
		var full: Array[int] = []
		for index in best.points.size():
			if best.upper[index] - best.lower[index] > best.height - 0.05:
				full.append(index)
		var middle := full[full.size() / 2]
		flat = best.points[middle] - best.normals[middle] * HOLD_INSET
	# La celda abierta más cercana que el raider alcanza: el punto pedido
	# puede caer dentro del hito de la cumbre.
	var cell := sweeps.graph.nearest_open(flat, HIGH_SNAP,
			_layout.zones[top].floor + _layout.zones[top].height
			+ _terrain.base_height_at(flat.x, flat.y), HIGH_LEVEL)
	if sweeps.raider_reaches(cell):
		return sweeps.graph.stand(cell)
	return Vector3(flat.x, _terrain.height_at(flat.x, flat.y), flat.y)


## El cruce más largo, o null.
func _longest_crossing() -> ReliefLayout.Crossing:
	var longest: ReliefLayout.Crossing = null
	for crossing: ReliefLayout.Crossing in _layout.crossings:
		if longest == null or crossing.span > longest.span:
			longest = crossing
	return longest


func _plan_tour() -> void:
	_tour.clear()
	_tour_index = 0
	_tour_leg_time = 0.0
	if _layout.zones.is_empty():
		return
	_tour.append(_high_point())
	var crossing := _longest_crossing()
	if crossing != null:
		for head: Vector2 in [crossing.head_a, crossing.head_b]:
			_tour.append(Vector3(head.x, crossing.level, head.y))


func _advance_tour(delta: float, lead: CharacterBody3D) -> void:
	var goal := _tour[_tour_index]
	var at := lead.global_position
	_tour_leg_time += delta
	var reached := Vector2(at.x - goal.x, at.z - goal.z).length() <= TOUR_REACHED \
			and absf(at.y - goal.y) <= HOLD_ARRIVE_LEVEL
	if not reached and _tour_leg_time < TOUR_LEG_TIMEOUT:
		return
	if not reached:
		print("Probe relief: tour leg %d timed out %.1fm short" % [_tour_index + 1,
				Vector2(at.x - goal.x, at.z - goal.z).length()])
	_tour_index += 1
	_tour_leg_time = 0.0


# --- hazañas ----------------------------------------------------------------------

## Anota la primera vez que el líder pisa una zona elevada y la primera vez
## que cruza un puente de una cabecera a la otra sin bajarse.
func _watch_feats(lead: CharacterBody3D) -> void:
	var at := lead.global_position
	var flat := Vector2(at.x, at.z)
	if not _stood and lead.is_on_floor():
		for index in _layout.zones.size():
			var zone := _layout.zones[index]
			if is_equal_approx(_layout.raised_offset(zone, flat), zone.height) \
					and absf(at.y - _terrain.height_at(at.x, at.z)) < 0.6:
				_stood = true
				print("Probe relief: stood on raised zone %d at (%.1f, %.1f, %.1f) t=%.1fs" % [
						index + 1, at.x, at.y, at.z, _clock])
	if _crossed:
		return
	_deck_sides.resize(_layout.crossings.size())
	for index in _layout.crossings.size():
		var crossing := _layout.crossings[index]
		var local := flat - crossing.center
		var along := local.dot(crossing.axis)
		var across := absf(local.dot(Vector2(-crossing.axis.y, crossing.axis.x)))
		var half_span := crossing.span * 0.5
		# Un salto sobre el tablero sigue siendo estar en el puente; caer
		# bajo él, no.
		var above := at.y - crossing.level
		if across > crossing.width * 0.5 + 0.5 or absf(along) > half_span + 2.0 \
				or above < -DECK_LEVEL or above > DECK_JUMP:
			_deck_sides[index] = 0
			continue
		if absf(along) < half_span - 1.5:
			continue
		var side := 1 if along > 0.0 else -1
		if _deck_sides[index] == -side:
			_crossed = true
			print("Probe relief: crossed bridge span=%.1f t=%.1fs" % [crossing.span, _clock])
			return
		_deck_sides[index] = side


# --- sonda de llegada --------------------------------------------------------------

func _start_hold(lead: CharacterBody3D) -> void:
	match _hold_at:
		"high":
			_hold_point = _high_point()
		"ravine":
			_hold_point = _ravine_point()
		"bridge":
			var crossing := _longest_crossing()
			if crossing != null:
				_hold_point = Vector3(crossing.center.x, crossing.level, crossing.center.y)
	if _hold_point == Vector3.INF:
		push_error("ArenaProbe: %s=%s but this stage has no such place" % [HOLD_ENV, _hold_at])
		return
	_holding = true
	_candidates.clear()
	_arrived.clear()
	_reached.clear()
	_window = 0
	_window_arrivals = 0
	lead.global_position = _hold_point + Vector3.UP * 0.2
	lead.velocity = Vector3.ZERO
	print("Probe hold: at=%s point=(%.1f, %.1f, %.1f)" % [
			_hold_at, _hold_point.x, _hold_point.y, _hold_point.z])


## El medio del tramo de fondo más largo del cañón. Lo parten los puentes y
## los collados: se recorre el eje metro a metro y se queda con la racha más
## larga a fondo completo que no cae bajo un tablero.
func _ravine_point() -> Vector3:
	var ravine := _layout.ravine
	if ravine == null:
		return Vector3.INF
	var best := Vector2.ZERO
	var run_from := -1.0
	var along := 0.0
	while along <= ravine.length + 1.0:
		var deep := along <= ravine.length \
				and _layout.ravine_drop(along) >= ravine.depth - 0.01
		for crossing: ReliefLayout.Crossing in _layout.crossings:
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
	var flat := _layout.ravine_frame((best.x + best.y) * 0.5)[0]
	return Vector3(flat.x, _terrain.height_at(flat.x, flat.y), flat.y)


func _watch_hold(lead: CharacterBody3D) -> void:
	var at := lead.global_position
	for node: Node in _tree.get_nodes_in_group(&"enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var id := body.get_instance_id()
		var where := body.global_position
		if not _candidates.has(id):
			_candidates[id] = absf(where.y - _hold_point.y) >= HOLD_SPAWN_GAP
		var close := Vector2(where.x - at.x, where.z - at.z).length() <= HOLD_ARRIVE_RANGE \
				and absf(where.y - at.y) <= HOLD_ARRIVE_LEVEL
		if close:
			_reached[id] = true
		if not _candidates[id] or _arrived.has(id):
			continue
		if close:
			_arrived[id] = true
			_arrivals += 1
			_window_arrivals += 1
	# Ventanas de 20 s que empiezan en el segundo 10: 10-30, 30-50, …
	var window := floori((_clock - (HOLD_WINDOWS_FROM - HOLD_WINDOW)) / HOLD_WINDOW)
	if window > _window:
		_close_window(false)
		_window = window
		_window_arrivals = 0


func _close_window(partial: bool) -> void:
	if not _holding:
		return
	var from := HOLD_WINDOWS_FROM - HOLD_WINDOW + float(_window) * HOLD_WINDOW
	var to := minf(from + HOLD_WINDOW, _clock)
	if to - from < 1.0:
		return
	print("Probe hold: at=%s window=%d-%ds arrivals=%d%s" % [_hold_at, int(from), int(round(to)),
			_window_arrivals, " (partial)" if partial else ""])
	if not partial and from >= HOLD_WINDOWS_FROM and _window_arrivals == 0:
		_empty_windows += 1
