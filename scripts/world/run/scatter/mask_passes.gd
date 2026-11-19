class_name MaskPasses
extends RefCounted
## Los repasos que ArenaMask.build() le hace a la roca recién crecida:
## rellenar muescas y rendijas, abrir lo que quedó apretado y sellar lo que
## no se alcanza a pie desde el spawn. Trabajan sobre las celdas bloqueadas
## de la máscara (`blocked`: celda -> true) en una cuadrícula de `side`
## celdas por lado. No sacan números de ningún RNG, así que no cambian el
## orden de sorteo del scatter.


## Las celdas abiertas rodeadas de roca por tres o cuatro lados se vuelven
## roca: una muesca cerrada por tres lados no sirve para pelear, y su
## contorno cuadrado es lo único que el margen de la formación no esconde.
## `may_grow` dice si una celda puede llevar roca (ArenaMask._rock_may_grow).
static func fill_notches(blocked: Dictionary[Vector2i, bool], side: int,
		may_grow: Callable) -> void:
	for sweep in 3:
		var notches: Array[Vector2i] = []
		for x in side:
			for y in side:
				var cell := Vector2i(x, y)
				if blocked.has(cell) or not bool(may_grow.call(cell)):
					continue
				var walls := 0
				for step: Vector2i in ArenaMask.STEPS:
					if blocked.has(cell + step):
						walls += 1
				if walls >= 3:
					notches.append(cell)
		if notches.is_empty():
			return
		for cell: Vector2i in notches:
			blocked[cell] = true


## Las celdas abiertas con roca a los dos lados opuestos se vuelven roca:
## un pasillo de UNA celda entre dos brazos de roca. El faldón que cada
## formación asoma de sus celdas lo deja en una rendija por donde nadie
## pasa, y lo que quede abierto al fondo es un rincón sin entrada (adonde
## sí se llega volando). Solo con relieve por zonas: en las demás arenas la
## máscara queda como siempre.
static func fill_slots(blocked: Dictionary[Vector2i, bool], side: int,
		may_grow: Callable) -> void:
	for sweep in 4:
		var slots: Array[Vector2i] = []
		for x in side:
			for y in side:
				var cell := Vector2i(x, y)
				if blocked.has(cell) or not bool(may_grow.call(cell)):
					continue
				if (blocked.has(cell + Vector2i.LEFT) and blocked.has(cell + Vector2i.RIGHT)) \
						or (blocked.has(cell + Vector2i.UP) and blocked.has(cell + Vector2i.DOWN)):
					slots.append(cell)
		if slots.is_empty():
			return
		for cell: Vector2i in slots:
			blocked[cell] = true


## Una celda PROTEGIDA con roca a los dos lados opuestos no se puede
## rellenar (ver fill_slots), así que se abre la roca: las dos celdas que
## la aprietan pasan a ser suelo. Va al final, después de todo lo que
## bloquea: abrir una celda nunca aprieta a otra ni deja nada sin alcanzar.
static func free_squeezed(blocked: Dictionary[Vector2i, bool], side: int,
		protected: Dictionary[Vector2i, bool]) -> void:
	var opened: Array[Vector2i] = []
	for cell: Vector2i in protected:
		if not _in_grid(cell, side) or blocked.has(cell):
			continue
		for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if blocked.has(cell + axis) and blocked.has(cell - axis):
				opened.append(cell + axis)
				opened.append(cell - axis)
	for cell: Vector2i in opened:
		blocked.erase(cell)


## Flood fill desde `start` (la celda del spawn); las celdas abiertas que no
## alcanza se sellan, así toda celda abierta que queda se alcanza a pie. Las
## celdas PROTEGIDAS nunca se sellan: si una quedó aislada, se abre un
## pasillo hasta suelo alcanzado y se repite el relleno. Así se cumplen las
## dos cosas: todo lo abierto es alcanzable y ningún spot de autor queda bajo
## una formación. El relleno no cruza `barriers`, las aristas que un corte
## del relieve vuelve infranqueables (ver ArenaMask.build).
static func seal_unreachable(blocked: Dictionary[Vector2i, bool], side: int, start: Vector2i,
		protected: Dictionary[Vector2i, bool], barriers: Dictionary[Vector3i, bool]) -> void:
	var reached := reachable_cells(blocked, side, start, barriers)
	var carved := false
	for cell: Vector2i in protected:
		if not _in_grid(cell, side) or reached.has(cell):
			continue
		if _carve_corridor(blocked, cell, reached):
			carved = true
	if carved:
		reached = reachable_cells(blocked, side, start, barriers)
	for x in side:
		for y in side:
			var cell := Vector2i(x, y)
			if not reached.has(cell):
				blocked[cell] = true


## Flood fill vecindad-4 desde `start` sobre las celdas abiertas, sin cruzar
## `barriers`.
static func reachable_cells(blocked: Dictionary[Vector2i, bool], side: int, start: Vector2i,
		barriers: Dictionary[Vector3i, bool]) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step: Vector2i in ArenaMask.STEPS:
			var next := cell + step
			if not _in_grid(next, side) or reached.has(next) or blocked.has(next) \
					or _barred(barriers, cell, next):
				continue
			reached[next] = true
			frontier.append(next)
	return reached


static func _in_grid(cell: Vector2i, side: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < side and cell.y < side


## True si un corte del relieve separa dos celdas vecinas. La llave de una
## arista es su celda de menor coordenada más el eje (0 = +x, 1 = +y).
static func _barred(barriers: Dictionary[Vector3i, bool], from: Vector2i, to: Vector2i) -> bool:
	if barriers.is_empty():
		return false
	return barriers.has(Vector3i(mini(from.x, to.x), mini(from.y, to.y),
			0 if from.y == to.y else 1))


## Desbloquea una escalera de celdas desde `from` hasta la celda alcanzada
## más cercana. Conexa-4 a propósito (un eje por paso), para que el pasillo
## se camine con la misma vecindad del flood fill. True si abrió algo.
static func _carve_corridor(blocked: Dictionary[Vector2i, bool], from: Vector2i,
		reached: Dictionary[Vector2i, bool]) -> bool:
	var target := from
	var best := INF
	for cell: Vector2i in reached:
		var distance := Vector2(cell - from).length_squared()
		if distance < best:
			best = distance
			target = cell
	if target == from:
		return false
	var carved := false
	var cursor := from
	blocked.erase(cursor)
	while cursor != target:
		var delta := target - cursor
		if absi(delta.x) >= absi(delta.y):
			cursor.x += signi(delta.x)
		else:
			cursor.y += signi(delta.y)
		if blocked.erase(cursor):
			carved = true
	return carved
