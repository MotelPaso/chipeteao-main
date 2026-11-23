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
## Metros que el final de una pared del cañón se mete dentro del puente,
## para que la roca no deje ver su corte.
const BRIDGE_EMBED: float = 0.4
## Tope del factor de esquina (ver CutPath.miter): una esquina más cerrada
## que 90 grados no aleja las filas más que esto.
const MITER_MAX: float = 1.6
## Metros a lo largo de un muelle, desde su punta en la isla, donde el corte
## de la isla se abre para que el estribo no muestre roca.
const PIER_LAND: float = 4.0


## Llena layout.cuts desde las zonas, las rampas, el cañón y los cruces.
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
		for piece: Dictionary in _open_for_piers(layout, zone_index, path,
				[first_corner, last_corner]):
			var part: ReliefLayout.CutPath = piece["path"]
			_finish(part, piece["corners"])
			layout.cuts.append(part)


## `path` partido donde aterriza un muelle en la isla `zone_index` (sin
## muelles, entero): cada pedazo con sus esquinas reubicadas. Un pedazo de
## menos de dos puntos se descarta.
static func _open_for_piers(layout: ReliefLayout, zone_index: int, path: ReliefLayout.CutPath,
		corners: Array[int]) -> Array[Dictionary]:
	var piers: Array[ReliefLayout.Crossing] = []
	for crossing: ReliefLayout.Crossing in layout.crossings:
		if crossing.island == zone_index:
			piers.append(crossing)
	if piers.is_empty():
		return [{"path": path, "corners": corners}]
	var out: Array[Dictionary] = []
	var part := _empty_like(path)
	var part_corners: Array[int] = []
	for index in path.points.size():
		if _under_pier(piers, path.points[index]):
			if part.points.size() >= 2:
				out.append({"path": part, "corners": part_corners})
			part = _empty_like(path)
			part_corners = []
			continue
		if corners.has(index):
			part_corners.append(part.points.size())
		part.points.append(path.points[index])
		part.upper.append(path.upper[index])
		part.lower.append(path.lower[index])
	if part.points.size() >= 2:
		out.append({"path": part, "corners": part_corners})
	return out


static func _empty_like(path: ReliefLayout.CutPath) -> ReliefLayout.CutPath:
	var part := ReliefLayout.CutPath.new()
	part.zone = path.zone
	return part


## True si `point` cae bajo el estribo de la punta en la isla de un muelle.
static func _under_pier(piers: Array[ReliefLayout.Crossing], point: Vector2) -> bool:
	for pier: ReliefLayout.Crossing in piers:
		var tip := pier.center - pier.axis * (pier.span * 0.5)
		var local := point - tip
		var across := absf(local.dot(Vector2(-pier.axis.y, pier.axis.x)))
		if across <= pier.width * 0.5 - BRIDGE_EMBED and absf(local.dot(pier.axis)) <= PIER_LAND:
			return true
	return false


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


# --- cañón ------------------------------------------------------------------

## Las dos paredes del cañón, partidas en cada cruce y en cada collado (un
## muelle parte solo la pared de su lado). La izquierda se recorre hacia
## delante y la derecha hacia atrás: así el fondo queda a la derecha de las dos.
static func _ravine_cuts(layout: ReliefLayout) -> void:
	var left := _wall_runs(layout, 1)
	var right := _wall_runs(layout, -1)
	# Intercaladas, tramo por tramo: con cruces de pared a pared los dos
	# lados se parten igual y el orden es el de siempre.
	for index in maxi(left.size(), right.size()):
		if index < left.size():
			layout.cuts.append(_ravine_wall(layout, left[index].x, left[index].y, 1.0))
		if index < right.size():
			layout.cuts.append(_ravine_wall(layout, right[index].y, right[index].x, -1.0))


## Los tramos (desde, hasta) del eje donde la pared del lado `side` (+1 = la
## izquierda) tiene roca: todo el cañón menos los cruces de ese lado y los collados.
static func _wall_runs(layout: ReliefLayout, side: int) -> Array[Vector2]:
	var ravine := layout.ravine
	var gaps: Array[Vector2] = []
	for crossing: ReliefLayout.Crossing in layout.crossings:
		if crossing.side != 0 and crossing.side != side:
			continue
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
	var runs: Array[Vector2] = []
	for index in range(0, stops.size(), 2):
		if stops[index + 1] - stops[index] >= ReliefLayout.PATH_STEP:
			runs.append(Vector2(stops[index], stops[index + 1]))
	return runs


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
		path.points.append(frame[0] + left * (layout.ravine.half_at(s) * side))
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
