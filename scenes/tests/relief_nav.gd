class_name ReliefNav
extends RefCounted
## Ruteo del bot del arnés en una arena con relieve por zonas. El bot camina
## en línea recta a su destino; con cortes en el mapa eso lo deja contra un
## acantilado. Aquí se le da, en vez del destino, el próximo punto del
## camino que lleva hasta él por las rampas y los puentes (ReliefGraph.raider_path).
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
## Al llegar a esta distancia (celdas) del final, apunta al destino real.
const FINAL_APPROACH: int = 2
## Metros que tiene que saltar el destino para recalcular sin esperar.
const GOAL_JUMP: float = 6.0

var graph: ReliefGraph = null

var _paths: Dictionary[int, PackedInt32Array] = {}
var _goals: Dictionary[int, int] = {}
var _ages: Dictionary[int, float] = {}
var _jumps: Dictionary[int, bool] = {}


## Olvida los caminos (cambió la etapa).
func reset() -> void:
	graph = null
	_paths.clear()
	_goals.clear()
	_ages.clear()
	_jumps.clear()


## El punto hacia el que tiene que caminar el cuerpo del puesto `slot`, que
## está en `from`, para llegar a `goal`.
func steer(slot: int, from: Vector3, goal: Vector3, delta: float) -> Vector3:
	_jumps[slot] = false
	if graph == null:
		return goal
	var here := graph.nearest_open(Vector2(from.x, from.z), SNAP_REACH)
	var there := graph.nearest_open(Vector2(goal.x, goal.z), SNAP_REACH)
	if here == ReliefGraph.NONE or there == ReliefGraph.NONE or here == there:
		return goal
	var age := float(_ages.get(slot, INF)) + delta
	var path: PackedInt32Array = _paths.get(slot, PackedInt32Array())
	var at := _nearest_index(path, from)
	# Destino nuevo: se recalcula ya si saltó lejos (otro tramo del recorrido)
	# y cada REPLAN_SECONDS si solo se corre de a poco (seguir a un compañero).
	# Un camino que no existe o del que el bot se salió se reintenta con
	# pausa, nunca en cada frame: cada búsqueda recorre medio mapa.
	var old_goal := int(_goals.get(slot, ReliefGraph.NONE))
	var replan := old_goal == ReliefGraph.NONE or (old_goal != there
			and graph.center(old_goal).distance_to(graph.center(there)) > GOAL_JUMP)
	if not replan and age >= OFF_PATH_SECONDS and not path.is_empty() and at < 0:
		replan = true
	if not replan and age >= REPLAN_SECONDS:
		replan = path.is_empty() or old_goal != there
	if replan:
		path = graph.raider_path(here, there)
		_paths[slot] = path
		_goals[slot] = there
		age = 0.0
		at = 0
	_ages[slot] = age
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


## True si el paso que viene del puesto `slot` es una subida que pide salto.
func wants_jump(slot: int) -> bool:
	return bool(_jumps.get(slot, false))


## Índice de la celda de `path` más cercana a `from`, o -1 si el cuerpo se
## salió del camino.
func _nearest_index(path: PackedInt32Array, from: Vector3) -> int:
	var best := -1
	var best_distance := OFF_PATH
	var flat := Vector2(from.x, from.z)
	for index in path.size():
		var distance := graph.center(path[index]).distance_to(flat)
		if distance <= best_distance:
			best_distance = distance
			best = index
	return best
