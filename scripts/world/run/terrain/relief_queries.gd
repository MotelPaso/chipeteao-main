class_name ReliefQueries
extends RefCounted
## Las preguntas que el resto del juego le hace al relieve por zonas, sobre
## un ReliefLayout ya trazado. El Terrain las expone (relief_distance,
## relief_features) y el scatter las usa para su máscara; nadie más llama
## aquí directo.
##
## Todo es geometría en planta y no saca números de ningún RNG.

## Edita aquí (no hay Inspector).
##
## Metros alrededor de cada corte, rampa y puente donde la máscara de la
## arena nunca pone roca: una formación llega hasta 2 m más allá de sus celdas.
const MASK_MARGIN: float = 7.5
## Paso en metros con que se camina de una celda de la máscara a su vecina
## buscando un corte, y desnivel entre dos pasos que ya no se camina ni se salta.
const BARRIER_STEP: float = 0.5
const BARRIER_RISE: float = 1.0
## Las aristas de máscara se revisan solo si su celda queda a menos de esto
## de un corte, en metros.
const BARRIER_REACH: float = 10.0
## Radio en metros de una estructura que quepa en un "sitio plano" de
## relief_features(), su separación de cualquier corte y cuánto puede variar
## el suelo dentro del sitio.
const SITE_RADIUS: float = 10.0
const SITE_CLEARANCE: float = 3.0
const SITE_MAX_RELIEF: float = 1.5
## Separación de la rejilla donde se buscan sitios planos, en metros.
const SITE_GRID: float = 12.0


## Distancia en metros de `point` al corte, rampa o puente más cercano. 0
## sobre una rampa, un tablero o el claro de una cabecera. Lo que quede más
## lejos que `limit` puede salir como INF: quien pregunta solo quiere saber
## si hay algo dentro de su margen.
static func distance(layout: ReliefLayout, point: Vector2, limit: float) -> float:
	var nearest := INF
	for zone: ReliefLayout.Zone in layout.zones:
		nearest = minf(nearest, _zone_distance(layout, zone, point, limit))
	if layout.ravine != null:
		nearest = minf(nearest, _ravine_distance(layout, point, limit))
	for crossing: ReliefLayout.Crossing in layout.crossings:
		nearest = minf(nearest, _crossing_distance(layout, crossing, point))
	return nearest


## Celdas de la máscara de la arena que el relieve necesita abiertas: las
## que caen sobre una zona elevada o el barranco y las que quedan a
## MASK_MARGIN de un corte, una rampa o un puente.
static func mask_cells(layout: ReliefLayout, cell_size: float) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	var per_side := ceili(layout.half * 2.0 / cell_size)
	for x in per_side:
		for y in per_side:
			var center := _cell_center(layout, cell_size, Vector2i(x, y))
			if layout.level_at(center) != 0 \
					or distance(layout, center, MASK_MARGIN) <= MASK_MARGIN:
				cells[Vector2i(x, y)] = true
	return cells


## Aristas entre celdas vecinas de la máscara que NO se cruzan a pie porque
## las separa un corte. Llave: (celda.x, celda.y, 0 = hacia +x | 1 = hacia +y).
## El flood fill de la máscara las respeta, así "alcanzable desde el spawn"
## significa lo mismo para ella que para un raider.
static func mask_barriers(layout: ReliefLayout, cell_size: float) -> Dictionary[Vector3i, bool]:
	var barriers: Dictionary[Vector3i, bool] = {}
	var per_side := ceili(layout.half * 2.0 / cell_size)
	for x in per_side:
		for y in per_side:
			var cell := Vector2i(x, y)
			var center := _cell_center(layout, cell_size, cell)
			if distance(layout, center, BARRIER_REACH) > BARRIER_REACH:
				continue
			for side in 2:
				var next := cell + (Vector2i.RIGHT if side == 0 else Vector2i.DOWN)
				if next.x >= per_side or next.y >= per_side:
					continue
				if _cut_between(layout, center, _cell_center(layout, cell_size, next)):
					barriers[Vector3i(x, y, side)] = true
	return barriers


## La línea de log del trazado.
static func summary(layout: ReliefLayout, map_id: String) -> String:
	return ("Relief layout: %s zones=%d raised=%d ravines=%d cuts=%d tallest=%.1f"
			+ " bridges=%d ramps=%d fallback=%s digest=%s") % [map_id,
			layout.zones.size() + (1 if layout.ravine != null else 0), layout.zones.size(),
			1 if layout.ravine != null else 0, layout.cuts.size(), layout.tallest_cut(),
			layout.crossings.size(), layout.ramp_count(), layout.fallback, layout.digest()]


## Lo que hay en el relieve de la etapa, para quien quiera construir encima
## (mecánicas de mapa, estructuras). Solo lectura; posiciones en el espacio
## del Terrain, con su altura real:
##   crossings: [{a, b: Vector3 (los dos extremos del tablero), span, width}]
##   cuts:      [{foot, rim: Vector3, height, normal: Vector3 (hacia el lado
##              bajo), zone}] un tramo por punto de cada línea de corte (pie
##              y borde uno frente al otro; zone -1 = pared del barranco)
##   floors:    [{kind: "ravine" | "raised", center: Vector3, extent: Vector2
##              (largo y ancho, en metros), zone}]
##   ramps:     [{top, foot: Vector3, width, zone}] (zone -1 = del barranco)
##   sites:     [{center: Vector3, radius}] claros donde cabe una estructura de
##              SITE_RADIUS metros lejos de todo corte y casi planos
static func features(layout: ReliefLayout, terrain: Terrain) -> Dictionary:
	return {
		"crossings": _crossings(layout, terrain),
		"cuts": _cuts(layout, terrain),
		"floors": _floors(layout, terrain),
		"ramps": _ramps(layout, terrain),
		"sites": _sites(layout, terrain),
	}


# --- distancias ------------------------------------------------------------------

static func _zone_distance(layout: ReliefLayout, zone: ReliefLayout.Zone, point: Vector2,
		limit: float) -> float:
	var rel := point - zone.center
	var rho := rel.length()
	var nearest := INF
	if rho <= zone.r_max + limit:
		var angle := rel.angle()
		nearest = absf(rho - layout.polar(zone.radii, angle)) / layout.polar(zone.oblique, angle)
	for ramp: ReliefLayout.Ramp in zone.ramps:
		var local := point - ramp.origin
		var u := local.dot(ramp.dir)
		var v := absf(local.dot(ramp.perp))
		var along := maxf(maxf(ramp.back - u, u - ramp.length - ReliefLayout.RAMP_LANDING), 0.0)
		var across := maxf(v - ramp.half_width, 0.0)
		nearest = minf(nearest, sqrt(along * along + across * across))
	return nearest


static func _ravine_distance(layout: ReliefLayout, point: Vector2, limit: float) -> float:
	var ravine := layout.ravine
	var coords := layout.ravine_coords(point)
	if coords.x < 0.0:
		# Antes o después de los extremos: la boca de la rampa es un tramo de
		# medio ancho alrededor del punto final del eje.
		var tip := minf(point.distance_to(ravine.points[0]),
				point.distance_to(ravine.points[ravine.points.size() - 1]))
		var gap := maxf(tip - ravine.half_width, 0.0)
		return gap if gap <= limit + ReliefLayout.RAMP_LANDING else INF
	if coords.y > ravine.half_width:
		return coords.y - ravine.half_width
	if coords.x < ravine.ramp or coords.x > ravine.length - ravine.ramp:
		return 0.0
	return ravine.half_width - coords.y


static func _crossing_distance(layout: ReliefLayout, crossing: ReliefLayout.Crossing,
		point: Vector2) -> float:
	var local := point - crossing.center
	var along := maxf(absf(local.dot(crossing.axis)) - crossing.span * 0.5
			- ReliefLayout.HEAD_SETBACK, 0.0)
	var across := maxf(absf(local.dot(Vector2(-crossing.axis.y, crossing.axis.x)))
			- crossing.width * 0.5, 0.0)
	var deck := sqrt(along * along + across * across)
	var radius := layout.settings.bridgehead_radius
	var heads := minf(point.distance_to(crossing.head_a), point.distance_to(crossing.head_b))
	return minf(deck, maxf(heads - radius, 0.0))


static func _cell_center(layout: ReliefLayout, cell_size: float, cell: Vector2i) -> Vector2:
	return Vector2(-layout.half + (float(cell.x) + 0.5) * cell_size,
			-layout.half + (float(cell.y) + 0.5) * cell_size)


## True si entre `from` y `to` hay un desnivel que no se camina ni se salta.
static func _cut_between(layout: ReliefLayout, from: Vector2, to: Vector2) -> bool:
	var steps := maxi(ceili(from.distance_to(to) / BARRIER_STEP), 1)
	var previous := layout.offset_at(from)
	for step in range(1, steps + 1):
		var here := layout.offset_at(from.lerp(to, float(step) / float(steps)))
		if absf(here - previous) > BARRIER_RISE:
			return true
		previous = here
	return false


# --- consulta de la etapa ----------------------------------------------------------

static func _at(terrain: Terrain, point: Vector2) -> Vector3:
	return Vector3(point.x, terrain.height_at(point.x, point.y), point.y)


static func _crossings(layout: ReliefLayout, terrain: Terrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crossing: ReliefLayout.Crossing in layout.crossings:
		var reach := crossing.axis * (crossing.span * 0.5)
		var a := crossing.center + reach
		var b := crossing.center - reach
		out.append({"a": Vector3(a.x, crossing.level, a.y),
				"b": Vector3(b.x, crossing.level, b.y),
				"span": crossing.span, "width": crossing.width})
	return out


static func _cuts(layout: ReliefLayout, terrain: Terrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cut: ReliefLayout.CutPath in layout.cuts:
		for index in cut.points.size():
			var height := cut.upper[index] - cut.lower[index]
			if height < 0.5:
				continue
			var point := cut.points[index]
			var ground := terrain.base_height_at(point.x, point.y)
			var normal := cut.normals[index]
			out.append({"rim": Vector3(point.x, ground + cut.upper[index], point.y),
					"foot": Vector3(point.x, ground + cut.lower[index], point.y),
					"height": height, "normal": Vector3(normal.x, 0.0, normal.y),
					"zone": cut.zone})
	return out


static func _floors(layout: ReliefLayout, terrain: Terrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if layout.ravine != null:
		var ravine := layout.ravine
		var middle := layout.ravine_frame(ravine.length * 0.5)[0]
		out.append({"kind": "ravine", "center": _at(terrain, middle), "zone": -1,
				"extent": Vector2(ravine.length - ravine.ramp * 2.0, ravine.half_width * 2.0)})
	for index in layout.zones.size():
		var zone := layout.zones[index]
		out.append({"kind": "raised", "center": _at(terrain, zone.center), "zone": index,
				"extent": Vector2(zone.r_max * 2.0, zone.r_min * 2.0)})
	return out


static func _ramps(layout: ReliefLayout, terrain: Terrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in layout.zones.size():
		for ramp: ReliefLayout.Ramp in layout.zones[index].ramps:
			out.append({"top": _at(terrain, ramp.origin),
					"foot": _at(terrain, ramp.origin + ramp.dir * ramp.length),
					"width": ramp.half_width * 2.0, "zone": index})
	if layout.ravine != null:
		var ravine := layout.ravine
		for ends: Vector2 in [Vector2(0.0, ravine.ramp), Vector2(ravine.length,
				ravine.length - ravine.ramp)]:
			out.append({"top": _at(terrain, layout.ravine_frame(ends.x)[0]),
					"foot": _at(terrain, layout.ravine_frame(ends.y)[0]),
					"width": ravine.half_width * 2.0, "zone": -1})
	return out


## Puntos de una rejilla de SITE_GRID metros lejos de todo corte y con el
## suelo casi plano en SITE_RADIUS a la redonda. No mira rocas ni props: eso
## se lo pregunta quien construye a arena_bounds.can_place().
static func _sites(layout: ReliefLayout, terrain: Terrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var clear := SITE_RADIUS + SITE_CLEARANCE
	var limit := layout.half - layout.settings.edge_margin * 0.5
	var along := -limit
	while along <= limit:
		var across := -limit
		while across <= limit:
			var point := Vector2(along, across)
			if distance(layout, point, clear) > clear and _flat(terrain, point):
				out.append({"center": _at(terrain, point), "radius": SITE_RADIUS})
			across += SITE_GRID
		along += SITE_GRID
	return out


static func _flat(terrain: Terrain, point: Vector2) -> bool:
	var low := terrain.height_at(point.x, point.y)
	var high := low
	for index in 8:
		var rim := point + Vector2.from_angle(float(index) * TAU / 8.0) * SITE_RADIUS
		var height := terrain.height_at(rim.x, rim.y)
		low = minf(low, height)
		high = maxf(high, height)
	return high - low <= SITE_MAX_RELIEF
