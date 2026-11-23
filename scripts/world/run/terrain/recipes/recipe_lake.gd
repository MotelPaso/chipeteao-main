class_name RecipeLake
extends RefCounted
## La receta EL LAGO DE LA ISLA (ver ReliefRecipes): un lago hundido frente
## al punto de aparición, alimentado por un brazo de río que entra por una
## punta y sale por la otra, con una ISLA en el medio que lleva el Árbol
## Hueco. Un muelle de piedra (un puente, con sus escaleras al agua) va de la
## orilla del lado del equipo a la isla, y la isla baja al fondo del lago por sus
## rampas. El lago es un cañón que se ensancha (ReliefLayout.Ravine.half_at);
## la isla, una zona que se apoya en su fondo y llega al nivel del llano. La
## pieza opcional "falls" pone una meseta-manantial junto al brazo de río
## arriba: la cascada cae al brazo y el río baja al lago.

## Edita aquí (no hay Inspector); los valores de diseño están en
## ReliefSettings (grupo «Receta: el lago de la isla»).
##
## Metros que tarda el cañón en pasar del ancho del brazo al del lago, desde
## cada punta del lago: la orilla dobla de a poco y la roca no se acuesta.
const FLARE: float = 34.0
## Cuánto se curva el eje del lago, en metros (como mucho, a cada lado).
const BEND: float = 12.0
## Cuánto se aparta el lago de quedar de frente al punto de aparición, en radianes.
const SWAY: float = 0.3
## Metros de agua que la isla deja libres hasta cada pared del lago.
const CHANNEL: float = 15.0
## Metros que la isla se corre del medio del lago a lo largo del eje, como mucho.
const ISLAND_SHIFT: float = 8.0
## Largo mínimo y máximo del muelle, en metros.
const PIER_MIN: float = 12.0
const PIER_MAX: float = 30.0
## Radianes que separan el muelle de una rampa de la isla, como mínimo.
const PIER_RAMP_GAP: float = 0.7
## Metros que el camino de la isla se queda antes del Árbol Hueco.
const LANDMARK_STOP: float = 8.0
## La meseta-manantial: metros pasada la rampa del brazo de río arriba hasta
## su lugar junto a él (mínimo, máximo). Cerca de la punta: más adentro, el
## lago ya se está abriendo y la meseta no cabe; antes, la cascada caería
## sobre la rampa del brazo.
const SPRING_FROM := Vector2(8.0, 12.0)
## Si el lago no cabe se prueba más corto: cuánto se achican los brazos y el
## cuerpo en cada vuelta, cuántas vueltas, y lo mínimo que un brazo mide más
## allá de la rampa de su punta.
const ARM_SHRINK: float = 0.8
const BODY_SHRINK: float = 0.95
const SHRINK_STEPS: int = 5
const ARM_DEEP_MIN: float = 6.0


## El trazado del lago; false si el lago, la isla o el muelle no cupieron.
static func try_plan(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var s := layout.settings
	if not _place_lake(layout, rng, calm):
		return false
	if not _place_island(layout, rng, calm):
		return false
	if not _place_pier(layout):
		return false
	if bool(layout.options.get("road", true)):
		_lay_road(layout)
	if bool(layout.options.get("falls", false)):
		var ravine := layout.ravine
		RecipeKit.place_springhead(layout, rng, calm, ravine.points[0].length()
				>= ravine.points[ravine.points.size() - 1].length(), SPRING_FROM,
				Vector2(s.lake_spring_radius_min, s.lake_spring_radius_max))
	if not RecipeKit.add_buttes(layout, rng, calm, maxi(s.butte_count_min - 1, 0),
			maxi(s.butte_count_max - 1, 1)):
		return false
	ReliefPlanner.place_hills(layout, rng)
	return true


## El lago: un brazo de río, el cuerpo ancho y otro brazo, sobre un eje
## apenas curvo que pasa frente al punto de aparición.
static func _place_lake(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var s := layout.settings
	for attempt in ReliefPlanner.PLACE_ATTEMPTS:
		var arm_half := ReliefPlanner.roll(rng, s.ravine_width_min, s.ravine_width_max, calm) * 0.5
		var depth := ReliefPlanner.roll(rng, s.ravine_depth_min, s.ravine_depth_max, calm)
		var body := ReliefPlanner.roll(rng, s.lake_length_min, s.lake_length_max, calm)
		var lake_half := ReliefPlanner.roll(rng, s.lake_half_min, s.lake_half_max, calm)
		var arm_a := ReliefPlanner.roll(rng, s.lake_arm_min, s.lake_arm_max, calm)
		var arm_b := ReliefPlanner.roll(rng, s.lake_arm_min, s.lake_arm_max, calm)
		var facing := PI * 0.25 + PI * 0.5 * float(rng.randi_range(0, 3)) if calm \
				else rng.randf() * TAU
		var out := Vector2.from_angle(facing)
		var along := Vector2(-out.y, out.x).rotated(0.0 if calm else rng.randf_range(-SWAY, SWAY))
		var center := out * (ReliefPlanner.roll(rng, s.lake_shore_min, s.lake_shore_max, calm)
				+ lake_half)
		var bend := out * (0.0 if calm else rng.randf_range(-BEND, BEND))
		var arm_least := depth / tan(deg_to_rad(s.ravine_ramp_slope_degrees)) + ARM_DEEP_MIN
		for step in SHRINK_STEPS:
			var shrink := pow(ARM_SHRINK, float(step))
			var first := maxf(arm_a * shrink, arm_least)
			var second := maxf(arm_b * shrink, arm_least)
			var middle := maxf(body * pow(BODY_SHRINK, float(step)), s.lake_length_min * 0.85)
			var start := center - along * (first + middle * 0.5)
			var finish := center + along * (second + middle * 0.5)
			var total := first + middle + second
			var points := ReliefRavine.bezier3(start, start.lerp(finish, 1.0 / 3.0) + bend,
					start.lerp(finish, 2.0 / 3.0) + bend, finish, total)
			ReliefRavine.set_axis(layout, points, lake_half, depth)
			var ravine := layout.ravine
			ravine.arm_half = arm_half
			ravine.lake_flare = FLARE
			ravine.lake_from = first * ravine.length / total
			ravine.lake_to = (first + middle) * ravine.length / total
			if _fits(layout):
				return true
			layout.ravine = null
	return false


## True si el lago entero (con el ancho de cada tramo) queda dentro de la
## arena con su margen y fuera del claro del punto de aparición.
static func _fits(layout: ReliefLayout) -> bool:
	var s := layout.settings
	var ravine := layout.ravine
	for index in ravine.points.size():
		var point := ravine.points[index]
		var wide := ravine.half_at(ravine.along[index])
		var limit := layout.half - s.edge_margin - wide
		if absf(point.x) > limit or absf(point.y) > limit:
			return false
		if point.length() - wide < s.spawn_clearance + RecipeKit.SPAWN_GAP:
			return false
	return true


## La isla: en el medio del lago, con agua de sobra alrededor y una o dos
## rampas que bajan al fondo a lo largo del eje. Es la zona más alta de la
## receta (`top`): ahí va el Árbol Hueco.
static func _place_island(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var s := layout.settings
	var ravine := layout.ravine
	var middle := (ravine.lake_from + ravine.lake_to) * 0.5
	for attempt in ReliefPlanner.PLACE_ATTEMPTS:
		var at := middle + (0.0 if calm else rng.randf_range(-ISLAND_SHIFT, ISLAND_SHIFT))
		var frame := layout.ravine_frame(at)
		var island := ReliefPlanner.new_zone(rng, calm, &"island", s.island_radius_min,
				s.island_radius_max, Vector2(1.0, 1.3), s.butte_lobes, frame[1].angle())
		island.floor = -ravine.depth
		island.height = ravine.depth
		island.swell = 0.0
		island.top = true
		island.ramp_slope = s.ramp_slope_degrees
		island.center = frame[0]
		if not _island_fits(layout, island):
			continue
		if not ReliefRamps.place(layout, island, frame[1].angle() + (0.0 if calm else rng.randf_range(-0.3, 0.3)),
				ReliefPlanner.jitters(rng, s.butte_ways_max, calm), 1, s.butte_ways_max):
			continue
		layout.zones.append(island)
		return true
	return false


## True si todo el contorno de `island` cae en el cuerpo del lago, a CHANNEL
## metros o más de sus paredes.
static func _island_fits(layout: ReliefLayout, island: ReliefLayout.Zone) -> bool:
	var ravine := layout.ravine
	for point: Vector2 in ReliefPlanner.rim_points(island):
		var coords := layout.ravine_coords(point)
		if coords.x < ravine.lake_from or coords.x > ravine.lake_to:
			return false
		if coords.y > ravine.half_at(coords.x) - CHANNEL:
			return false
	return true


## El muelle: de la pared del lado del punto de aparición a la isla, de
## frente, sin cruzarse con una rampa de la isla.
static func _place_pier(layout: ReliefLayout) -> bool:
	var ravine := layout.ravine
	var index := layout.zones.size() - 1
	var island := layout.zones[index]
	var at := layout.ravine_coords(island.center).x
	var frame := layout.ravine_frame(at)
	var left := Vector2(-frame[1].y, frame[1].x)
	var side := 1 if (-frame[0]).dot(left) >= 0.0 else -1
	var wall := frame[0] + left * (float(side) * ravine.half_at(at))
	var toward := (wall - island.center).normalized()
	for ramp: ReliefLayout.Ramp in island.ramps:
		if absf(angle_difference(ramp.angle, toward.angle())) < PIER_RAMP_GAP:
			return false
	var shore := island.center + toward * layout.zone_radius(island, toward.angle())
	var span := wall.distance_to(shore)
	if span < PIER_MIN or span > PIER_MAX:
		return false
	return ReliefRavine.add_pier(layout, at, side, index, wall, shore)


## El camino: del punto de aparición a la cabecera del muelle en la orilla y,
## en la isla, de su cabecera hacia el Árbol Hueco.
static func _lay_road(layout: ReliefLayout) -> void:
	for crossing: ReliefLayout.Crossing in layout.crossings:
		if crossing.island < 0:
			continue
		var start := crossing.head_a.normalized() * RecipeKit.ROAD_START
		if not RecipeKit.straight_clear(layout, start, crossing.head_a):
			return
		layout.road_legs.append({"points": PackedVector2Array([start, crossing.head_a]),
				"fading": false})
		var island := layout.zones[crossing.island]
		var inland := island.center - crossing.head_b
		if inland.length() > LANDMARK_STOP + 2.0:
			layout.road_legs.append({"points": PackedVector2Array([crossing.head_b,
					crossing.head_b + inland.normalized() * (inland.length() - LANDMARK_STOP)]),
					"fading": false})
		return
