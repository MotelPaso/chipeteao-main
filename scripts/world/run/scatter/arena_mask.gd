class_name ArenaMask
extends RefCounted
## Máscara de celdas caminables de una arena: una cuadrícula gruesa sobre el
## cuadrado de juego donde algunas regiones de celdas quedan bloqueadas por
## formaciones de roca. Un flood fill desde el spawn garantiza que toda celda
## abierta se alcanza a pie.
##
## La crea y la consulta el scatter (scatter.gd), que responde por ella a
## is_walkable() y compañía a través del grupo "arena_bounds". No tiene
## Inspector: se ajusta con los exports "Máscara de la arena" del scatter,
## que _new_mask() copia aquí antes de build().
##
## Saca números del MISMO RandomNumberGenerator que el scatter (se lo pasa
## al crearla): build() y random_walkable_point() sortean en el orden de
## siempre, y BONK_GAME_SEED reproduce la máscara.

## Constantes del algoritmo: edita aquí (no hay Inspector). Los valores que
## se ajustan por arena están en los exports del scatter.
##
## Los cuatro pasos de la vecindad-4: crecimiento, relleno de muescas, flood
## fill y división en regiones usan la misma.
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## "Ninguna celda", para el selector de semillas de formación.
const NO_CELL := Vector2i(-1, -1)
## Atracción hacia celdas ya rodeadas por dos o más lados mientras la
## formación crece: da masas sólidas en vez de brazos de una celda.
const FORMATION_COMPACTNESS: float = 1.0

## Copias de los exports del scatter (sus tooltips explican cada uno). Sin
## valores propios a propósito: la única fuente es el scatter.
var enabled: bool
var half_extent: float
var cell_size: float
var blobs_min: int
var blobs_max: int
var blob_cells_min: int
var blob_cells_max: int
var ridge_bias: float
var blob_spacing: int
var formation_gap: int
var border_cells: int
var protect_radius: float
var min_open_fraction: float

## El RNG del scatter, compartido.
var _rng: RandomNumberGenerator
## Celdas bloqueadas (coordenadas de cuadrícula -> true) y celdas por lado.
var _blocked: Dictionary[Vector2i, bool] = {}
var _cells_per_side: int = 0


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Construye la máscara de la etapa e imprime `Arena mask:`. `protected_seeds`
## son los puntos planos donde nunca hay roca (el spawn y los keepouts de
## autor), en el orden en que el scatter los recorre.
func build(protected_seeds: Array[Vector2]) -> void:
	_cells_per_side = maxi(ceili(half_extent * 2.0 / cell_size), 3)
	var protected := _protected_cells(protected_seeds)
	var formations := _rng.randi_range(blobs_min, blobs_max)
	for attempt in 4:
		_blocked.clear()
		var seeds: Array[Vector2i] = []
		# Qué formación creció cada celda bloqueada, para que la siguiente
		# guarde formation_gap respecto de ella.
		var owners: Dictionary[Vector2i, int] = {}
		for formation in formations:
			var seed_cell := _pick_formation_seed(seeds, protected, owners)
			if seed_cell == NO_CELL:
				continue
			seeds.append(seed_cell)
			_grow_formation(seed_cell,
					_rng.randi_range(blob_cells_min, blob_cells_max),
					protected, owners, seeds.size())
		_fill_notches(protected)
		_seal_unreachable(protected)
		if float(open_cell_count()) / float(_cells_per_side * _cells_per_side) \
				>= min_open_fraction:
			break
		formations = maxi(formations - 1, 1)
	var cells := _cells_per_side * _cells_per_side
	# El log da la FRACCIÓN ABIERTA, la cifra que persigue el bucle de
	# reconstrucción de arriba (min_open_fraction).
	print("Arena mask: %d/%d cells blocked, open=%.2f" % [
			_blocked.size(), cells, float(open_cell_count()) / float(maxi(cells, 1))])


## True si una posición plana está dentro de la arena y no cae en una celda
## bloqueada.
func is_walkable(xz: Vector2) -> bool:
	if absf(xz.x) > half_extent or absf(xz.y) > half_extent:
		return false
	if not enabled or _cells_per_side == 0:
		return true
	# La cuadrícula, no solo el cuadrado: un punto en exactamente
	# +-half_extent cae una celda FUERA de la última fila, y una celda fuera
	# de la cuadrícula nunca está en _blocked.
	var cell := cell_of(xz)
	return _in_grid(cell) and not _blocked.has(cell)


## True si `center` y los ocho puntos a `radius` a su alrededor son
## caminables: la prueba barata de "ninguna formación llega aquí".
func clear_of(center: Vector2, radius: float) -> bool:
	if not is_walkable(center):
		return false
	if not enabled or radius <= 0.0:
		return true
	for index in 8:
		if not is_walkable(center + Vector2.from_angle(float(index) * TAU / 8.0) * radius):
			return false
	return true


func blocked_cell_count() -> int:
	return _blocked.size()


func open_cell_count() -> int:
	return _cells_per_side * _cells_per_side - _blocked.size()


## Coordenadas de cada celda bloqueada, en el orden en que se bloquearon.
func blocked_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _blocked:
		cells.append(cell)
	return cells


## Centro plano de una celda.
func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
			-half_extent + (float(cell.x) + 0.5) * cell_size,
			-half_extent + (float(cell.y) + 0.5) * cell_size)


## Celda donde cae una posición plana.
func cell_of(xz: Vector2) -> Vector2i:
	return Vector2i(
			floori((xz.x + half_extent) / cell_size),
			floori((xz.y + half_extent) / cell_size))


## Un punto plano caminable al azar (uniforme sobre el área abierta), o el
## origen si 64 intentos fallan.
func random_walkable_point(margin: float) -> Vector2:
	for attempt in 64:
		var candidate := Vector2(
				_rng.randf_range(-half_extent + margin, half_extent - margin),
				_rng.randf_range(-half_extent + margin, half_extent - margin))
		if is_walkable(candidate):
			return candidate
	return Vector2.ZERO


## Las celdas bloqueadas divididas en regiones conexas-4, cada una un
## conjunto (celda -> true) con la forma que recibe RockFormation.build().
func blocked_regions() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for start: Vector2i in _blocked:
		if seen.has(start):
			continue
		var region: Dictionary[Vector2i, bool] = {start: true}
		seen[start] = true
		var frontier: Array[Vector2i] = [start]
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			for step: Vector2i in STEPS:
				var next := cell + step
				if _blocked.has(next) and not seen.has(next):
					seen[next] = true
					region[next] = true
					frontier.append(next)
		regions.append(region)
	return regions


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
			and cell.x < _cells_per_side and cell.y < _cells_per_side


## Celdas que deben quedar abiertas: toda celda a menos de protect_radius de
## una de las semillas (spawn, spots de verticalidad, grupos de rocas).
func _protected_cells(seeds: Array[Vector2]) -> Dictionary[Vector2i, bool]:
	var protected: Dictionary[Vector2i, bool] = {}
	var reach := ceili(protect_radius / cell_size) + 1
	var half := cell_size * 0.5
	for seed_xz: Vector2 in seeds:
		var home := cell_of(seed_xz)
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var cell := home + Vector2i(dx, dy)
				# Distancia de la semilla al CUADRADO de la celda, no a su
				# centro: una celda que el círculo apenas toca sigue siendo
				# suelo que el spot necesita.
				var center := cell_center(cell)
				var gap := Vector2(maxf(absf(seed_xz.x - center.x) - half, 0.0),
						maxf(absf(seed_xz.y - center.y) - half, 0.0))
				if gap.length() <= protect_radius:
					protected[cell] = true
	return protected


## True donde la roca puede sembrar o crecer: dentro de la cuadrícula, fuera
## del anillo de borde abierto y fuera de las celdas protegidas.
func _rock_may_grow(cell: Vector2i, protected: Dictionary[Vector2i, bool]) -> bool:
	var last := _cells_per_side - 1 - border_cells
	return cell.x >= border_cells and cell.y >= border_cells \
			and cell.x <= last and cell.y <= last and not protected.has(cell)


## Celda semilla para la siguiente formación: a blob_spacing celdas o más
## (Chebyshev) de cada semilla previa y libre de las formaciones ya
## crecidas, o NO_CELL si la etapa está llena.
func _pick_formation_seed(seeds: Array[Vector2i], protected: Dictionary[Vector2i, bool],
		owners: Dictionary[Vector2i, int]) -> Vector2i:
	for attempt in 32:
		var cell := Vector2i(
				_rng.randi_range(border_cells, _cells_per_side - 1 - border_cells),
				_rng.randi_range(border_cells, _cells_per_side - 1 - border_cells))
		if _blocked.has(cell) or not _rock_may_grow(cell, protected):
			continue
		if _crowds_formation(cell, -1, owners):
			continue
		var crowded := false
		for other: Vector2i in seeds:
			if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) < blob_spacing:
				crowded = true
				break
		if not crowded:
			return cell
	return NO_CELL


## True si `cell` está a formation_gap celdas o menos (Chebyshev) de una
## celda crecida por cualquier formación distinta de `index`.
func _crowds_formation(cell: Vector2i, index: int, owners: Dictionary[Vector2i, int]) -> bool:
	for dx in range(-formation_gap, formation_gap + 1):
		for dy in range(-formation_gap, formation_gap + 1):
			var owner_index: int = owners.get(cell + Vector2i(dx, dy), index)
			if owner_index != index:
				return true
	return false


## Hace crecer una formación desde `start` hasta `size` celdas por acreción:
## cada paso añade una celda de la frontera (los vecinos-4 libres de lo ya
## crecido), con peso hacia el eje propio de la formación (crestas) y hacia
## celdas ya rodeadas por dos o más lados (masas sólidas).
func _grow_formation(start: Vector2i, size: int, protected: Dictionary[Vector2i, bool],
		owners: Dictionary[Vector2i, int], index: int) -> void:
	var axis := Vector2.from_angle(_rng.randf_range(0.0, TAU))
	var stretch := _rng.randf_range(0.0, ridge_bias)
	var grown: Dictionary[Vector2i, bool] = {}
	var frontier: Dictionary[Vector2i, bool] = {}
	var next_cell := start
	while true:
		grown[next_cell] = true
		frontier.erase(next_cell)
		_blocked[next_cell] = true
		owners[next_cell] = index
		if grown.size() >= size:
			return
		for step: Vector2i in STEPS:
			var next := next_cell + step
			if not grown.has(next) and _rock_may_grow(next, protected) \
					and not _crowds_formation(next, index, owners):
				frontier[next] = true
		if frontier.is_empty():
			return
		next_cell = _pick_frontier_cell(frontier, grown, start, axis, stretch)


## Sortea la siguiente celda de la frontera, con peso hacia el eje de la
## formación y hacia celdas ya rodeadas. Un solo randf() por llamada.
func _pick_frontier_cell(frontier: Dictionary[Vector2i, bool], grown: Dictionary[Vector2i, bool],
		start: Vector2i, axis: Vector2, stretch: float) -> Vector2i:
	var options: Array[Vector2i] = []
	var weights: Array[float] = []
	var total := 0.0
	for cell: Vector2i in frontier:
		var along := absf(Vector2(cell - start).normalized().dot(axis))
		var walls := 0
		for side: Vector2i in STEPS:
			if grown.has(cell + side):
				walls += 1
		var weight := 1.0 + stretch * along * along \
				+ FORMATION_COMPACTNESS * float(walls - 1)
		options.append(cell)
		weights.append(weight)
		total += weight
	var pick := _rng.randf() * total
	for option in options.size():
		pick -= weights[option]
		if pick <= 0.0:
			return options[option]
	return options[options.size() - 1]


## Las celdas abiertas rodeadas de roca por tres o cuatro lados se vuelven
## roca: una muesca cerrada por tres lados no sirve para pelear, y su
## contorno cuadrado es lo único que el margen de la formación no esconde.
func _fill_notches(protected: Dictionary[Vector2i, bool]) -> void:
	for sweep in 3:
		var notches: Array[Vector2i] = []
		for x in _cells_per_side:
			for y in _cells_per_side:
				var cell := Vector2i(x, y)
				if _blocked.has(cell) or not _rock_may_grow(cell, protected):
					continue
				var walls := 0
				for step: Vector2i in STEPS:
					if _blocked.has(cell + step):
						walls += 1
				if walls >= 3:
					notches.append(cell)
		if notches.is_empty():
			return
		for cell: Vector2i in notches:
			_blocked[cell] = true


## Flood fill desde la celda del spawn; las celdas abiertas que no alcanza
## se sellan, así toda celda abierta que queda se alcanza a pie. Las celdas
## PROTEGIDAS nunca se sellan: si una quedó aislada, se abre un pasillo
## hasta suelo alcanzado y se repite el relleno. Así se cumplen las dos
## cosas: todo lo abierto es alcanzable y ningún spot de autor queda bajo
## una formación.
func _seal_unreachable(protected: Dictionary[Vector2i, bool]) -> void:
	var reached := _reachable_cells()
	var carved := false
	for cell: Vector2i in protected:
		if not _in_grid(cell) or reached.has(cell):
			continue
		if _carve_corridor(cell, reached):
			carved = true
	if carved:
		reached = _reachable_cells()
	for x in _cells_per_side:
		for y in _cells_per_side:
			var cell := Vector2i(x, y)
			if not reached.has(cell):
				_blocked[cell] = true


## Flood fill vecindad-4 desde la celda del spawn sobre las celdas abiertas.
func _reachable_cells() -> Dictionary[Vector2i, bool]:
	var start := cell_of(Vector2.ZERO)
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step: Vector2i in STEPS:
			var next := cell + step
			if not _in_grid(next) or reached.has(next) or _blocked.has(next):
				continue
			reached[next] = true
			frontier.append(next)
	return reached


## Desbloquea una escalera de celdas desde `from` hasta la celda alcanzada
## más cercana. Conexa-4 a propósito (un eje por paso), para que el pasillo
## se camine con la misma vecindad del flood fill. True si abrió algo.
func _carve_corridor(from: Vector2i, reached: Dictionary[Vector2i, bool]) -> bool:
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
	_blocked.erase(cursor)
	while cursor != target:
		var delta := target - cursor
		if absi(delta.x) >= absi(delta.y):
			cursor.x += signi(delta.x)
		else:
			cursor.y += signi(delta.y)
		if _blocked.erase(cursor):
			carved = true
	return carved
