class_name ReliefSearch
extends RefCounted
## Los recorridos sobre el grafo del relieve (ReliefGraph): qué celdas se
## alcanzan desde una, desde cuáles se llega a una, y el camino de un raider
## entre dos. Todo estático: el grafo va en cada llamada. Los usan los
## barridos de alcance (ReliefSweeps) y el ruteo del bot (ReliefNav).

const WAYS: int = ReliefGraph.WAYS
const NONE: int = ReliefGraph.NONE


## Una búsqueda de camino a medio hacer (begin / advance). Se reparte en
## frames: recorrer el mapa entero de una vez cuesta más de 100 ms, y eso es
## un tirón en las medidas de rendimiento del soak.
class Path:
	var to: int = ReliefGraph.NONE
	## Solo pasos a pie (subidas de hasta ReliefGraph.WALK_RISE), sin saltos.
	var walk_only: bool = false
	var parent := PackedInt32Array()
	var frontier := PackedInt32Array()
	var cursor: int = 0
	var done: bool = false
	## Con `done`: el camino con las dos puntas, o vacío si no hay ninguno.
	var path := PackedInt32Array()


## Todas las celdas a las que se llega desde `from` con los pasos de `next`
## (graph.raider_next u horde_next): 1 en las alcanzadas.
static func reach(graph: ReliefGraph, from: int, next: PackedInt32Array) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(graph.side * graph.side)
	if from == NONE:
		return seen
	seen[from] = 1
	var frontier := PackedInt32Array([from])
	var cursor := 0
	while cursor < frontier.size():
		var at := frontier[cursor]
		cursor += 1
		for step in WAYS:
			var to := next[at * WAYS + step]
			if to != NONE and seen[to] == 0:
				seen[to] = 1
				frontier.append(to)
	return seen


## Todas las celdas DESDE las que se llega a `to` con los pasos de `next`.
static func reach_back(graph: ReliefGraph, to: int, next: PackedInt32Array) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(graph.side * graph.side)
	if to == NONE:
		return seen
	# Lista de llegadas por celda: para cada paso a -> b, b recuerda a `a`.
	var first := PackedInt32Array()
	var link := PackedInt32Array()
	first.resize(graph.side * graph.side)
	first.fill(NONE)
	link.resize(next.size())
	for edge in next.size():
		var target := next[edge]
		if target == NONE:
			continue
		link[edge] = first[target]
		first[target] = edge
	seen[to] = 1
	var frontier := PackedInt32Array([to])
	var cursor := 0
	while cursor < frontier.size():
		var at := frontier[cursor]
		cursor += 1
		var edge := first[at]
		while edge != NONE:
			var from := edge / WAYS
			if seen[from] == 0:
				seen[from] = 1
				frontier.append(from)
			edge = link[edge]
	return seen


## Empieza la búsqueda a lo ancho de un camino de `from` a `to` con los
## pasos de un raider; con `walk_only`, sin saltos. No recorre nada todavía:
## eso lo hace advance.
static func begin(graph: ReliefGraph, from: int, to: int, walk_only: bool = false) -> Path:
	var search := Path.new()
	search.to = to
	search.walk_only = walk_only
	if from == NONE or to == NONE:
		search.done = true
		return search
	search.parent.resize(graph.side * graph.side)
	search.parent.fill(NONE)
	search.parent[from] = from
	search.frontier.append(from)
	return search


## Avanza `search` hasta `budget` celdas. True cuando terminó: su `path`
## tiene el camino, o queda vacío si no hay.
static func advance(graph: ReliefGraph, search: Path, budget: int) -> bool:
	if search.done:
		return true
	var steps := graph.raider_next
	var floor_y := graph.floor_y
	var walk := search.walk_only
	var parent := search.parent
	var frontier := search.frontier
	var cursor := search.cursor
	var to := search.to
	var stop := cursor + budget
	while cursor < stop and cursor < frontier.size() and parent[to] == NONE:
		var at := frontier[cursor]
		cursor += 1
		for step in WAYS:
			var next := steps[at * WAYS + step]
			if next == NONE or parent[next] != NONE:
				continue
			if walk and floor_y[next] - floor_y[at] > ReliefGraph.WALK_RISE:
				continue
			parent[next] = at
			frontier.append(next)
	search.parent = parent
	search.frontier = frontier
	search.cursor = cursor
	if parent[to] == NONE and cursor < frontier.size():
		return false
	search.done = true
	if parent[to] != NONE:
		# La celda de partida es su propio padre.
		var at := to
		while parent[at] != at:
			search.path.append(at)
			at = parent[at]
		search.path.append(at)
		search.path.reverse()
	search.parent = PackedInt32Array()
	search.frontier = PackedInt32Array()
	return true
