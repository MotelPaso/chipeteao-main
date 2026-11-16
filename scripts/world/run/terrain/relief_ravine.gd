class_name ReliefRavine
extends RefCounted
## El cañón del relieve: por dónde pasa su eje, en cuántos tramos se parte
## su fondo, dónde van los collados y dónde los puentes. Lo pide
## ReliefPlanner una vez que el macizo está puesto.
##
## Pasa al pie del macizo por el lado contrario a la montaña, a ravine_gap
## de su borde donde más se acerca, y lo abraza un poco. Entre dos puentes
## lleva siempre un collado: sin él, ese tramo de fondo sería un pozo.

## Edita aquí (no hay Inspector); los valores de diseño están en ReliefSettings.
##
## Cuánto se desvía el cañón de quedar justo enfrente de la montaña, en radianes.
const RAVINE_SWAY: float = 0.35
## Metros de fondo parejo que necesita cada tramo del cañón (uno por puente).
const SEGMENT_MIN: float = 22.0
## Mitad del tramo plano de un collado, en metros.
const SADDLE_HALF: float = 5.0
## Cuánto se corre cada puente del medio de su tramo, en fracción del tramo.
const CROSSING_JITTER: float = 0.15


## El cañón: pasa al pie del macizo por el lado contrario a la montaña, a
## ravine_gap de su borde donde más se acerca, y se curva alrededor de él.
static func place(layout: ReliefLayout, rng: RandomNumberGenerator, bearing: float,
		calm: bool) -> bool:
	var s := layout.settings
	var massif := layout.zones[0]
	for attempt in ReliefPlanner.PLACE_ATTEMPTS:
		var half_width := ReliefPlanner.roll(rng, s.ravine_width_min, s.ravine_width_max, calm) * 0.5
		var depth := ReliefPlanner.roll(rng, s.ravine_depth_min, s.ravine_depth_max, calm)
		var length := ReliefPlanner.roll(rng, s.ravine_length_min, s.ravine_length_max, calm)
		var bend := ReliefPlanner.roll(rng, s.ravine_bend_min, s.ravine_bend_max, calm)
		var facing := bearing + PI + (0.0 if calm else rng.randf_range(-RAVINE_SWAY, RAVINE_SWAY))
		var out := Vector2.from_angle(facing)
		var along := Vector2(-out.y, out.x)
		var mid := out * (ReliefPlanner.rim_from_origin(layout, massif, out) + s.ravine_gap + half_width)
		# Bézier con el punto medio en `mid` y los extremos `bend` metros más
		# cerca de la montaña: la abraza.
		var points := _bezier(mid - along * (length * 0.5) - out * bend, mid + out * bend,
				mid + along * (length * 0.5) - out * bend, length)
		if not _ravine_fits(layout, points, half_width):
			continue
		_set_ravine(layout, points, half_width, depth)
		_split_ravine(layout, rng, ReliefPlanner.roll_int(rng, s.bridge_count_min, s.bridge_count_max, calm),
				calm)
		return true
	return false


## Parte el fondo del cañón en `wanted` tramos (menos si no caben), con un
## collado entre cada dos y un puente en cada uno.
static func _split_ravine(layout: ReliefLayout, rng: RandomNumberGenerator, wanted: int,
		calm: bool) -> void:
	var ravine := layout.ravine
	ravine.saddle_half = SADDLE_HALF
	var saddle_span := (SADDLE_HALF + ravine.ramp) * 2.0
	var count := maxi(wanted, 1)
	var deep := 0.0
	while count >= 1:
		deep = (ravine.length - ravine.ramp * 2.0 - saddle_span * float(count - 1)) \
				/ float(count)
		if deep >= SEGMENT_MIN or count == 1:
			break
		count -= 1
	var cursor := ravine.ramp
	for index in count:
		var middle := cursor + deep * 0.5
		if not calm:
			middle += deep * rng.randf_range(-CROSSING_JITTER, CROSSING_JITTER)
		_set_crossing(layout, middle)
		if index < count - 1:
			ravine.saddles.append(cursor + deep + ravine.ramp + SADDLE_HALF)
		cursor += deep + saddle_span


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


## True si el eje entero queda dentro de la arena con su margen y a
## ravine_gap o más del borde del macizo.
static func _ravine_fits(layout: ReliefLayout, points: PackedVector2Array,
		half_width: float) -> bool:
	var s := layout.settings
	var limit := layout.half - s.edge_margin - half_width
	var massif := layout.zones[0]
	for point: Vector2 in points:
		if absf(point.x) > limit or absf(point.y) > limit:
			return false
		if layout.on_plateau(massif, point, -(s.ravine_gap + half_width - 0.5)):
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
	# La caja cubre la vaguada entera: quien pregunta por el cañón desde
	# más lejos no tiene nada que ver con él.
	ravine.bounds = box.grow(half_width + layout.settings.swell_reach)
	layout.ravine = ravine


## Un cruce (un puente) a `along` metros del inicio del cañón. Sin escena de
## puente no hay cruces: las paredes siguen de largo.
static func _set_crossing(layout: ReliefLayout, along: float) -> void:
	if layout.settings.bridge_scene == null:
		return
	var ravine := layout.ravine
	var crossing := ReliefLayout.Crossing.new()
	crossing.s = along
	var frame := layout.ravine_frame(crossing.s)
	crossing.center = frame[0]
	crossing.axis = Vector2(-frame[1].y, frame[1].x)
	crossing.span = ravine.half_width * 2.0
	crossing.width = layout.settings.bridge_width
	var reach := ravine.half_width + ReliefLayout.HEAD_SETBACK
	crossing.head_a = crossing.center + crossing.axis * reach
	crossing.head_b = crossing.center - crossing.axis * reach
	layout.crossings.append(crossing)
