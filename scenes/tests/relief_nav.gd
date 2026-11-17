class_name ReliefNav
extends RefCounted
## Ruteo del bot del arnés en una arena con relieve por zonas. El bot camina
## en línea recta a su destino; con cortes en el mapa eso lo deja contra un
## acantilado. Aquí se le da, en vez del destino, el próximo punto del
## camino que lleva hasta él por las rampas y los puentes (ReliefSearch.begin).
## La búsqueda se reparte en frames; mientras llega, el bot sigue en línea recta.
##
## Sin grafo (una arena sin relieve por zonas) steer() devuelve el destino
## tal cual: el recorrido de siempre.

## Celdas por delante del bot a las que apunta: suaviza el camino en
## escalera de una cuadrícula y no corta tanto como para tirarlo de una cornisa.
const LOOKAHEAD: int = 3
## Segundos entre dos recálculos del camino hacia un destino que se mueve.
const REPLAN_SECONDS: float = 1.5
## Metros fuera de su camino a los que el bot lo recalcula (más que
## SNAP_REACH, o un camino recién calculado ya nacería "fuera"), y segundos
## mínimos entre dos de esos recálculos.
const OFF_PATH: float = 4.5
const OFF_PATH_SECONDS: float = 0.5
## Subida en metros que pide un salto, y a cuántos metros de ella se salta.
const JUMP_RISE: float = 0.55
const JUMP_RANGE: float = 1.8
## Radio en metros donde se busca la celda abierta del bot y la del destino.
const SNAP_REACH: float = 4.0
## Radio en metros donde se busca la celda de un DESTINO que no tiene ninguna
## a su altura cerca: está bajo un tablero (el grafo guarda un piso por
## celda, y ahí ese piso es el tablero de arriba). Se llega a la celda de su
## nivel más cercana y de ahí, derecho.
const UNDER_REACH: float = 16.0
## Cuánto más alto o más bajo que un cuerpo puede estar el piso de "su"
## celda, en metros: por encima, un escalón; por debajo, lo que sube un salto.
## Sin esto, al pie de un corte la celda más cercana es una de arriba.
const LEVEL_ABOVE: float = 0.8
const LEVEL_BELOW: float = 2.4
## Al llegar a esta distancia (celdas) del final, apunta al destino real.
const FINAL_APPROACH: int = 2
## Metros que tiene que saltar el destino para recalcular sin esperar.
const GOAL_JUMP: float = 6.0
## Celdas que la búsqueda de un camino recorre por frame y por puesto: el
## mapa entero (57 600 celdas) se reparte en unos 40 frames.
const SEARCH_BUDGET: int = 1500

var graph: ReliefGraph = null

var _paths: Dictionary[int, PackedInt32Array] = {}
## Búsqueda en curso de cada puesto (ReliefSearch.Path); sin entrada si no hay.
var _searches: Dictionary[int, RefCounted] = {}
var _goals: Dictionary[int, int] = {}
var _ages: Dictionary[int, float] = {}
var _jumps: Dictionary[int, bool] = {}


## Olvida los caminos (cambió la etapa).
func reset() -> void:
	graph = null
	_paths.clear()
	_searches.clear()
	_goals.clear()
	_ages.clear()
	_jumps.clear()


## El punto hacia el que tiene que caminar el cuerpo del puesto `slot`, que
## está en `from`, para llegar a `goal`.
func steer(slot: int, from: Vector3, goal: Vector3, delta: float) -> Vector3:
	_jumps[slot] = false
	if graph == null:
		return goal
	var here := _cell_at(from)
	var there := _goal_cell(goal)
	if here == ReliefGraph.NONE or there == ReliefGraph.NONE or here == there:
		return goal
	var path := _plan(slot, here, there, from, delta)
	var at := _nearest_index(path, from)
	if path.is_empty() or at < 0:
		return goal
	if at >= path.size() - 1 - FINAL_APPROACH:
		return goal
	# Apunta unas celdas adelante, pero nunca más allá de un desnivel: una
	# subida se salta de frente y una caída se toma por donde dice el camino.
	var target := at + 1
	while target < mini(at + LOOKAHEAD, path.size() - 1):
		if absf(graph.floor_y[path[target + 1]] - graph.floor_y[path[target]]) > JUMP_RISE:
			break
		target += 1
	var rise := graph.floor_y[path[at + 1]] - graph.floor_y[path[at]]
	var next := graph.stand(path[at + 1])
	if rise > JUMP_RISE and Vector2(next.x - from.x, next.z - from.z).length() < JUMP_RANGE:
		_jumps[slot] = true
	return graph.stand(path[target])


## El camino vigente del puesto `slot`, de `here` a `there`: decide cuándo
## recalcularlo y avanza la búsqueda en curso.
func _plan(slot: int, here: int, there: int, from: Vector3, delta: float) -> PackedInt32Array:
	var age := float(_ages.get(slot, INF)) + delta
	var path: PackedInt32Array = _paths.get(slot, PackedInt32Array())
	var search := _searches.get(slot, null) as ReliefSearch.Path
	# Destino nuevo: se recalcula ya si saltó lejos (otro tramo del recorrido)
	# y cada REPLAN_SECONDS si solo se corre de a poco (seguir a un compañero).
	# Un camino que no existe o del que el bot se salió se reintenta con
	# pausa, nunca en cada frame, y nunca con otra búsqueda a medio hacer.
	var old_goal := int(_goals.get(slot, ReliefGraph.NONE))
	var jumped := old_goal == ReliefGraph.NONE or (old_goal != there
			and graph.center(old_goal).distance_to(graph.center(there)) > GOAL_JUMP)
	var lost := search == null and age >= OFF_PATH_SECONDS and not path.is_empty() \
			and _nearest_index(path, from) < 0
	var stale := search == null and age >= REPLAN_SECONDS \
			and (path.is_empty() or old_goal != there)
	if jumped or lost or stale:
		search = ReliefSearch.begin(graph, here, there)
		_searches[slot] = search
		_goals[slot] = there
		age = 0.0
		if jumped or lost:
			# El camino viejo ya no lleva a nada: en línea recta hasta el nuevo.
			path = PackedInt32Array()
			_paths[slot] = path
	_ages[slot] = age
	if search != null and ReliefSearch.advance(graph, search, SEARCH_BUDGET):
		path = search.path
		_paths[slot] = path
		_searches.erase(slot)
	return path


## True si el paso que viene del puesto `slot` es una subida que pide salto.
func wants_jump(slot: int) -> bool:
	return bool(_jumps.get(slot, false))


## La celda abierta de lo que está en `at` (un cuerpo o un destino): la más
## cercana con el piso a su altura, y si a su altura no hay ninguna (va por
## el aire), la más cercana a secas.
func _cell_at(at: Vector3) -> int:
	var flat := Vector2(at.x, at.z)
	var cell := graph.nearest_open(flat, SNAP_REACH, at.y + (LEVEL_ABOVE - LEVEL_BELOW) * 0.5,
			(LEVEL_ABOVE + LEVEL_BELOW) * 0.5)
	return cell if cell != ReliefGraph.NONE else graph.nearest_open(flat, SNAP_REACH)


## La celda abierta de un destino: como _cell_at, pero antes de conformarse
## con una de otro nivel busca más lejos una del suyo. Un compañero caído
## bajo el puente tiene encima las celdas del tablero: sin esto el bot se
## pararía arriba de él sin poder alcanzarlo.
func _goal_cell(goal: Vector3) -> int:
	var flat := Vector2(goal.x, goal.z)
	var level := goal.y + (LEVEL_ABOVE - LEVEL_BELOW) * 0.5
	var window := (LEVEL_ABOVE + LEVEL_BELOW) * 0.5
	var cell := graph.nearest_open(flat, SNAP_REACH, level, window)
	if cell == ReliefGraph.NONE:
		cell = graph.nearest_open(flat, UNDER_REACH, level, window)
	return cell if cell != ReliefGraph.NONE else graph.nearest_open(flat, SNAP_REACH)


## Índice de la celda de `path` más cercana a `from` y a su altura, o -1 si
## el cuerpo se salió del camino (también si se cayó de él a otro nivel).
func _nearest_index(path: PackedInt32Array, from: Vector3) -> int:
	var best := -1
	var best_distance := OFF_PATH
	var flat := Vector2(from.x, from.z)
	for index in path.size():
		var rise := graph.floor_y[path[index]] - from.y
		if rise > LEVEL_ABOVE or rise < -LEVEL_BELOW:
			continue
		var distance := graph.center(path[index]).distance_to(flat)
		if distance <= best_distance:
			best_distance = distance
			best = index
	return best
