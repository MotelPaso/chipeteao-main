class_name ReliefPlanner
extends RefCounted
## Sortea el trazado del relieve de una etapa (ReliefLayout) desde la
## semilla de partida. Todo gira alrededor de un rumbo al azar, hacia donde
## queda la montaña vista desde el punto de aparición:
##
##   1. el MACIZO, un nivel ancho que contiene el punto de aparición;
##   2. el SEGUNDO NIVEL, sobre el macizo, pegado a su lado lejano;
##   3. la CUMBRE, sobre el segundo nivel;
##   4. el CAÑÓN, que pasa al pie del macizo por el lado contrario, con sus
##      puentes;
##   5. las rampas del macizo al llano (ya saben dónde quedó el cañón);
##   6. los CERROS sueltos y las lomas del llano.
##
## Cada pieza se sortea por rechazo hasta que cabe. Si una obligatoria no
## cabe, se tira el trazado entero y se sortea otro.
##
## RNG PROPIO, sembrado con la semilla de partida: no saca ni un número del
## flujo de la partida, así que el relieve es función de la semilla y no
## mueve ningún otro sorteo. Las líneas de corte las arma ReliefCuts.

## Edita aquí (no hay Inspector); los valores de diseño están en ReliefSettings.
##
## Sal que separa este RNG de los otros que se siembran con la misma semilla.
const SEED_SALT: int = 0x52454C49
## Trazados completos que se intentan antes de usar el de reserva.
const PLAN_ATTEMPTS: int = 60
## Intentos por pieza dentro de un trazado.
const PLACE_ATTEMPTS: int = 40
## Cuánto se desvía del rumbo de la montaña el eje largo del macizo, y
## cuánto el segundo nivel, en radianes.
const MASSIF_SWAY: float = 0.15
const TIER_SWAY: float = 0.2
## Cuánto se aparta la primera rampa del segundo nivel de la línea al punto
## de aparición, en radianes: recta terminaría en su claro.
const TIER_FIRST_WAY: float = 0.55
## Paso con que se busca el borde de una zona a lo largo de un rayo, en metros.
const RIM_STEP: float = 0.5


## El trazado de la etapa para `seed_value`, con sus líneas de corte ya armadas.
static func plan(settings: ReliefSettings, seed_value: int, half: float) -> ReliefLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ SEED_SALT
	var layout: ReliefLayout = null
	for attempt in PLAN_ATTEMPTS:
		layout = ReliefLayout.new(settings, half)
		if _try_plan(layout, rng, false):
			break
		layout = null
	if layout == null:
		layout = ReliefLayout.new(settings, half)
		layout.fallback = true
		if not _try_plan(layout, rng, true):
			push_warning("ReliefPlanner: the reserve layout is missing a piece")
	ReliefCuts.build(layout)
	return layout


## Un trazado entero; false si alguna pieza obligatoria no cupo. Con `calm`
## es el de reserva: la montaña mira a una esquina (donde sobra lugar), cada
## medida toma el medio de su rango y los contornos son óvalos lisos.
static func _try_plan(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var bearing := rng.randf() * TAU
	if calm:
		bearing = PI * 0.25 + PI * 0.5 * float(rng.randi_range(0, 3))
	if not _place_massif(layout, rng, bearing, calm):
		return false
	if not _place_tier(layout, rng, bearing, calm):
		return false
	if not _place_summit(layout, rng, bearing, calm):
		return false
	if not ReliefRavine.place(layout, rng, bearing, calm):
		return false
	var massif := layout.zones[0]
	var s := layout.settings
	if not ReliefRamps.place(layout, massif, bearing + PI + rng.randf_range(0.5, 0.9),
			_jitters(rng, s.massif_ways_max, calm), s.massif_ways_min, s.massif_ways_max):
		return false
	var wanted := roll_int(rng, s.butte_count_min, s.butte_count_max, calm)
	var placed := 0
	for index in wanted:
		if _place_butte(layout, rng, calm):
			placed += 1
	if placed < s.butte_count_min and not calm:
		return false
	_place_hills(layout, rng)
	return true


# --- tiradas ---------------------------------------------------------------------

## Un valor entre `low` y `high`; el medio en el trazado de reserva.
static func roll(rng: RandomNumberGenerator, low: float, high: float, calm: bool) -> float:
	return (low + high) * 0.5 if calm else rng.randf_range(low, high)


static func roll_int(rng: RandomNumberGenerator, low: int, high: int, calm: bool) -> int:
	return low if calm else rng.randi_range(low, high)


## Un desvío por rampa, para que no queden a intervalos exactos.
static func _jitters(rng: RandomNumberGenerator, count: int, calm: bool) -> PackedFloat32Array:
	var jitters := PackedFloat32Array()
	for way in count:
		jitters.append(0.0 if calm else rng.randf_range(-ReliefRamps.RAMP_SPACING, ReliefRamps.RAMP_SPACING))
	return jitters


## Una zona nueva con su contorno sorteado: radio medio entre los dos dados,
## alargada entre `stretch.x` y `stretch.y` veces y con lóbulos de fuerza
## `lobes`. `turn` es hacia dónde apunta su eje largo (NAN = al azar).
static func _new_zone(rng: RandomNumberGenerator, calm: bool, kind: StringName,
		radius_min: float, radius_max: float, stretch: Vector2, lobes: float,
		turn: float = NAN) -> ReliefLayout.Zone:
	var zone := ReliefLayout.Zone.new()
	zone.kind = kind
	if calm:
		# El de reserva: el óvalo menos alargado que permite el rango, sin lóbulos.
		_shape_zone(zone, (radius_min + radius_max) * 0.5, stretch.x,
				0.0 if is_nan(turn) else turn, 0.0, 0.0, 0.0, 0.0)
	else:
		_shape_zone(zone, rng.randf_range(radius_min, radius_max),
				rng.randf_range(stretch.x, stretch.y), rng.randf() * TAU if is_nan(turn) else turn,
				rng.randf_range(0.0, lobes), rng.randf() * TAU,
				rng.randf_range(lobes * 0.3, lobes), rng.randf() * TAU)
	return zone


# --- la montaña ------------------------------------------------------------------

## El macizo: contiene el punto de aparición, corrido hacia `bearing`.
static func _place_massif(layout: ReliefLayout, rng: RandomNumberGenerator, bearing: float,
		calm: bool) -> bool:
	var s := layout.settings
	for attempt in PLACE_ATTEMPTS:
		var zone := _new_zone(rng, calm, &"massif", s.massif_radius_min, s.massif_radius_max,
				Vector2(s.massif_stretch_min, s.massif_stretch_max), s.massif_lobes,
				bearing + (0.0 if calm else rng.randf_range(-MASSIF_SWAY, MASSIF_SWAY)))
		zone.ramp_slope = s.ramp_slope_degrees
		zone.height = roll(rng, s.massif_height_min, s.massif_height_max, calm)
		zone.swell = roll(rng, s.massif_swell_min, s.massif_swell_max, calm)
		zone.center = Vector2.from_angle(bearing) \
				* roll(rng, s.massif_offset_min, s.massif_offset_max, calm)
		if not _inside_arena(layout, zone):
			continue
		if not layout.on_plateau(zone, Vector2.ZERO, s.spawn_clearance + 2.0):
			continue
		layout.zones.append(zone)
		return true
	return false


## El segundo nivel: sobre el macizo, pegado a su borde lejano para que del
## lado del punto de aparición quede meseta para sus rampas.
static func _place_tier(layout: ReliefLayout, rng: RandomNumberGenerator, bearing: float,
		calm: bool) -> bool:
	var s := layout.settings
	var massif := layout.zones[0]
	for attempt in PLACE_ATTEMPTS:
		var zone := _new_zone(rng, calm, &"tier", s.tier_radius_min, s.tier_radius_max,
				Vector2(1.0, s.tier_stretch_max), s.tier_lobes)
		zone.parent = 0
		zone.floor = massif.floor + massif.height
		zone.ramp_slope = s.tier_ramp_slope_degrees
		zone.height = roll(rng, s.tier_height_min, s.tier_height_max, calm)
		var aim := bearing + (0.0 if calm else rng.randf_range(-TIER_SWAY, TIER_SWAY))
		var out := Vector2.from_angle(aim)
		var far := rim_from_origin(layout, massif, out)
		var distance := minf(far - s.tier_margin - layout.zone_radius(zone, aim) - 1.5,
				s.tier_distance_max)
		if distance < s.tier_distance_min:
			continue
		zone.center = out * distance
		if not _child_fits(layout, zone):
			continue
		var side := 1.0 if calm or rng.randf() < 0.5 else -1.0
		if not ReliefRamps.place(layout, zone, (-zone.center).angle() + TIER_FIRST_WAY * side,
				_jitters(rng, s.tier_ways_max, calm), s.tier_ways_min, s.tier_ways_max):
			continue
		layout.zones.append(zone)
		return true
	return false


## La cumbre: sobre el segundo nivel, corrida hacia lejos del punto de
## aparición, con su rampa mirando hacia acá.
static func _place_summit(layout: ReliefLayout, rng: RandomNumberGenerator, bearing: float,
		calm: bool) -> bool:
	var s := layout.settings
	var tier := layout.zones[1]
	for attempt in PLACE_ATTEMPTS:
		var zone := _new_zone(rng, calm, &"summit", s.summit_radius_min, s.summit_radius_max,
				Vector2(1.0, 1.15), s.tier_lobes * 0.6)
		zone.parent = 1
		zone.top = true
		zone.floor = tier.floor + tier.height
		zone.ramp_slope = s.tier_ramp_slope_degrees
		zone.height = roll(rng, s.summit_height_min, s.summit_height_max, calm)
		var aim := bearing + (0.0 if calm else rng.randf_range(-0.5, 0.5))
		zone.center = tier.center + Vector2.from_angle(aim) \
				* (s.summit_shift + (0.0 if calm else rng.randf_range(-2.0, 2.0)))
		if not _child_fits(layout, zone):
			continue
		var way := (tier.center - zone.center).angle() \
				+ (0.0 if calm else rng.randf_range(-0.4, 0.4))
		if not ReliefRamps.place(layout, zone, way, _jitters(rng, s.summit_ways_max, calm),
				s.summit_ways_min, s.summit_ways_max):
			continue
		layout.zones.append(zone)
		return true
	return false


## Un cerro suelto del llano: lejos de la montaña, del cañón, de las rampas
## del macizo y de los otros cerros.
static func _place_butte(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	var s := layout.settings
	for attempt in PLACE_ATTEMPTS:
		var zone := _new_zone(rng, false, &"butte", s.butte_radius_min, s.butte_radius_max,
				Vector2(1.0, s.butte_stretch_max), s.butte_lobes)
		zone.ramp_slope = s.ramp_slope_degrees
		zone.height = roll(rng, s.butte_height_min, s.butte_height_max, calm)
		zone.swell = roll(rng, s.butte_swell_min, s.butte_swell_max, calm)
		var limit := layout.half - s.edge_margin - zone.r_max
		zone.center = Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		if not _loose_fits(layout, zone):
			continue
		if not ReliefRamps.place(layout, zone, rng.randf() * TAU,
				_jitters(rng, s.butte_ways_max, calm), s.butte_ways_min, s.butte_ways_max):
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


# --- dónde cabe una zona ---------------------------------------------------------

## Puntos del contorno de `zone`, uno cada 12 grados.
static func _rim_points(zone: ReliefLayout.Zone) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(0, ReliefLayout.TABLE, 6):
		points.append(zone.center + Vector2.from_angle(TAU * float(index)
				/ float(ReliefLayout.TABLE)) * zone.radii[index])
	return points


## True si el contorno entero de `zone` queda dentro de la arena con su margen.
static func _inside_arena(layout: ReliefLayout, zone: ReliefLayout.Zone) -> bool:
	var limit := layout.half - layout.settings.edge_margin
	for rim: Vector2 in _rim_points(zone):
		if absf(rim.x) > limit or absf(rim.y) > limit:
			return false
	return true


## Distancia desde el punto de aparición, a lo largo de `direction`, hasta
## el borde de `zone` (que lo contiene).
static func rim_from_origin(layout: ReliefLayout, zone: ReliefLayout.Zone,
		direction: Vector2) -> float:
	var reach := 0.0
	while reach < layout.half * 2.0 and layout.on_plateau(zone, direction * (reach + RIM_STEP)):
		reach += RIM_STEP
	return reach


## True si `zone` cabe sobre la meseta de su padre: todo su contorno a
## tier_margin del borde del padre y lejos del claro del punto de aparición.
static func _child_fits(layout: ReliefLayout, zone: ReliefLayout.Zone) -> bool:
	var s := layout.settings
	var parent := layout.zones[zone.parent]
	for rim: Vector2 in _rim_points(zone):
		if not layout.on_plateau(parent, rim, s.tier_margin):
			return false
		if rim.length() < s.spawn_clearance:
			return false
	return true


## True si una zona suelta cabe: dentro de la arena, a feature_gap de las
## otras zonas del llano, del cañón y de las rampas ya puestas.
static func _loose_fits(layout: ReliefLayout, zone: ReliefLayout.Zone) -> bool:
	var s := layout.settings
	if not _inside_arena(layout, zone):
		return false
	var rim := _rim_points(zone)
	rim.append(zone.center)
	for point: Vector2 in rim:
		for other: ReliefLayout.Zone in layout.zones:
			if other.parent >= 0:
				continue
			if layout.on_plateau(other, point, -s.feature_gap):
				return false
			for ramp: ReliefLayout.Ramp in other.ramps:
				if ReliefRamps.on_ramp(ramp, point, s.feature_gap):
					return false
		if ReliefRamps.near_ravine(layout, point, s.feature_gap):
			return false
	return true


# --- lomas sueltas ---------------------------------------------------------------

static func _place_hills(layout: ReliefLayout, rng: RandomNumberGenerator) -> void:
	var s := layout.settings
	var limit := layout.half - s.edge_margin
	for index in s.hill_count:
		var hill := ReliefLayout.Hill.new()
		hill.radius = rng.randf_range(s.hill_radius_min, s.hill_radius_max)
		hill.height = rng.randf_range(s.hill_height_min, s.hill_height_max)
		hill.center = Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		layout.hills.append(hill)
