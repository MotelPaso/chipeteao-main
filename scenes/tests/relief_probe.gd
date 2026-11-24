class_name ReliefProbe
extends RefCounted
## Lo que ArenaProbe hace de más en una arena con RELIEVE POR ZONAS (hoy, el
## Bosque Hueco). Vive en su propio archivo para no engordar arena_probe.gd,
## que solo lo crea, lo avanza y le pregunta por dónde caminar. En una arena
## sin relieve por zonas no hace ni imprime nada.
##
## 1. BARRE, al empezar cada etapa y otra vez a los 120 s (ReliefSweeps):
##    las líneas `Relief graph:` y `Relief sweep:` que lee tools/verificar.sh.
##    Si a los 120 s el mundo está congelado por una cinemática, espera. El
##    barrido del infierno espera, además, a que el bosque de afuera termine.
## 2. RUTEA: route() le da al bot el próximo punto del camino a su destino
##    por rampas y puentes (ReliefNav), en vez de la línea recta.
## 3. PASEA: antes del recorrido de siempre, lleva al raider a la zona más
##    alta y de una cabecera del puente a la otra, y lo dice:
##      Probe relief: stood on raised zone …
##      Probe relief: crossed bridge …
## 4. RETIENE, solo con BONK_HOLD_AT=high|ravine|bridge: deja al raider
##    quieto a 8 m del corte más alto de la zona más alta, en el medio del
##    fondo del cañón o en el medio del puente más largo, y cuenta las
##    llegadas (ReliefHold, relief_hold.gd).

## Solo depuración: BONK_RELIEF_DUMP=x,z[,radio] imprime el grafo alrededor
## de ese punto (ReliefSweeps.dump).
const DUMP_ENV := "BONK_RELIEF_DUMP"
## Frames tras el cambio de etapa antes de barrer: los transforms de los
## props ya llegaron a la física (igual que el barrido de máscara).
const START_FRAMES: int = 10
## Segundo del reloj de la etapa en que la colocación se barre otra vez.
const PLACEMENT_AGAIN_AT: float = 120.0
## Metros hacia dentro del corte más alto donde queda el punto alto (el del
## paseo y el de BONK_HOLD_AT=high).
const HOLD_INSET: float = 8.0
## Radio y ventana de altura con que se busca la celda abierta del punto
## alto, en metros.
const HIGH_SNAP: float = 7.0
const HIGH_LEVEL: float = 2.0
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
var hold := ReliefHold.new()

var _tree: SceneTree = null
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


func _init(tree: SceneTree) -> void:
	_tree = tree


## Una etapa nueva: lo de la anterior ya no vale y el barrido se agenda.
func on_stage_changed(frames: int) -> void:
	_start_frame = frames + START_FRAMES
	_active = false
	_clock = 0.0
	_placement_again = false
	_thawed_frames = 0
	_tour.clear()
	_tour_index = 0
	hold.reset()
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
	# El barrido del infierno espera al bosque de afuera (ReliefSweeps.try_hell).
	if sweeps.hell_pending():
		sweeps.try_hell()
		swept = swept or not sweeps.hell_pending()
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
	if hold.holding:
		hold.watch(_tree, lead, _clock)
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
	if not _active or hold.holding or _tour_index >= _tour.size():
		return Vector3.INF
	return _tour[_tour_index]


## True mientras BONK_HOLD_AT retiene al líder en su punto.
func hold_active() -> bool:
	return _active and hold.holding


## Dónde está retenido el líder (válido con hold_active()).
func hold_point() -> Vector3:
	return hold.point


## True si el líder retenido se corrió y tiene que volver a su punto.
func hold_drifted(lead: Node3D) -> bool:
	return hold.drifted(lead)


## Las líneas de cierre del soak.
func report() -> void:
	if _layout == null:
		return
	print("Probe relief: tour stood=%s crossed=%s legs=%d/%d" % [
			_stood, _crossed, _tour_index, _tour.size()])
	if not hold.place.is_empty():
		hold.report(_clock)


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
	if hold.place.is_empty():
		_plan_tour()
	elif lead != null:
		_start_hold(lead)


## True mientras la arena de la etapa está desactivada (WorldFreeze).
func _world_frozen() -> bool:
	var arena := RunRoot.stage_parent(_tree)
	return arena != null and arena.process_mode == Node.PROCESS_MODE_DISABLED


## El punto a HOLD_INSET metros hacia dentro del corte más alto de la zona
## más alta (la que la receta marca `top`, o la de cima más alta); el centro
## de esa zona si ese punto no se alcanza.
func _high_point() -> Vector3:
	var top := 0
	var highest := -INF
	for index in _layout.zones.size():
		var zone := _layout.zones[index]
		if zone.top:
			top = index
			break
		if zone.floor + zone.height > highest:
			highest = zone.floor + zone.height
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
			and absf(at.y - goal.y) <= ReliefHold.ARRIVE_LEVEL
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

## El punto del lugar que pidió BONK_HOLD_AT, y la sonda que retiene ahí al líder.
func _start_hold(lead: CharacterBody3D) -> void:
	var at := Vector3.INF
	match hold.place:
		"high":
			at = _high_point()
		"ravine":
			at = ReliefHold.ravine_point(_layout, _terrain)
		"bridge":
			var crossing := _longest_crossing()
			if crossing != null:
				at = Vector3(crossing.center.x, crossing.level, crossing.center.y)
	hold.start(at, _layout.recipe, lead)
