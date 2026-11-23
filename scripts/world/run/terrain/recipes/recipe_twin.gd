class_name RecipeTwin
extends RefCounted
## La receta EL PASO DE LOS DOS MONTES (ver ReliefRecipes): dos montañas de
## dos niveles, una a cada lado del punto de aparición, y el equipo en el
## valle entre ellas. El camino antiguo atraviesa el paso de punta a punta
## por el medio del valle (ReliefStructures le pone un portal de piedra en
## cada boca y un círculo de piedras en cada cima). Sin cañón ni puentes;
## algún cerro suelto más allá.

## Edita aquí (no hay Inspector); los valores de diseño están en
## ReliefSettings (grupo «Receta: el paso de los dos montes»).
##
## Cuánto se aparta cada monte de quedar justo enfrente del otro, en radianes.
const SWAY: float = 0.25
## Cuánto se alarga la base de cada monte a lo largo del valle (mín., máx.).
const STRETCH := Vector2(1.05, 1.3)


## El trazado del paso; false si un monte o los cerros no cupieron.
static func try_plan(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var s := layout.settings
	var facing := PI * 0.25 + PI * 0.5 * float(rng.randi_range(0, 3)) if calm \
			else rng.randf() * TAU
	var out := Vector2.from_angle(facing)
	var valley := Vector2(-out.y, out.x)
	_lay_road(layout, valley)
	for side: float in [1.0, -1.0]:
		if not _place_mount(layout, rng, calm, out * side, valley):
			return false
	if not RecipeKit.add_buttes(layout, rng, calm, maxi(s.butte_count_min - 1, 0),
			maxi(s.butte_count_max - 2, 1)):
		return false
	ReliefPlanner.place_hills(layout, rng)
	return true


## El camino del paso: dos tramos rectos por el eje del valle, del punto de
## aparición hacia cada punta del mapa, que se pierden al llegar.
static func _lay_road(layout: ReliefLayout, valley: Vector2) -> void:
	var limit := layout.half - RecipeKit.ROAD_EDGE
	var reach := limit / maxf(absf(valley.x), absf(valley.y))
	for side: float in [1.0, -1.0]:
		var way := valley * side
		layout.road_legs.append({"fading": true, "points": PackedVector2Array([
				way * RecipeKit.ROAD_START, way * reach])})


## Un monte hacia `toward` (unitario, desde el punto de aparición): una base
## alargada a lo largo del valle, con sus rampas al llano lejos del camino, y
## un nivel arriba corrido hacia afuera, con su rampa mirando al valle.
static func _place_mount(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool,
		toward: Vector2, valley: Vector2) -> bool:
	var s := layout.settings
	for attempt in ReliefPlanner.PLACE_ATTEMPTS:
		var aim := toward.rotated(0.0 if calm else rng.randf_range(-SWAY, SWAY))
		var base := ReliefPlanner.new_zone(rng, calm, &"mount", s.twin_radius_min,
				s.twin_radius_max, STRETCH, s.massif_lobes, valley.angle())
		base.ramp_slope = s.ramp_slope_degrees
		base.height = ReliefPlanner.roll(rng, s.massif_height_min, s.massif_height_max, calm)
		base.swell = ReliefPlanner.roll(rng, s.massif_swell_min, s.massif_swell_max, calm)
		base.center = aim * ReliefPlanner.roll(rng, s.twin_distance_min, s.twin_distance_max, calm)
		if not ReliefPlanner.inside_arena(layout, base) or not RecipeKit.spawn_clear(layout, base):
			continue
		if not ReliefPlanner.loose_fits(layout, base):
			continue
		if not ReliefRamps.place(layout, base, valley.angle() + (0.0 if calm else rng.randf_range(-0.4, 0.4)),
				ReliefPlanner.jitters(rng, s.massif_ways_max, calm), s.massif_ways_min,
				s.massif_ways_max - 1):
			continue
		# Una rampa que cae sobre el camino del valle se saca; el monte sigue
		# si le quedan al menos dos.
		if RecipeKit.drop_road_ramps(layout, base, s.twin_road_clearance) < 2:
			continue
		if not RecipeKit.clear_of_road(layout, base, s.twin_road_clearance):
			continue
		layout.zones.append(base)
		if _place_top(layout, rng, calm, layout.zones.size() - 1, aim):
			return true
		layout.zones.pop_back()
	return false


## El nivel de arriba del monte de índice `base_index`: corrido hacia afuera
## del valle (`aim`), con la rampa mirando al valle.
static func _place_top(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool,
		base_index: int, aim: Vector2) -> bool:
	var s := layout.settings
	var base := layout.zones[base_index]
	for attempt in 12:
		var top := ReliefPlanner.new_zone(rng, calm, &"tier", s.twin_top_radius_min,
				s.twin_top_radius_max, Vector2(1.0, s.tier_stretch_max), s.tier_lobes)
		top.parent = base_index
		top.floor = base.floor + base.height
		top.ramp_slope = s.tier_ramp_slope_degrees
		top.height = ReliefPlanner.roll(rng, s.tier_height_min, s.tier_height_max, calm)
		var rim := layout.zone_radius(base, aim.angle())
		var shift := maxf(rim - top.r_max - s.tier_margin - 1.5, 0.0) \
				* (1.0 if calm else rng.randf_range(0.55, 0.9))
		top.center = base.center + aim * shift
		if not ReliefPlanner.child_fits(layout, top):
			continue
		if not ReliefRamps.place(layout, top, (-aim).angle() + (0.0 if calm else rng.randf_range(-0.5, 0.5)),
				ReliefPlanner.jitters(rng, s.tier_ways_max, calm), 1, s.tier_ways_max - 1):
			continue
		layout.zones.append(top)
		return true
	return false
