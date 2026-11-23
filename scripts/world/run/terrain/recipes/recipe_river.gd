class_name RecipeRiver
extends RefCounted
## La receta EL GRAN RÍO (ver ReliefRecipes): un río que cruza el mapa de
## punta a punta por un cañón, con varios puentes y un vado entre cada dos, y
## el equipo en el llano de una orilla. Puede nacer en la cascada de una
## meseta-manantial río arriba (la pieza opcional "springhead", ReliefWaters
## la hace caer). El camino antiguo va del punto de aparición al puente más
## cercano y sigue del otro lado. Cerros en las dos orillas.

## Edita aquí (no hay Inspector); los valores de diseño están en
## ReliefSettings (grupo «Receta: el gran río»).
##
## Cuánto se achica el largo pedido mientras el río no quepa, y cuántas veces.
const SHRINK: float = 0.93
const SHRINK_STEPS: int = 7
## Cuánto se aparta el río de quedar perpendicular al punto de aparición, en radianes.
const SWAY: float = 0.35
## Metros que guarda el río, con su ancho, con el punto de aparición.
const SPAWN_GAP: float = 6.0
## La meseta-manantial: metros río arriba, pasada la rampa de la punta, hasta
## su lugar junto al cañón (mínimo, máximo).
const SPRING_FROM := Vector2(22.0, 46.0)


## El trazado del Gran Río; false si el río o los cerros no cupieron.
static func try_plan(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var s := layout.settings
	if not _place_river(layout, rng, calm):
		return false
	if bool(layout.options.get("road", true)):
		RecipeKit.bridge_road(layout)
	if bool(layout.options.get("springhead", false)):
		# Río arriba: la punta más lejos del punto de aparición.
		var ravine := layout.ravine
		RecipeKit.place_springhead(layout, rng, calm, ravine.points[0].length()
				>= ravine.points[ravine.points.size() - 1].length(), SPRING_FROM,
				Vector2(s.springhead_radius_min, s.springhead_radius_max))
	if not RecipeKit.add_buttes(layout, rng, calm, s.butte_count_min, s.butte_count_max):
		return false
	ReliefPlanner.place_hills(layout, rng)
	return true


## El río: una Bézier cúbica que pasa a river_gap del punto de aparición,
## de lado a lado del mapa, partida en tramos con un puente cada uno.
static func _place_river(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var s := layout.settings
	for attempt in ReliefPlanner.PLACE_ATTEMPTS:
		var half_width := ReliefPlanner.roll(rng, s.ravine_width_min, s.ravine_width_max, calm) * 0.5
		var depth := ReliefPlanner.roll(rng, s.ravine_depth_min, s.ravine_depth_max, calm)
		var facing := PI * 0.25 + PI * 0.5 * float(rng.randi_range(0, 3)) if calm \
				else rng.randf() * TAU
		var out := Vector2.from_angle(facing)
		var along := Vector2(-out.y, out.x).rotated(0.0 if calm else rng.randf_range(-SWAY, SWAY))
		var middle := out * ReliefPlanner.roll(rng, s.river_gap_min, s.river_gap_max, calm)
		var bends := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		if not calm:
			bends = PackedFloat32Array([rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
					rng.randf_range(-0.3, 1.0), rng.randf_range(-0.3, 1.0)])
		var wanted := ReliefPlanner.roll(rng, s.river_length_min, s.river_length_max, calm)
		for step in SHRINK_STEPS:
			var length := wanted * pow(SHRINK, float(step))
			var swing := out * s.river_meander
			var points := ReliefRavine.bezier3(
					middle - along * (length * 0.5) + swing * bends[2],
					middle - along * (length / 6.0) + swing * bends[0],
					middle + along * (length / 6.0) + swing * bends[1],
					middle + along * (length * 0.5) + swing * bends[3], length)
			if not _fits(layout, points, half_width):
				continue
			ReliefRavine.set_axis(layout, points, half_width, depth)
			ReliefRavine.split(layout, rng,
					ReliefPlanner.roll_int(rng, s.river_bridges_min, s.river_bridges_max, calm), calm)
			return true
	return false


## True si el eje entero queda dentro de la arena con su margen y lejos del
## claro del punto de aparición.
static func _fits(layout: ReliefLayout, points: PackedVector2Array, half_width: float) -> bool:
	var s := layout.settings
	var limit := layout.half - s.edge_margin - half_width
	for point: Vector2 in points:
		if absf(point.x) > limit or absf(point.y) > limit:
			return false
		if point.length() - half_width < s.spawn_clearance + SPAWN_GAP:
			return false
	return true
