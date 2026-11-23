class_name RecipeKit
extends RefCounted
## Lo que comparten las recetas del relieve por zonas que no son la Montaña
## Escalonada (RecipeRiver, RecipeTwin, RecipeLake): el camino que deja la
## receta en ReliefLayout.road_legs, los cerros que lo respetan y las
## preguntas de geometría sobre él. Todo es geometría en planta.

## Edita aquí (no hay Inspector); los valores de diseño están en ReliefSettings.
##
## Metros del punto de aparición donde arranca el camino.
const ROAD_START: float = 7.0
## Metros que sigue el camino pasada la cabecera de la otra orilla.
const ROAD_BEYOND: float = 28.0
## Metros libres a cada lado del camino donde no cae un cerro ni el pie de
## una de sus rampas.
const ROAD_CLEARANCE: float = 8.0
## Metros que el camino guarda con el borde de la arena.
const ROAD_EDGE: float = 18.0
## Paso con que se revisa que un tramo recto no cruce el cañón, en metros.
const ROAD_CHECK_STEP: float = 2.0
## Metros que el camino guarda con el borde del cañón.
const ROAD_FROM_CANYON: float = 5.0
## Metros que una zona del llano guarda con el claro del punto de aparición.
const SPAWN_GAP: float = 6.0
## La meseta-manantial: metros entre su borde y el borde del cañón (de ahí
## cae la cascada).
const SPRING_GAP: float = 16.0


## Distancia de `point` al tramo de `a` a `b`.
static func segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var run := b - a
	var length_sq := run.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(run) / length_sq, 0.0, 1.0)
	return point.distance_to(a + run * t)


## Distancia de `point` al camino de la receta (INF sin camino).
static func road_distance(layout: ReliefLayout, point: Vector2) -> float:
	var nearest := INF
	for leg: Dictionary in layout.road_legs:
		var points: PackedVector2Array = leg["points"]
		for index in points.size() - 1:
			nearest = minf(nearest, segment_distance(point, points[index], points[index + 1]))
	return nearest


## True si `zone` (su contorno y el pie de sus rampas) queda a `gap` metros o
## más del camino de la receta.
static func clear_of_road(layout: ReliefLayout, zone: ReliefLayout.Zone, gap: float) -> bool:
	if layout.road_legs.is_empty():
		return true
	for point: Vector2 in ReliefPlanner.rim_points(zone):
		if road_distance(layout, point) < gap:
			return false
	for ramp: ReliefLayout.Ramp in zone.ramps:
		if not _ramp_clear(layout, ramp, gap):
			return false
	return true


## Saca de `zone` las rampas que caen a menos de `gap` metros del camino de
## la receta. Devuelve cuántas quedaron.
static func drop_road_ramps(layout: ReliefLayout, zone: ReliefLayout.Zone, gap: float) -> int:
	var kept: Array[ReliefLayout.Ramp] = []
	for ramp: ReliefLayout.Ramp in zone.ramps:
		if _ramp_clear(layout, ramp, gap):
			kept.append(ramp)
	zone.ramps = kept
	return kept.size()


static func _ramp_clear(layout: ReliefLayout, ramp: ReliefLayout.Ramp, gap: float) -> bool:
	for along: float in [0.0, ramp.length * 0.5, ramp.length + ReliefLayout.RAMP_LANDING]:
		for side: float in [-1.0, 0.0, 1.0]:
			var probe := ramp.origin + ramp.dir * along + ramp.perp * (ramp.half_width * side)
			if road_distance(layout, probe) < gap:
				return false
	return true


## True si el contorno de `zone` queda fuera del claro del punto de
## aparición (spawn_clearance más SPAWN_GAP): en estas recetas el equipo
## aparece en el llano.
static func spawn_clear(layout: ReliefLayout, zone: ReliefLayout.Zone) -> bool:
	var clear := layout.settings.spawn_clearance + SPAWN_GAP
	for point: Vector2 in ReliefPlanner.rim_points(zone):
		if point.length() < clear:
			return false
	return zone.center.length() >= clear


## Entre `low` y `high` cerros sueltos que respetan el camino. False si no
## cupieron `low` (y no es el trazado de reserva).
static func add_buttes(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool, low: int,
		high: int) -> bool:
	var wanted := ReliefPlanner.roll_int(rng, low, high, calm)
	var placed := 0
	for index in wanted:
		if not ReliefPlanner.place_butte(layout, rng, calm):
			continue
		var butte := layout.zones[layout.zones.size() - 1]
		if spawn_clear(layout, butte) and clear_of_road(layout, butte, ROAD_CLEARANCE):
			placed += 1
		else:
			layout.zones.pop_back()
	return placed >= low or calm


## True si el tramo recto de `a` a `b` no pisa el cañón (con margen) ni una
## zona elevada. Los últimos metros antes de `b` (una cabecera de puente, a
## pasos del borde) no miran el margen del cañón.
static func straight_clear(layout: ReliefLayout, a: Vector2, b: Vector2) -> bool:
	var steps := maxi(ceili(a.distance_to(b) / ROAD_CHECK_STEP), 1)
	for step in steps + 1:
		var point := a.lerp(b, float(step) / float(steps))
		if layout.level_at(point) != 0:
			return false
		var coords := layout.ravine_coords(point)
		if coords.x >= 0.0 and point.distance_to(b) > ReliefLayout.HEAD_SETBACK * 2.0 \
				and coords.y < layout.ravine.half_at(coords.x) + ROAD_FROM_CANYON:
			return false
	return true


## El cruce cuya cabecera de este lado queda más cerca del punto de
## aparición y se alcanza en línea recta, como [cruce, cabecera cercana,
## cabecera lejana]; vacío si ninguno.
static func nearest_crossing(layout: ReliefLayout) -> Array:
	var best: Array = []
	var best_distance := INF
	for crossing: ReliefLayout.Crossing in layout.crossings:
		var near := crossing.head_a
		var far := crossing.head_b
		if far.length() < near.length():
			near = crossing.head_b
			far = crossing.head_a
		var start := near.normalized() * ROAD_START
		if near.length() < best_distance and straight_clear(layout, start, near):
			best_distance = near.length()
			best = [crossing, near, far]
	return best


## Los dos tramos del camino que cruza un puente: del punto de aparición a
## la cabecera cercana, y de la lejana un trecho más allá, perdiéndose.
static func bridge_road(layout: ReliefLayout) -> bool:
	var pick := nearest_crossing(layout)
	if pick.is_empty():
		return false
	var near: Vector2 = pick[1]
	var far: Vector2 = pick[2]
	var onward := (far - near).normalized()
	layout.road_legs.append({"points": PackedVector2Array([near.normalized() * ROAD_START, near]),
			"fading": false})
	layout.road_legs.append({"points": PackedVector2Array([far, far + onward * ROAD_BEYOND]),
			"fading": true})
	return true


## Una meseta-manantial junto al cañón, entre `reach.x` y `reach.y` metros
## pasada la rampa de una punta (`from_start`: la del inicio del eje), de
## preferencia del lado lejos del punto de aparición (los intentos impares
## prueban el otro), con un radio medio entre `radius.x` y `radius.y`: desde
## su acantilado cae la cascada al cañón (ReliefWaters). La meseta se queda
## solo si su cascada cabe; si no cabe en ningún intento, o la cascada está
## apagada (ReliefSettings.cascade), no hay manantial.
static func place_springhead(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool,
		from_start: bool, reach: Vector2, radius: Vector2) -> bool:
	var s := layout.settings
	if not s.cascade:
		return false
	var ravine := layout.ravine
	for attempt in ReliefPlanner.PLACE_ATTEMPTS:
		var run := ravine.ramp + ReliefPlanner.roll(rng, reach.x, reach.y, calm)
		var at := run if from_start else ravine.length - run
		var frame := layout.ravine_frame(at)
		var left := Vector2(-frame[1].y, frame[1].x)
		var side := 1.0 if frame[0].dot(left) >= 0.0 else -1.0
		if attempt % 2 == 1:
			side = -side
		var zone := ReliefPlanner.new_zone(rng, calm, &"spring", radius.x, radius.y,
				Vector2(1.0, 1.25), s.butte_lobes)
		zone.ramp_slope = s.ramp_slope_degrees
		zone.height = ReliefPlanner.roll(rng, s.massif_height_min, s.massif_height_max, calm)
		zone.swell = ReliefPlanner.roll(rng, s.butte_swell_min, s.butte_swell_max, calm)
		zone.center = frame[0] + left * side * (ravine.half_at(at) + SPRING_GAP
				+ layout.zone_radius(zone, (-left * side).angle()))
		if not spawn_clear(layout, zone) or not ReliefPlanner.loose_fits(layout, zone):
			continue
		# Una sola rampa, del lado contrario al cañón: la cara que lo mira
		# queda de roca limpia para la caída.
		if not ReliefRamps.place(layout, zone, (left * side).angle(),
				ReliefPlanner.jitters(rng, 1, calm), 1, 1):
			continue
		if not clear_of_road(layout, zone, ROAD_CLEARANCE):
			continue
		layout.zones.append(zone)
		layout.cascade_zone = layout.zones.size() - 1
		if not ReliefWaters.cascade_spot(layout).is_empty():
			return true
		layout.zones.pop_back()
		layout.cascade_zone = -1
	return false
