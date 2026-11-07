class_name EnemySeparation
extends RefCounted
## Separación de la horda: cada enemigo suma empujes que lo alejan de los
## "enemies" vecinos dentro de su separation_radius, así la horda se reparte
## en vez de apilarse. Para no comparar cada cuerpo con toda la horda, los
## cuerpos se reparten una vez por tick de física en una grilla de celdas
## cuadradas del plano, y cada escaneo visita solo su celda y el anillo de
## alrededor (O(n) por tick en vez de O(n²)). Todo es estático: una sola
## grilla compartida. La celda de cada cuerpo se guarda en el propio cuerpo
## (EnemyBase.separation_key y separation_key_frame).
##
## La grilla la arma el primer escaneo del tick con posiciones VIVAS y se
## mantiene viva el resto del tick (follow). El escaneo es el de la horda
## completa (mismo test de distancia, chequeo de grupo, empujón de apilados
## y caída), así que vecinos y contribuciones son los mismos; solo cambia el
## orden de la suma (redondeo float, ~1e-7). Va en el bucle más caliente del
## juego: nada aquí reserva memoria por frame salvo la grilla del tick.

## Lado de celda en metros. Mayor que todo separation_radius en uso (1.2 m),
## así alcanza con un anillo de celdas; un radio mayor sigue siendo correcto
## porque el escaneo abre más anillos.
const CELL_SIZE: float = 1.25
## La celda (cx, cz) se empaqueta como cx * KEY_STRIDE + cz. Es lineal, así
## la clave de un vecino es una suma; dos celdas solo se confunden pasadas
## 2^19 celdas (~650 km), y ahí el escaneo vería candidatos DE MÁS que el
## test de distancia descarta. Nunca de menos.
const KEY_STRIDE: int = 1 << 20

## Una sola foto del grupo "enemies" por tick: una consulta de grupo por tick
## en vez de una por cuerpo. Las entradas siguen siendo instancias válidas
## todo el tick (los free son diferidos); igual se saltan los cuerpos que
## salieron del grupo o del árbol.
static var _snapshot: Array[Node] = []
static var _snapshot_frame: int = -1
static var _grid: Dictionary = {}
static var _grid_frame: int = -1
## El cuerpo cuyo movimiento de este tick todavía no está en la grilla: el
## último que corrió _physics_process, si estaba repartido. A lo sumo uno.
static var _pending: EnemyBase = null


## Va al inicio del _physics_process de cada enemigo, antes de que algo lo
## mueva. Un cuerpo solo se mueve dentro de su propio _physics_process
## (incluido lo de la subclase: BossBase recorta DESPUÉS de super()), y ningún
## escaneo corre entre el final del de un cuerpo y el inicio del siguiente.
## Por eso repartir de nuevo aquí al cuerpo ANTERIOR ve todo su movimiento
## (un salto del Fenwraith, un brinco del Grubthing, el recorte del jefe) a
## tiempo para todo escaneo posterior. No hace nada si la grilla de este
## tick todavía no existe.
static func follow(body: EnemyBase) -> void:
	if _grid_frame != Engine.get_physics_frames():
		return
	if is_instance_valid(_pending):
		_rebucket(_pending)
	_pending = body if body.separation_key_frame == _grid_frame else null


## Suma de empujes que alejan a `body` de los "enemies" vivos dentro de su
## separation_radius, con caída (máximo al solaparse, cero en el borde).
## Solo visita las celdas alrededor del cuerpo, sobre posiciones vivas.
static func push(body: EnemyBase) -> Vector3:
	var grid := _grid_this_tick(body.get_tree(), body)
	var total := Vector3.ZERO
	var here := body.global_position
	var radius := body.separation_radius
	# Un vecino pasa el test de distancia solo si está más cerca que el radio
	# en cada eje plano, así un anillo de celdas cubre todo radio menor que la
	# celda (con ~4% de margen a 1.2 m, muy por encima del redondeo float del
	# índice); un radio mayor escanea los anillos necesarios.
	var rings := 1
	if radius >= CELL_SIZE:
		rings = ceili(radius / CELL_SIZE) + 1
	var cell_x := floori(here.x / CELL_SIZE)
	var cell_z := floori(here.z / CELL_SIZE)
	for dx in range(-rings, rings + 1):
		var column_key := (cell_x + dx) * KEY_STRIDE + cell_z
		for dz in range(-rings, rings + 1):
			var cell: Variant = grid.get(column_key + dz)
			if cell == null:
				continue
			# Bucle tipado: las entradas siguen siendo instancias válidas todo
			# el tick (los free son diferidos), como la foto de la que salen.
			for other: Node3D in cell:
				if other == body or not other.is_inside_tree():
					continue
				var away := here - other.global_position
				away.y = 0.0
				var dist := away.length()
				if dist >= radius:
					continue
				# Solo para vecinos reales: un cuerpo que murió ANTES en este tick
				# sigue en la foto y empujaría a la horda como cadáver.
				if not other.is_in_group(&"enemies"):
					continue
				if dist < 0.01:
					# Cuerpos apilados exactos: se separan en una dirección estable por instancia.
					away = Vector3.RIGHT.rotated(Vector3.UP,
							float(body.get_instance_id() % 64) * TAU / 64.0)
					dist = 0.01
				total += (away / dist) * (1.0 - dist / radius)
	return total


## La grilla de este tick; la arma el primer escaneo que la pide. Cada cuerpo
## de la foto se reparte donde está AHORA: los que ya corrieron este tick
## terminaron de moverse, y al resto se lo sigue con follow(). `builder` es
## el cuerpo que escanea, a mitad de su _physics_process.
static func _grid_this_tick(tree: SceneTree, builder: EnemyBase) -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame == _grid_frame:
		return _grid
	_grid_frame = frame
	_grid.clear()
	for node: Node in _enemies_this_tick(tree):
		var body := node as Node3D
		# El escaneo igual se salta los cuerpos fuera del árbol, que no tienen posición.
		if body == null or not body.is_inside_tree():
			continue
		var at := body.global_position
		var key := floori(at.x / CELL_SIZE) * KEY_STRIDE + floori(at.z / CELL_SIZE)
		var cell: Variant = _grid.get(key)
		if cell == null:
			_grid[key] = [body]
		else:
			(cell as Array).append(body)
		var enemy := body as EnemyBase
		if enemy != null:
			enemy.separation_key = key
			enemy.separation_key_frame = frame
	_pending = builder if builder.separation_key_frame == frame else null
	return _grid


static func _rebucket(body: EnemyBase) -> void:
	# Fuera del árbol su entrada vieja no molesta: el escaneo se la salta.
	if not body.is_inside_tree():
		return
	var at := body.global_position
	var key := floori(at.x / CELL_SIZE) * KEY_STRIDE + floori(at.z / CELL_SIZE)
	if key == body.separation_key:
		return
	var old_cell: Variant = _grid.get(body.separation_key)
	if old_cell != null:
		(old_cell as Array).erase(body)
	var cell: Variant = _grid.get(key)
	if cell == null:
		_grid[key] = [body]
	else:
		(cell as Array).append(body)
	body.separation_key = key


static func _enemies_this_tick(tree: SceneTree) -> Array[Node]:
	var frame := Engine.get_physics_frames()
	if frame != _snapshot_frame:
		_snapshot_frame = frame
		_snapshot = tree.get_nodes_in_group(&"enemies")
	return _snapshot
