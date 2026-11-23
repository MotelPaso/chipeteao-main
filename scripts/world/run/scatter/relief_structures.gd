class_name ReliefStructures
extends RefCounted
## Las estructuras que visten el relieve por zonas de una etapa:
##
##   - el HITO (el Árbol Hueco) en la zona más alta de la receta (`top`): al
##     borde lejano de la cumbre, o en el medio de la isla del lago;
##   - un PORTAL de piedra en la boca de cada rampa de los niveles altos y
##     de la isla;
##   - una pareja de MENHIRES al pie de cada rampa que baja al llano;
##   - un CÍRCULO de piedras en un claro al nivel donde aparece el equipo
##     (en la Montaña Escalonada, el macizo), y en el Paso de los Dos Montes
##     uno en cada cima y un PORTAL en cada boca del paso, sobre el camino;
##   - RUINAS en claros del llano;
##   - MONOLITOS sueltos, altos, repartidos por todo el mapa;
##   - el CAMINO antiguo, del punto de aparición al puente (ReliefRoad);
##   - el AGUA: el río del cañón y la cascada que lo alimenta (ReliefWaters).
##
## Las escenas vienen del ReliefSettings de la arena (grupo «Estructuras»);
## una escena vacía apaga esa pieza. Todo cuelga del scatter, así arde con
## el bosque en el infierno de Mythos, y entra al grupo GROUP: el barrido de
## colocación del harness las trata como parte del relieve.
##
## No saca números del RNG de la partida ni del scatter: cada pieza se
## siembra con la semilla de partida y su número de orden.

## Grupo de toda estructura puesta aquí.
const GROUP: StringName = &"relief_structures"
## Edita aquí (no hay Inspector); las escenas están en ReliefSettings.
##
## Metros desde el borde lejano de la cumbre hasta el centro del hito.
const LANDMARK_INSET: float = 4.4
## Metros libres alrededor del hito donde no va nada más.
const LANDMARK_KEEPOUT: float = 6.0
## Metros que los pilares de un portal quedan detrás de las esquinas de su
## rampa (sobre la meseta) y hacia afuera de ellas.
const GATE_BACK: float = 2.2
const GATE_ASIDE: float = 1.0
## Metros más allá del pie de una rampa, y hacia afuera de su borde, donde
## va cada menhir de la pareja.
const MENHIR_AHEAD: float = 1.5
const MENHIR_ASIDE: float = 1.4
## Radio del círculo de piedras y metros libres a su alrededor.
const CIRCLE_RADIUS: float = 7.5
const CIRCLE_KEEPOUT: float = 11.0
## A cuántos metros del punto de aparición se busca el claro del círculo.
const CIRCLE_DISTANCE: float = 36.0
## Los portales del paso: a cuántos metros del punto de aparición, sobre el
## camino, y el ancho entre sus pilares.
const PASS_GATE_DISTANCE: float = 44.0
const PASS_GATE_SPAN: float = 9.0
## Largo de una ruina, metros libres a su alrededor, y separación mínima
## entre dos estructuras de claro.
const RUIN_SPAN: float = 13.0
const RUIN_KEEPOUT: float = 9.0
## Metros que el centro de una ruina guarda con el borde de la arena (el
## anillo de árboles vive en los últimos 8 m) y que sus piedras guardan con la
## roca de la máscara: entre el muro roto y una roca no queda un rincón cerrado.
const RUIN_EDGE_GAP: float = 18.0
const RUIN_ROCK_GAP: float = 4.5
const SITE_SPACING: float = 48.0
## Metros que un claro guarda con un POI ya puesto o con una meseta.
const SITE_CLEAR: float = 14.0
## Un monolito: radio de su base, metros que guarda con el relieve y con el
## punto de aparición, separación entre dos y claro que ocupa.
const MONOLITH_RADIUS: float = 1.35
const MONOLITH_RELIEF_GAP: float = 7.0
const MONOLITH_SPAWN_GAP: float = 24.0
const MONOLITH_SPACING: float = 32.0
const MONOLITH_KEEPOUT: float = 3.5
## Intentos por monolito.
const MONOLITH_TRIES: int = 30


## Levanta las estructuras de la etapa como hijas de `scatter`. `taken` son
## los puntos (XZ) que ya ocupa otra cosa: POIs y mesetas. Devuelve los
## claros que ocuparon, como (x, radio, z), para que nadie ponga nada encima.
## Anota en `pieces` lo que puso: el hito ("hollow_tree"), el camino
## ("road"), el río y la cascada (ReliefWaters).
static func raise(scatter: Node3D, terrain: Terrain, run_seed: int,
		taken: PackedVector2Array, pieces: Dictionary = {}) -> PackedVector3Array:
	var claimed := PackedVector3Array()
	if terrain == null or not terrain.has_relief():
		return claimed
	var layout := terrain.relief_layout()
	var settings := layout.settings
	var order := 0
	for index in layout.zones.size():
		var zone := layout.zones[index]
		if zone.top and settings.landmark_scene != null:
			claimed.append(_place_landmark(scatter, terrain, layout, zone, run_seed + order))
			pieces["hollow_tree"] = 1
			order += 1
		for ramp: ReliefLayout.Ramp in zone.ramps:
			order += 1
			if zone.parent >= 0 or zone.kind == &"island":
				_place_gate(scatter, terrain, layout, zone, ramp, run_seed + order * 131)
			else:
				_place_menhirs(scatter, terrain, ramp, run_seed + order * 131)
	# El camino va antes que los claros y los monolitos: lo esquivan.
	var road := ReliefRoad.raise(scatter, terrain, run_seed)
	if not road.is_empty():
		pieces["road"] = 1
	claimed.append_array(road)
	if layout.recipe == &"twin":
		_place_pass(scatter, terrain, layout, run_seed, claimed)
	var busy := taken.duplicate()
	for site: Vector3 in road:
		busy.append(Vector2(site.x, site.z))
	_place_sites(scatter, terrain, layout, run_seed, busy, claimed)
	_place_monoliths(scatter, terrain, layout, run_seed, taken, claimed)
	ReliefWaters.raise(scatter, terrain, layout, run_seed, pieces)
	return claimed


## Una estructura de `scene` colgada de `scatter` en `at`, girada `yaw`.
## Si es un StandingStones, `layout_kind` y `span` la configuran antes de
## entrar al árbol, y `tweaks` (nombre de export -> valor) le cambia medidas.
static func _spawn(scatter: Node3D, scene: PackedScene, at: Vector3, yaw: float,
		seed_value: int, layout_kind: int = -1, span: float = 0.0,
		tweaks: Dictionary = {}) -> Node3D:
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	node.set(&"shape_seed", seed_value)
	if layout_kind >= 0:
		node.set(&"layout", layout_kind)
		node.set(&"span", span)
	for key: StringName in tweaks:
		node.set(key, tweaks[key])
	node.add_to_group(GROUP)
	scatter.add_child(node)
	node.position = at
	node.rotation.y = yaw
	return node


## El giro (yaw) que deja el frente (-Z) de un nodo mirando hacia `toward`.
static func _yaw_to(toward: Vector2) -> float:
	return atan2(-toward.x, -toward.y)


static func _ground(terrain: Terrain, xz: Vector2) -> Vector3:
	return Vector3(xz.x, terrain.height_at(xz.x, xz.y), xz.y)


## El hito: al borde de la cumbre que queda más lejos de su rampa, con el
## frente hacia el centro; en una isla, en su medio, con el frente hacia el
## muelle. Devuelve su claro.
static func _place_landmark(scatter: Node3D, terrain: Terrain, layout: ReliefLayout,
		zone: ReliefLayout.Zone, seed_value: int) -> Vector3:
	if zone.kind == &"island":
		var facing := Vector2.RIGHT
		for crossing: ReliefLayout.Crossing in layout.crossings:
			if crossing.island >= 0 and layout.zones[crossing.island] == zone:
				facing = crossing.head_b - zone.center
		_spawn(scatter, layout.settings.landmark_scene, _ground(terrain, zone.center),
				_yaw_to(facing), seed_value)
		return Vector3(zone.center.x, LANDMARK_KEEPOUT, zone.center.y)
	var away := Vector2.RIGHT
	if not zone.ramps.is_empty():
		away = -zone.ramps[0].dir
	var angle := away.angle()
	var xz := zone.center + away * (layout.zone_radius(zone, angle) - LANDMARK_INSET)
	_spawn(scatter, layout.settings.landmark_scene, _ground(terrain, xz),
			_yaw_to(zone.center - xz), seed_value)
	return Vector3(xz.x, LANDMARK_KEEPOUT, xz.y)


## El Paso de los Dos Montes: un portal de piedra sobre el camino en cada
## boca del paso y un círculo de piedras en cada cima.
static func _place_pass(scatter: Node3D, terrain: Terrain, layout: ReliefLayout, run_seed: int,
		claimed: PackedVector3Array) -> void:
	var scene := layout.settings.stones_scene
	if scene == null:
		return
	for index in layout.road_legs.size():
		var points: PackedVector2Array = layout.road_legs[index]["points"]
		var way := (points[points.size() - 1] - points[0]).normalized()
		var at := way * PASS_GATE_DISTANCE
		if layout.level_at(at) != 0:
			continue
		var across := Vector2(-way.y, way.x)
		var node := _spawn(scatter, scene, _ground(terrain, at), atan2(-across.y, across.x),
				run_seed + 4999 + index * 17, StandingStones.Layout.GATE, PASS_GATE_SPAN)
		if node != null:
			node.name = "PassGate"
		for side: float in [-1.0, 1.0]:
			var foot := at + across * (PASS_GATE_SPAN * 0.5 * side)
			claimed.append(Vector3(foot.x, 2.0, foot.y))
	for index in layout.zones.size():
		var zone := layout.zones[index]
		if zone.parent < 0:
			continue
		_spawn(scatter, scene, _ground(terrain, zone.center), 0.0, run_seed + 6007 + index * 29,
				StandingStones.Layout.CIRCLE, CIRCLE_RADIUS)
		claimed.append(Vector3(zone.center.x, CIRCLE_KEEPOUT, zone.center.y))


## Un portal en la boca de `ramp`: un pilar detrás de cada esquina de la
## rampa, sobre la meseta de `zone`, y el dintel de uno a otro.
static func _place_gate(scatter: Node3D, terrain: Terrain, layout: ReliefLayout,
		zone: ReliefLayout.Zone, ramp: ReliefLayout.Ramp, seed_value: int) -> void:
	var scene := layout.settings.stones_scene
	if scene == null:
		return
	var feet := PackedVector2Array()
	for side: float in [1.0, -1.0]:
		var corner_angle := ramp.corner_hi if side > 0.0 else ramp.corner_lo
		var corner := zone.center + Vector2.from_angle(corner_angle) \
				* layout.zone_radius(zone, corner_angle)
		feet.append(corner - ramp.dir * GATE_BACK + ramp.perp * (GATE_ASIDE * side))
	var middle := (feet[0] + feet[1]) * 0.5
	var across := feet[0] - feet[1]
	var at := _ground(terrain, middle)
	at.y = maxf(terrain.height_at(feet[0].x, feet[0].y), terrain.height_at(feet[1].x, feet[1].y))
	# El eje X local del portal va de un pilar al otro.
	var node := _spawn(scatter, scene, at, atan2(-across.y, across.x), seed_value,
			StandingStones.Layout.GATE, across.length() - 1.5)
	if node != null:
		node.name = "Gate"


## Dos menhires al pie de `ramp`, uno a cada lado de su descanso.
static func _place_menhirs(scatter: Node3D, terrain: Terrain, ramp: ReliefLayout.Ramp,
		seed_value: int) -> void:
	var settings := terrain.relief_layout().settings
	if settings.stones_scene == null:
		return
	for side: float in [-1.0, 1.0]:
		var xz := ramp.origin + ramp.dir * (ramp.length + MENHIR_AHEAD) \
				+ ramp.perp * ((ramp.half_width + MENHIR_ASIDE) * side)
		_spawn(scatter, settings.stones_scene, _ground(terrain, xz), 0.0,
				seed_value + int(side) * 7, StandingStones.Layout.MENHIR, 0.0)


## El círculo de piedras (en un claro del macizo, cerca de CIRCLE_DISTANCE
## del punto de aparición) y las ruinas (en claros del llano), sobre los
## sitios planos que da Terrain.relief_features().
static func _place_sites(scatter: Node3D, terrain: Terrain, layout: ReliefLayout, run_seed: int,
		taken: PackedVector2Array, claimed: PackedVector3Array) -> void:
	var settings := layout.settings
	if settings.stones_scene == null:
		return
	var sites: Array = terrain.relief_features()["sites"]
	var used := PackedVector2Array()
	var circle := Vector2.INF
	var best := INF
	# El círculo, al nivel donde aparece el equipo (el macizo, o el llano).
	var home := layout.level_at(Vector2.ZERO)
	for site: Dictionary in sites:
		var center: Vector3 = site["center"]
		var xz := Vector2(center.x, center.z)
		if layout.level_at(xz) != home or not _site_free(xz, taken, used):
			continue
		var score := absf(xz.length() - CIRCLE_DISTANCE)
		if score < best:
			best = score
			circle = xz
	if circle != Vector2.INF:
		_spawn(scatter, settings.stones_scene, _ground(terrain, circle), 0.0, run_seed + 977,
				StandingStones.Layout.CIRCLE, CIRCLE_RADIUS)
		claimed.append(Vector3(circle.x, CIRCLE_KEEPOUT, circle.y))
		used.append(circle)
	var ruins := 0
	for site: Dictionary in sites:
		if ruins >= settings.ruin_count:
			break
		var center: Vector3 = site["center"]
		var xz := Vector2(center.x, center.z)
		if layout.level_at(xz) != 0 or not _site_free(xz, taken, used) \
				or not _ruin_room(scatter, layout, xz):
			continue
		# El giro sale de la posición: la misma semilla, la misma ruina.
		var yaw := fposmod(xz.x * 0.37 + xz.y * 0.61 + float(run_seed % 97), TAU)
		_spawn(scatter, settings.stones_scene, _ground(terrain, xz), yaw,
				run_seed + 1543 + ruins * 59, StandingStones.Layout.RUIN, RUIN_SPAN)
		claimed.append(Vector3(xz.x, RUIN_KEEPOUT, xz.y))
		used.append(xz)
		ruins += 1


## Los monolitos: piedras paradas de varios metros en puntos al azar donde
## se puede poner algo, lejos del relieve, del punto de aparición, de los
## POIs y entre sí. Tienen su propio RNG (la semilla de partida).
static func _place_monoliths(scatter: Node3D, terrain: Terrain, layout: ReliefLayout,
		run_seed: int, taken: PackedVector2Array, claimed: PackedVector3Array) -> void:
	var settings := layout.settings
	if settings.stones_scene == null or not scatter.has_method(&"can_place"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ 0x4D4F4E4F
	var limit := layout.half - settings.edge_margin
	var placed := PackedVector2Array()
	for index in settings.monolith_count:
		for attempt in MONOLITH_TRIES:
			var xz := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
			if xz.length() < MONOLITH_SPAWN_GAP or layout.level_at(xz) < 0:
				continue
			if not bool(scatter.call(&"can_place", xz, MONOLITH_RELIEF_GAP)):
				continue
			if not _site_free(xz, taken, PackedVector2Array()) or not _apart(xz, placed, claimed):
				continue
			var node := _spawn(scatter, settings.stones_scene, _ground(terrain, xz), 0.0,
					run_seed + 2111 + index * 37, StandingStones.Layout.MENHIR, 0.0,
					{&"stone_height_min": settings.monolith_height_min,
					&"stone_height_max": settings.monolith_height_max,
					&"stone_radius": MONOLITH_RADIUS})
			if node != null:
				node.name = "Monolith"
			placed.append(xz)
			claimed.append(Vector3(xz.x, MONOLITH_KEEPOUT, xz.y))
			break


## True si `xz` queda a MONOLITH_SPACING de los monolitos ya puestos y fuera
## del claro de toda estructura ya puesta.
static func _apart(xz: Vector2, placed: PackedVector2Array, claimed: PackedVector3Array) -> bool:
	for other: Vector2 in placed:
		if xz.distance_to(other) < MONOLITH_SPACING:
			return false
	for site: Vector3 in claimed:
		if Vector2(site.x, site.z).distance_to(xz) < site.y + MONOLITH_KEEPOUT:
			return false
	return true


## True si una ruina cabe en `xz` lejos del anillo del borde y de la roca
## (ArenaScatter.can_build mide la roca con el margen que se le pide).
static func _ruin_room(scatter: Node3D, layout: ReliefLayout, xz: Vector2) -> bool:
	if layout.half - maxf(absf(xz.x), absf(xz.y)) < RUIN_EDGE_GAP:
		return false
	return not scatter.has_method(&"can_build") \
			or bool(scatter.call(&"can_build", xz, RUIN_SPAN * 0.5 + RUIN_ROCK_GAP))


## True si en `xz` no hay un POI ni una meseta cerca (`taken`) ni otra
## estructura de claro (`used`).
static func _site_free(xz: Vector2, taken: PackedVector2Array, used: PackedVector2Array) -> bool:
	for other: Vector2 in taken:
		if xz.distance_to(other) < SITE_CLEAR:
			return false
	for other: Vector2 in used:
		if xz.distance_to(other) < SITE_SPACING:
			return false
	return true
