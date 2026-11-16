class_name ReliefPlanner
extends RefCounted
## Sortea el trazado del relieve de una etapa (ReliefLayout) desde la
## semilla de partida: primero el barranco, después las zonas elevadas con
## sus rampas, al final las lomas sueltas. Cada pieza se sortea por rechazo
## hasta que cabe: lejos del spawn, del borde de la arena y de las demás.
##
## RNG PROPIO, sembrado con la semilla de partida: no saca ni un número del
## flujo de la partida, así que el relieve es función de la semilla y no
## mueve ningún otro sorteo. Las líneas de corte las arma ReliefCuts.

## Edita aquí (no hay Inspector); los valores de diseño están en ReliefSettings.
##
## Sal que separa este RNG de los otros que se siembran con la misma semilla.
const SEED_SALT: int = 0x52454C49
## Trazados completos que se intentan antes de usar el de reserva.
const PLAN_ATTEMPTS: int = 40
## Intentos por pieza (barranco, zona) dentro de un trazado.
const PLACE_ATTEMPTS: int = 40
## Desvíos del ángulo pedido que se prueban para que una rampa quepa, en radianes.
const RAMP_NUDGES: Array[float] = [0.0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45, 0.6, -0.6]
## Metros que el pie de una rampa guarda con el borde de la arena.
const RAMP_EDGE_MARGIN: float = 14.0
## Metros que una rampa guarda con otra zona o con el barranco.
const RAMP_GAP: float = 9.0
## Radianes libres entre dos rampas de la misma zona.
const RAMP_SPACING: float = 0.3
## Cuánto se desvía el barranco de la tangente al círculo del spawn, en radianes.
const RAVINE_SKEW: float = 0.6
## Entre qué fracciones del largo del barranco cae el puente.
const CROSSING_FROM: float = 0.42
const CROSSING_TO: float = 0.58
## Metros sin lomas sueltas alrededor del spawn.
const HILL_SPAWN_CLEAR: float = 26.0


## El trazado de la etapa para `seed_value`, con sus líneas de corte ya armadas.
static func plan(settings: ReliefSettings, seed_value: int, half: float) -> ReliefLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ SEED_SALT
	var layout: ReliefLayout = null
	for attempt in PLAN_ATTEMPTS:
		layout = ReliefLayout.new(settings, half)
		if _try_plan(layout, rng):
			break
		layout = null
	if layout == null:
		layout = _fallback(settings, half, rng)
	ReliefCuts.build(layout)
	return layout


## Un trazado entero; false si alguna pieza obligatoria no cupo.
static func _try_plan(layout: ReliefLayout, rng: RandomNumberGenerator) -> bool:
	if not _place_ravine(layout, rng):
		return false
	var wanted := rng.randi_range(layout.settings.raised_min, layout.settings.raised_max)
	for index in wanted:
		if _place_zone(layout, rng, index == 0):
			continue
		if index < layout.settings.raised_min:
			return false
		break
	_place_hills(layout, rng)
	return true


## Trazado fijo de reserva, girado por la semilla: un barranco recto y dos
## zonas ovaladas en un triángulo alrededor del spawn. Solo sale si el
## sorteo no encontró lugar en PLAN_ATTEMPTS intentos.
static func _fallback(settings: ReliefSettings, half: float,
		rng: RandomNumberGenerator) -> ReliefLayout:
	var layout := ReliefLayout.new(settings, half)
	layout.fallback = true
	var turn := float(rng.randi_range(0, 3)) * PI * 0.5
	var ring := half * 0.52
	var along := Vector2.from_angle(turn + PI * 0.5)
	var mid := Vector2.from_angle(turn) * ring
	var length := settings.ravine_length_min
	_set_ravine(layout, _bezier(mid - along * length * 0.5, mid, mid + along * length * 0.5, length),
			settings.ravine_width_min * 0.5, settings.ravine_depth_min)
	_set_crossing(layout, 0.5)
	for index in 2:
		var zone := ReliefLayout.Zone.new()
		zone.top = index == 0
		zone.height = settings.zone_top_height if zone.top else settings.zone_height_min
		zone.swell = settings.zone_top_swell_min if zone.top else settings.zone_swell_min
		_shape_zone(zone, settings.zone_radius_min, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		zone.center = Vector2.from_angle(turn + TAU * float(index + 1) / 3.0) * ring
		for way in 2:
			var ramp := _fit_ramp(layout, zone, (-zone.center).angle() + PI * float(way))
			if ramp != null:
				zone.ramps.append(ramp)
		layout.zones.append(zone)
	return layout


# --- barranco ------------------------------------------------------------------

static func _place_ravine(layout: ReliefLayout, rng: RandomNumberGenerator) -> bool:
	var s := layout.settings
	for attempt in PLACE_ATTEMPTS:
		var half_width := rng.randf_range(s.ravine_width_min, s.ravine_width_max) * 0.5
		var length := rng.randf_range(s.ravine_length_min, s.ravine_length_max)
		var depth := rng.randf_range(s.ravine_depth_min, s.ravine_depth_max)
		var bearing := rng.randf() * TAU
		var nearest := s.spawn_clearance + half_width + 10.0
		var farthest := maxf(layout.half - s.edge_margin - half_width - 12.0, nearest)
		var mid := Vector2.from_angle(bearing) * rng.randf_range(nearest, farthest)
		var along := Vector2.from_angle(bearing + PI * 0.5
				+ rng.randf_range(-RAVINE_SKEW, RAVINE_SKEW))
		var bend := rng.randf_range(-s.ravine_bend_max, s.ravine_bend_max)
		var crossing_at := rng.randf_range(CROSSING_FROM, CROSSING_TO)
		var control := mid + Vector2(-along.y, along.x) * (bend * 2.0)
		var points := _bezier(mid - along * (length * 0.5), control,
				mid + along * (length * 0.5), length)
		if not _ravine_fits(layout, points, half_width):
			continue
		_set_ravine(layout, points, half_width, depth)
		_set_crossing(layout, crossing_at)
		return true
	return false


## El eje como tramos rectos de unos CENTER_STEP metros sobre una Bézier
## cuadrática.
static func _bezier(from: Vector2, control: Vector2, to: Vector2,
		length: float) -> PackedVector2Array:
	var pieces := maxi(ceili(length / ReliefLayout.CENTER_STEP), 4)
	var points := PackedVector2Array()
	for index in pieces + 1:
		var t := float(index) / float(pieces)
		points.append(from.lerp(control, t).lerp(control.lerp(to, t), t))
	return points


## True si el eje entero queda dentro de la arena con su margen y lejos del spawn.
static func _ravine_fits(layout: ReliefLayout, points: PackedVector2Array,
		half_width: float) -> bool:
	var limit := layout.half - layout.settings.edge_margin - half_width
	var clear := layout.settings.spawn_clearance + half_width
	for point: Vector2 in points:
		if absf(point.x) > limit or absf(point.y) > limit or point.length() < clear:
			return false
	return true


static func _set_ravine(layout: ReliefLayout, points: PackedVector2Array,
		half_width: float, depth: float) -> void:
	var ravine := ReliefLayout.Ravine.new()
	ravine.points = points
	ravine.half_width = half_width
	ravine.depth = depth
	ravine.ramp = depth / tan(deg_to_rad(layout.settings.ravine_ramp_slope_degrees))
	var walked := 0.0
	var box := Rect2(points[0], Vector2.ZERO)
	for index in points.size():
		if index > 0:
			walked += points[index].distance_to(points[index - 1])
		ravine.along.append(walked)
		box = box.expand(points[index])
	ravine.length = walked
	# La caja cubre la vaguada entera: quien pregunta por el barranco desde
	# más lejos no tiene nada que ver con él.
	ravine.bounds = box.grow(half_width + layout.settings.swell_reach)
	layout.ravine = ravine


## El cruce del puente a `fraction` del largo del barranco. Sin escena de
## puente no hay cruce: las paredes siguen de largo.
static func _set_crossing(layout: ReliefLayout, fraction: float) -> void:
	if layout.settings.bridge_scene == null:
		return
	var ravine := layout.ravine
	var crossing := ReliefLayout.Crossing.new()
	crossing.s = ravine.length * fraction
	var frame := layout.ravine_frame(crossing.s)
	crossing.center = frame[0]
	crossing.axis = Vector2(-frame[1].y, frame[1].x)
	crossing.span = ravine.half_width * 2.0
	crossing.width = layout.settings.bridge_width
	var reach := ravine.half_width + ReliefLayout.HEAD_SETBACK
	crossing.head_a = crossing.center + crossing.axis * reach
	crossing.head_b = crossing.center - crossing.axis * reach
	layout.crossings.append(crossing)


# --- zonas elevadas --------------------------------------------------------------

static func _place_zone(layout: ReliefLayout, rng: RandomNumberGenerator, top: bool) -> bool:
	var s := layout.settings
	for attempt in PLACE_ATTEMPTS:
		var zone := ReliefLayout.Zone.new()
		zone.top = top
		zone.height = s.zone_top_height if top \
				else rng.randf_range(s.zone_height_min, s.zone_height_max)
		zone.swell = rng.randf_range(s.zone_top_swell_min, s.zone_top_swell_max) if top \
				else rng.randf_range(s.zone_swell_min, s.zone_swell_max)
		_shape_zone(zone, rng.randf_range(s.zone_radius_min, s.zone_radius_max),
				rng.randf_range(1.0, s.zone_stretch_max), rng.randf() * TAU,
				rng.randf_range(0.0, s.zone_lobes), rng.randf() * TAU,
				rng.randf_range(s.zone_lobes * 0.3, s.zone_lobes), rng.randf() * TAU)
		var bearing := rng.randf() * TAU
		var away := rng.randf_range(s.spawn_clearance + zone.r_max,
				maxf(layout.half - s.edge_margin - zone.r_max, s.spawn_clearance + zone.r_max))
		if layout.zones.is_empty():
			# La primera se ve desde el spawn: su borde más cercano queda a
			# view_distance del origen.
			away = layout.zone_radius(zone, bearing + PI) \
					+ rng.randf_range(s.view_distance_min, s.view_distance_max)
		zone.center = Vector2.from_angle(bearing) * away
		var first_way := rng.randf() * TAU
		if layout.zones.is_empty():
			first_way = (-zone.center).angle() + rng.randf_range(-0.4, 0.4)
		var jitters := PackedFloat32Array()
		for way in s.ways_max:
			jitters.append(rng.randf_range(-RAMP_SPACING, RAMP_SPACING))
		if not _zone_fits(layout, zone):
			continue
		if not _place_ramps(layout, zone, first_way, jitters):
			continue
		layout.zones.append(zone)
		return true
	return false


## Llena el contorno polar de `zone`: un óvalo de radio medio `radius`,
## alargado `stretch` veces y girado `turn`, con dos ondas (de 2 y de 3
## lóbulos) encima.
static func _shape_zone(zone: ReliefLayout.Zone, radius: float, stretch: float, turn: float,
		wave2: float, phase2: float, wave3: float, phase3: float) -> void:
	var long_axis := sqrt(stretch)
	var short_axis := 1.0 / long_axis
	zone.radii.resize(ReliefLayout.TABLE)
	zone.oblique.resize(ReliefLayout.TABLE)
	zone.r_min = INF
	zone.r_max = 0.0
	for index in ReliefLayout.TABLE:
		var angle := TAU * float(index) / float(ReliefLayout.TABLE)
		var across := short_axis * cos(angle - turn)
		var down := long_axis * sin(angle - turn)
		var oval := 1.0 / sqrt(across * across + down * down)
		var reach := radius * oval * (1.0 + wave2 * sin(2.0 * angle + phase2)
				+ wave3 * sin(3.0 * angle + phase3))
		zone.radii[index] = reach
		zone.r_min = minf(zone.r_min, reach)
		zone.r_max = maxf(zone.r_max, reach)
	var step := TAU / float(ReliefLayout.TABLE)
	for index in ReliefLayout.TABLE:
		var ahead := zone.radii[(index + 1) % ReliefLayout.TABLE]
		var behind := zone.radii[(index + ReliefLayout.TABLE - 1) % ReliefLayout.TABLE]
		var slope := (ahead - behind) / (2.0 * step) / zone.radii[index]
		zone.oblique[index] = sqrt(1.0 + slope * slope)


## True si `zone` cabe: dentro de la arena con su margen, con el spawn libre
## y a feature_gap de las otras zonas y del barranco.
static func _zone_fits(layout: ReliefLayout, zone: ReliefLayout.Zone) -> bool:
	var s := layout.settings
	var limit := layout.half - s.edge_margin - zone.r_max
	if absf(zone.center.x) > limit or absf(zone.center.y) > limit:
		return false
	for index in range(0, ReliefLayout.TABLE, 6):
		var angle := TAU * float(index) / float(ReliefLayout.TABLE)
		var rim := zone.center + Vector2.from_angle(angle) * zone.radii[index]
		if rim.length() < s.spawn_clearance:
			return false
	for other: ReliefLayout.Zone in layout.zones:
		if zone.center.distance_to(other.center) < zone.r_max + other.r_max + s.feature_gap:
			return false
	if layout.ravine != null:
		var clear := zone.r_max + layout.ravine.half_width + s.feature_gap
		for point: Vector2 in layout.ravine.points:
			if zone.center.distance_to(point) < clear:
				return false
	return true


## Reparte las rampas de `zone` alrededor de su contorno, una cada
## way_every metros, la primera hacia `first_way`. False si no cupieron
## al menos ways_min.
static func _place_ramps(layout: ReliefLayout, zone: ReliefLayout.Zone, first_way: float,
		jitters: PackedFloat32Array) -> bool:
	var s := layout.settings
	var perimeter := 0.0
	for reach: float in zone.radii:
		perimeter += reach * TAU / float(ReliefLayout.TABLE)
	var count := clampi(roundi(perimeter / s.way_every), s.ways_min, s.ways_max)
	for index in count:
		var wanted := first_way + TAU * float(index) / float(count)
		if index > 0:
			wanted += jitters[index]
		var ramp := _fit_ramp(layout, zone, wanted)
		if ramp != null:
			zone.ramps.append(ramp)
	zone.ramps.sort_custom(func(a: ReliefLayout.Ramp, b: ReliefLayout.Ramp) -> bool:
		return a.angle < b.angle)
	return zone.ramps.size() >= s.ways_min


## Una rampa de `zone` cerca del ángulo `wanted` que quepa, o null.
static func _fit_ramp(layout: ReliefLayout, zone: ReliefLayout.Zone,
		wanted: float) -> ReliefLayout.Ramp:
	for nudge: float in RAMP_NUDGES:
		var ramp := _make_ramp(layout, zone, wanted + nudge)
		if ramp != null and _ramp_fits(layout, zone, ramp):
			return ramp
	return null


## La rampa de `zone` cuyo eje sale por `angle`: recorre el contorno hacia
## los dos lados hasta el ancho de la rampa para hallar sus esquinas y dónde
## empieza a bajar. Null si la zona es más angosta que la rampa ahí.
static func _make_ramp(layout: ReliefLayout, zone: ReliefLayout.Zone,
		angle: float) -> ReliefLayout.Ramp:
	var ramp := ReliefLayout.Ramp.new()
	ramp.angle = fposmod(angle, TAU)
	ramp.dir = Vector2.from_angle(angle)
	ramp.perp = Vector2(-ramp.dir.y, ramp.dir.x)
	ramp.half_width = layout.settings.ramp_width * 0.5
	ramp.length = zone.height / tan(deg_to_rad(layout.settings.ramp_slope_degrees))
	var reach := Vector2(-INF, INF)
	var corners := PackedFloat32Array()
	for side: float in [1.0, -1.0]:
		var corner := _scan_corner(layout, zone, ramp, side, reach)
		if is_nan(corner.x):
			return null
		corners.append(corner.x)
		reach = Vector2(corner.y, corner.z)
	ramp.corner_hi = corners[0]
	ramp.corner_lo = corners[1]
	ramp.origin = zone.center + ramp.dir * reach.x
	# Entra en la zona hasta pasado el escalón escondido, para que la boca
	# de la rampa quede abierta de lado a lado.
	ramp.back = (reach.y - reach.x) - ReliefLayout.LEDGE_INSET - 1.5
	return ramp


## Recorre el contorno desde el eje de `ramp` hacia el lado `side` (+1 o -1)
## hasta que se aleja half_width del eje. Devuelve (ángulo de la esquina,
## mayor u, menor u) con los u del arco acumulados sobre `reach`, o NAN si
## el contorno nunca llega al ancho.
static func _scan_corner(layout: ReliefLayout, zone: ReliefLayout.Zone,
		ramp: ReliefLayout.Ramp, side: float, reach: Vector2) -> Vector3:
	var step := TAU / float(ReliefLayout.TABLE) * 0.5
	var top := reach.x
	var low := reach.y
	var previous_angle := ramp.angle
	var previous_v := 0.0
	for index in ReliefLayout.TABLE:
		var angle := ramp.angle + side * step * float(index)
		var rim := Vector2.from_angle(angle) * layout.zone_radius(zone, angle)
		var v := rim.dot(ramp.perp) * side
		if v >= ramp.half_width:
			var t := (ramp.half_width - previous_v) / maxf(v - previous_v, 0.0001)
			var corner := lerpf(previous_angle, angle, t)
			var corner_u := (Vector2.from_angle(corner) * layout.zone_radius(zone, corner)) \
					.dot(ramp.dir)
			return Vector3(corner, maxf(top, corner_u), minf(low, corner_u))
		var u := rim.dot(ramp.dir)
		if u < 0.0:
			break
		top = maxf(top, u)
		low = minf(low, u)
		previous_angle = angle
		previous_v = v
	return Vector3(NAN, 0.0, 0.0)


## True si `ramp` cabe: su pie dentro de la arena, sin pisar otra rampa de
## su zona, otra zona ni el barranco.
static func _ramp_fits(layout: ReliefLayout, zone: ReliefLayout.Zone,
		ramp: ReliefLayout.Ramp) -> bool:
	var limit := layout.half - RAMP_EDGE_MARGIN
	var probes := PackedVector2Array()
	for along: float in [ramp.length * 0.5, ramp.length + ReliefLayout.RAMP_LANDING]:
		for side: float in [-1.0, 1.0]:
			probes.append(ramp.origin + ramp.dir * along + ramp.perp * (ramp.half_width * side))
	for probe: Vector2 in probes:
		if absf(probe.x) > limit or absf(probe.y) > limit:
			return false
		for other: ReliefLayout.Zone in layout.zones:
			if probe.distance_to(other.center) < other.r_max + RAMP_GAP:
				return false
		if layout.ravine != null:
			for point: Vector2 in layout.ravine.points:
				if probe.distance_to(point) < layout.ravine.half_width + RAMP_GAP:
					return false
	for other: ReliefLayout.Ramp in zone.ramps:
		if _arc_gap(ramp, other) < RAMP_SPACING:
			return false
	return true


## Radianes de contorno libres entre las bocas de dos rampas de una zona.
static func _arc_gap(a: ReliefLayout.Ramp, b: ReliefLayout.Ramp) -> float:
	var apart := absf(angle_difference(a.angle, b.angle))
	return apart - absf(angle_difference(a.corner_lo, a.corner_hi)) * 0.5 \
			- absf(angle_difference(b.corner_lo, b.corner_hi)) * 0.5


# --- lomas sueltas ---------------------------------------------------------------

static func _place_hills(layout: ReliefLayout, rng: RandomNumberGenerator) -> void:
	var s := layout.settings
	var limit := layout.half - s.edge_margin
	for index in s.hill_count:
		var hill := ReliefLayout.Hill.new()
		hill.radius = rng.randf_range(s.hill_radius_min, s.hill_radius_max)
		hill.height = rng.randf_range(s.hill_height_min, s.hill_height_max)
		hill.center = Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		if hill.center.length() < HILL_SPAWN_CLEAR + hill.radius * 0.5:
			continue
		layout.hills.append(hill)
