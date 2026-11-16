class_name ReliefCuts
extends RefCounted
## Arma las líneas de corte (ReliefLayout.CutPath) de un trazado: por dónde
## pasa cada acantilado y cuánto mide en cada punto. Las leen CliffWall, que
## levanta la roca sobre ellas, y las consultas de colocación.
##
## Una zona elevada con N rampas da N líneas: cada una sube por el costado
## de una rampa (de 0 a la altura de la zona), sigue el contorno hasta la
## rampa siguiente y baja por su costado. Los dos lados de una zona apilada
## llevan además `zone.floor`, lo que ya sube el suelo donde se apoya. El
## cañón da sus dos paredes, partidas donde las cruza un puente y donde un
## collado las interrumpe; cada pared nace y muere en 0 en una rampa.
##
## Sentido: al recorrer una línea, el lado alto queda a la izquierda y el
## bajo a la derecha. Todas las normales apuntan al lado bajo.

## Edita aquí (no hay Inspector).
##
## Metros que el final de una pared del barranco se mete dentro del puente,
## para que la roca no deje ver su corte.
const BRIDGE_EMBED: float = 0.4
## Tope del factor de esquina (ver CutPath.miter): una esquina más cerrada
## que 90 grados no aleja las filas más que esto.
const MITER_MAX: float = 1.6


## Llena layout.cuts desde las zonas, las rampas, el barranco y los cruces.
static func build(layout: ReliefLayout) -> void:
	layout.cuts.clear()
	for index in layout.zones.size():
		_zone_cuts(layout, index)
	if layout.ravine != null:
		_ravine_cuts(layout)


# --- zonas elevadas --------------------------------------------------------------

static func _zone_cuts(layout: ReliefLayout, zone_index: int) -> void:
	var zone := layout.zones[zone_index]
	var count := zone.ramps.size()
	for index in count:
		var ramp := zone.ramps[index]
		var next := zone.ramps[(index + 1) % count]
		var path := ReliefLayout.CutPath.new()
		path.zone = zone_index
		_ramp_side(layout, zone, ramp, 1.0, path)
		var first_corner := path.points.size()
		_arc(layout, zone, ramp.corner_hi, next.corner_lo, path)
		var last_corner := path.points.size() - 1
		_ramp_side(layout, zone, next, -1.0, path)
		_finish(path, [first_corner, last_corner])
		layout.cuts.append(path)


## El costado `side` (+1 o -1) de `ramp`, sin su esquina. El costado +1 se
## recorre del pie hacia la zona y el -1 de la zona hacia el pie, que es lo
## que deja el lado alto (la rampa) a la izquierda en los dos.
static func _ramp_side(layout: ReliefLayout, zone: ReliefLayout.Zone, ramp: ReliefLayout.Ramp,
		side: float, path: ReliefLayout.CutPath) -> void:
	var corner_angle := ramp.corner_hi if side > 0.0 else ramp.corner_lo
	var corner := zone.center + Vector2.from_angle(corner_angle) \
			* layout.zone_radius(zone, corner_angle)
	var from_u := (corner - ramp.origin).dot(ramp.dir) + ReliefLayout.CORNER_CLEAR
	var pieces := maxi(ceili((ramp.length - from_u) / ReliefLayout.PATH_STEP), 1)
	for step in pieces + 1:
		# El +1 baja hacia la esquina; el -1 sale de ella.
		var k := pieces - step if side > 0.0 else step
		var u := lerpf(from_u, ramp.length, float(k) / float(pieces))
		path.points.append(ramp.origin + ramp.dir * u + ramp.perp * (ramp.half_width * side))
		path.upper.append(zone.floor + zone.height * clampf(1.0 - u / ramp.length, 0.0, 1.0))
		path.lower.append(zone.floor)


## El contorno de `zone` entre dos esquinas de rampa, con las dos esquinas.
static func _arc(layout: ReliefLayout, zone: ReliefLayout.Zone, from_angle: float,
		to_angle: float, path: ReliefLayout.CutPath) -> void:
	var span := fposmod(to_angle - from_angle, TAU)
	var angles := PackedFloat32Array([from_angle])
	var start := from_angle + ReliefLayout.CORNER_CLEAR / layout.zone_radius(zone, from_angle)
	var finish := from_angle + span \
			- ReliefLayout.CORNER_CLEAR / layout.zone_radius(zone, to_angle)
	if finish > start:
		var mean_radius := (zone.r_min + zone.r_max) * 0.5
		var pieces := maxi(ceili((finish - start) * mean_radius / ReliefLayout.PATH_STEP), 1)
		for step in pieces + 1:
			angles.append(lerpf(start, finish, float(step) / float(pieces)))
	angles.append(from_angle + span)
	for angle: float in angles:
		path.points.append(zone.center + Vector2.from_angle(angle)
				* layout.zone_radius(zone, angle))
		path.upper.append(zone.floor + zone.height)
		path.lower.append(zone.floor)


# --- barranco ------------------------------------------------------------------

## Las dos paredes del cañón, partidas en cada cruce y en cada collado. La
## izquierda se recorre hacia delante y la derecha hacia atrás: así el fondo
## queda a la derecha de las dos.
static func _ravine_cuts(layout: ReliefLayout) -> void:
	var ravine := layout.ravine
	# Tramos del eje sin pared: (desde, hasta).
	var gaps: Array[Vector2] = []
	for crossing: ReliefLayout.Crossing in layout.crossings:
		var gap := crossing.width * 0.5 - BRIDGE_EMBED
		gaps.append(Vector2(crossing.s - gap, crossing.s + gap))
	for saddle: float in ravine.saddles:
		gaps.append(Vector2(saddle - ravine.saddle_half, saddle + ravine.saddle_half))
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x)
	var stops := PackedFloat32Array([0.0])
	for gap: Vector2 in gaps:
		stops.append(gap.x)
		stops.append(gap.y)
	stops.append(ravine.length)
	for index in range(0, stops.size(), 2):
		var from_s := stops[index]
		var to_s := stops[index + 1]
		if to_s - from_s < ReliefLayout.PATH_STEP:
			continue
		layout.cuts.append(_ravine_wall(layout, from_s, to_s, 1.0))
		layout.cuts.append(_ravine_wall(layout, to_s, from_s, -1.0))


## La pared del lado `side` (+1 = izquierda del eje) entre dos posiciones
## del eje, recorrida de `from_s` a `to_s`.
static func _ravine_wall(layout: ReliefLayout, from_s: float, to_s: float,
		side: float) -> ReliefLayout.CutPath:
	var path := ReliefLayout.CutPath.new()
	var pieces := maxi(ceili(absf(to_s - from_s) / ReliefLayout.PATH_STEP), 2)
	for step in pieces + 1:
		var s := lerpf(from_s, to_s, float(step) / float(pieces))
		var frame := layout.ravine_frame(s)
		var left := Vector2(-frame[1].y, frame[1].x)
		path.points.append(frame[0] + left * (layout.ravine.half_width * side))
		path.upper.append(0.0)
		path.lower.append(-layout.ravine_drop(s))
	_finish(path, [])
	return path


# --- normales ------------------------------------------------------------------

## Calcula las normales (hacia el lado bajo), el factor de esquina y la
## altura de `path`. `corners` son los índices donde la línea dobla en seco.
static func _finish(path: ReliefLayout.CutPath, corners: Array[int]) -> void:
	var last := path.points.size() - 1
	for index in path.points.size():
		var point := path.points[index]
		var before := (point - path.points[index - 1]).normalized() if index > 0 \
				else Vector2.ZERO
		var after := (path.points[index + 1] - point).normalized() if index < last \
				else Vector2.ZERO
		if before == Vector2.ZERO:
			before = after
		if after == Vector2.ZERO:
			after = before
		var normal := _right(before + after)
		var scale := 1.0
		if corners.has(index):
			normal = (_right(before) + _right(after)).normalized()
			scale = minf(1.0 / maxf(normal.dot(_right(before)), 0.01), MITER_MAX)
		path.normals.append(normal)
		path.miter.append(scale)
		path.height = maxf(path.height, path.upper[index] - path.lower[index])


## `direction` girada hacia la derecha de quien avanza por ella, unitaria.
static func _right(direction: Vector2) -> Vector2:
	return Vector2(direction.y, -direction.x).normalized()
