class_name ReliefRamps
extends RefCounted
## Las rampas de una zona elevada del relieve: dónde caben alrededor de su
## contorno y qué forma tienen. Las pide ReliefPlanner para cada zona que
## coloca (el macizo, los niveles altos, los cerros).
##
## Una rampa sale del contorno hacia afuera y baja hasta el suelo donde la
## zona se apoya. Cabe si su pie y su descanso quedan dentro de la arena,
## fuera del claro del punto de aparición, sobre la meseta del padre cuando
## la zona está apilada, y lejos de las otras zonas, de sus rampas y del
## cañón; y si detrás de su boca queda meseta libre.

## Edita aquí (no hay Inspector); los valores de diseño están en ReliefSettings.
##
## Desvíos del ángulo pedido que se prueban para que una rampa quepa, en radianes.
const RAMP_NUDGES: Array[float] = [0.0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45, 0.6, -0.6]
## Metros que el pie de una rampa guarda con el borde de la arena.
const RAMP_EDGE_MARGIN: float = 14.0
## Metros que una rampa guarda con otra zona, con otra rampa o con el cañón.
const RAMP_GAP: float = 9.0
## Metros que el pie de una rampa de un nivel alto guarda con el borde de la
## meseta donde aterriza.
const RAMP_PARENT_MARGIN: float = 4.0
## Metros de meseta libres detrás de la boca de una rampa: ahí no puede
## empezar el corte de un nivel de arriba.
const RAMP_TOP_CLEAR: float = 6.0
## Radianes libres entre dos rampas de la misma zona.
const RAMP_SPACING: float = 0.3


## Reparte las rampas de `zone` alrededor de su contorno, una cada
## way_every metros (entre `ways_min` y `ways_max`), la primera hacia
## `first_way`. False si no cupieron al menos `ways_min`.
static func place(layout: ReliefLayout, zone: ReliefLayout.Zone, first_way: float,
		jitters: PackedFloat32Array, ways_min: int, ways_max: int) -> bool:
	var perimeter := 0.0
	for reach: float in zone.radii:
		perimeter += reach * TAU / float(ReliefLayout.TABLE)
	var count := clampi(roundi(perimeter / layout.settings.way_every), ways_min, ways_max)
	zone.ramps.clear()
	for index in count:
		var wanted := first_way + TAU * float(index) / float(count)
		if index > 0:
			wanted += jitters[index]
		var ramp := _fit_ramp(layout, zone, wanted)
		if ramp != null:
			zone.ramps.append(ramp)
	zone.ramps.sort_custom(func(a: ReliefLayout.Ramp, b: ReliefLayout.Ramp) -> bool:
		return a.angle < b.angle)
	return zone.ramps.size() >= ways_min


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
	ramp.length = zone.height / tan(deg_to_rad(zone.ramp_slope))
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


## True si `ramp` cabe. Su pie y su descanso: dentro de la arena, fuera del
## claro del punto de aparición, sobre la meseta del padre si la zona está
## apilada, y lejos de las zonas que no son de su familia, de sus rampas y
## del cañón. Su boca: con meseta libre detrás, sin el corte de un nivel de
## arriba ni el pie de una de sus rampas.
static func _ramp_fits(layout: ReliefLayout, zone: ReliefLayout.Zone,
		ramp: ReliefLayout.Ramp) -> bool:
	var s := layout.settings
	var limit := layout.half - RAMP_EDGE_MARGIN
	var probes := PackedVector2Array()
	for along: float in [ramp.length * 0.5, ramp.length + ReliefLayout.RAMP_LANDING]:
		for side: float in [-1.0, 1.0]:
			probes.append(ramp.origin + ramp.dir * along + ramp.perp * (ramp.half_width * side))
	var mouth := PackedVector2Array()
	for side: float in [-1.0, 0.0, 1.0]:
		mouth.append(ramp.origin + ramp.dir * (ramp.back - RAMP_TOP_CLEAR)
				+ ramp.perp * (ramp.half_width * side))
	var own := layout.zones.find(zone)
	for probe: Vector2 in probes:
		if absf(probe.x) > limit or absf(probe.y) > limit:
			return false
		if probe.length() < s.spawn_clearance:
			return false
		if zone.parent >= 0 and not layout.on_plateau(layout.zones[zone.parent], probe,
				RAMP_PARENT_MARGIN):
			return false
		if zone.parent < 0 and near_ravine(layout, probe, RAMP_GAP):
			return false
	for index in layout.zones.size():
		var other := layout.zones[index]
		if other == zone or _is_ancestor(layout, zone, index):
			continue
		# Una zona de arriba (hija, nieta): lo que importa es la boca.
		var above := own >= 0 and _is_ancestor(layout, other, own)
		for point: Vector2 in (mouth if above else probes):
			if layout.on_plateau(other, point, -RAMP_GAP):
				return false
			for other_ramp: ReliefLayout.Ramp in other.ramps:
				if on_ramp(other_ramp, point, RAMP_GAP):
					return false
	for other: ReliefLayout.Ramp in zone.ramps:
		if _arc_gap(ramp, other) < RAMP_SPACING:
			return false
	return true


## True si la zona de índice `index` es un ancestro de `zone`.
static func _is_ancestor(layout: ReliefLayout, zone: ReliefLayout.Zone, index: int) -> bool:
	var up := zone.parent
	while up >= 0:
		if up == index:
			return true
		up = layout.zones[up].parent
	return false


## Radianes de contorno libres entre las bocas de dos rampas de una zona.
static func _arc_gap(a: ReliefLayout.Ramp, b: ReliefLayout.Ramp) -> float:
	var apart := absf(angle_difference(a.angle, b.angle))
	return apart - absf(angle_difference(a.corner_lo, a.corner_hi)) * 0.5 \
			- absf(angle_difference(b.corner_lo, b.corner_hi)) * 0.5


## True si `point` queda a menos de `gap` metros del pasillo del cañón.
static func near_ravine(layout: ReliefLayout, point: Vector2, gap: float) -> bool:
	if layout.ravine == null:
		return false
	var clear := layout.ravine.half_width + gap
	for axis: Vector2 in layout.ravine.points:
		if point.distance_to(axis) < clear:
			return true
	return false


## True si `point` cae sobre `ramp` (con su descanso al pie) o a menos de
## `gap` metros de ella.
static func on_ramp(ramp: ReliefLayout.Ramp, point: Vector2, gap: float) -> bool:
	var local := point - ramp.origin
	var u := local.dot(ramp.dir)
	if u < ramp.back - gap or u > ramp.length + ReliefLayout.RAMP_LANDING + gap:
		return false
	return absf(local.dot(ramp.perp)) <= ramp.half_width + gap
