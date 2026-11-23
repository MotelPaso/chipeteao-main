class_name ReliefLattice
extends RefCounted
## La retícula gruesa del suelo base de un Terrain con relieve por zonas: un
## punto cada `noise_step` metros con la ondulación del ruido, la loma de cada
## zona elevada, las lomas sueltas y la vaguada del cañón. ReliefField la
## interpola a 1 m (su rejilla `base`) y sigue desde ahí.

## Edita aquí (no hay Inspector); los valores de diseño están en
## ReliefSettings y en los exports del Terrain.
##
## Metros desde el contorno de una zona en que su loma sigue a altura completa.
const SWELL_SHELF: float = 3.0
## Metros desde el borde del cañón en que la vaguada sigue a fondo
## completo, y metros que tarda la ondulación del suelo en volver a su fuerza.
const VALLEY_SHELF: float = 4.0
const DETAIL_BLEND: float = 6.0
## Junto al contorno de una zona y sobre sus rampas la ondulación del suelo
## se amansa a esta fracción: la cornisa de roca de un corte se apoya en ese
## suelo, y sobre una loma fuerte quedaría con caras de 45 grados; una rampa
## inclinada de más deja de caminarse. A EDGE_FLAT metros del corte sigue
## amansada del todo y recupera su fuerza a EDGE_REACH metros.
const EDGE_DETAIL: float = 0.35
const EDGE_FLAT: float = 5.0
const EDGE_REACH: float = 13.0
## Paso del barrido que marca la vaguada sobre la retícula gruesa, en metros
## (a lo largo y a lo ancho del eje). Más fino que la retícula: sin huecos.
const VALLEY_STEP_ALONG: float = 1.0
const VALLEY_STEP_ACROSS: float = 1.5

## Puntos por lado y metros entre dos puntos vecinos.
var count: int = 0
var spacing: float = 0.0
## Altura de cada punto, fila por fila (primero z, después x).
var heights := PackedFloat32Array()

var _layout: ReliefLayout = null
var _half: float = 0.0


func _init(layout: ReliefLayout, half: float) -> void:
	_layout = layout
	_half = half


## Llena la retícula para `terrain`, con el ruido de `noise_seed`.
func build(terrain: Terrain, noise_seed: int) -> void:
	var step := maxf(terrain.noise_step, 0.5)
	var lattice := maxi(int(ceil(terrain.size / step)) + 1, 2)
	var lift := PackedFloat32Array()
	lift.resize(lattice * lattice)
	_stamp_swells(lift, lattice, step)
	var side := PackedFloat32Array()
	side.resize(lattice * lattice)
	side.fill(INF)
	if _layout.ravine != null:
		_stamp_valley(side, lattice, step)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = 1.0 / maxf(terrain.feature_size, 1.0)
	noise.fractal_octaves = maxi(terrain.octaves, 1)
	var settings := _layout.settings
	var coarse := PackedFloat32Array()
	coarse.resize(lattice * lattice)
	for lz in lattice:
		var z := -_half + float(lz) * step
		for lx in lattice:
			var index := lz * lattice + lx
			var x := -_half + float(lx) * step
			var detail := noise.get_noise_2d(x, z) * terrain.amplitude \
					* _edge_detail(Vector2(x, z))
			# Metros pasada la pared del cañón (negativo adentro), o INF lejos.
			var beyond := side[index]
			if beyond == INF:
				coarse[index] = detail + lift[index]
				continue
			# Junto al cañón: la vaguada tira del suelo hacia abajo y la
			# ondulación se amansa sobre el fondo.
			var valley := 1.0 - smoothstep(VALLEY_SHELF, VALLEY_SHELF + settings.swell_reach, beyond)
			var calm := 1.0 - smoothstep(0.0, DETAIL_BLEND, beyond)
			coarse[index] = detail * lerpf(1.0, settings.ravine_floor_detail, calm) \
					+ lerpf(lift[index], -settings.ravine_valley, valley)
	count = lattice
	spacing = step
	heights = coarse


## Fracción de la ondulación del suelo que queda en `point`: EDGE_DETAIL
## junto al contorno de una zona y sobre sus rampas, 1 lejos de todas.
func _edge_detail(point: Vector2) -> float:
	var nearest := EDGE_REACH
	for zone: ReliefLayout.Zone in _layout.zones:
		nearest = minf(nearest, ReliefQueries.zone_distance(_layout, zone, point, EDGE_REACH))
	return lerpf(EDGE_DETAIL, 1.0, smoothstep(EDGE_FLAT, EDGE_REACH, nearest))


## La loma de cada zona elevada y las lomas sueltas: en cada punto gana la
## más alta (no se suman, así la cima del mapa la fija una sola zona).
func _stamp_swells(lift: PackedFloat32Array, lattice: int, step: float) -> void:
	var reach := _layout.settings.swell_reach
	for zone: ReliefLayout.Zone in _layout.zones:
		# Una zona apilada no tiene loma propia: la lleva la de su base.
		if zone.parent >= 0:
			continue
		_stamp_dome(lift, lattice, step, zone.center, zone.r_max + SWELL_SHELF,
				zone.r_max + SWELL_SHELF + reach, zone.swell)
	for hill: ReliefLayout.Hill in _layout.hills:
		_stamp_dome(lift, lattice, step, hill.center, 0.0, hill.radius, hill.height)


## Una loma redonda: `height` hasta `shelf` metros del centro, 0 desde `rim`.
func _stamp_dome(lift: PackedFloat32Array, lattice: int, step: float, center: Vector2,
		shelf: float, rim: float, height: float) -> void:
	var from_x := clampi(floori((center.x - rim + _half) / step), 0, lattice - 1)
	var to_x := clampi(ceili((center.x + rim + _half) / step), 0, lattice - 1)
	var from_z := clampi(floori((center.y - rim + _half) / step), 0, lattice - 1)
	var to_z := clampi(ceili((center.y + rim + _half) / step), 0, lattice - 1)
	for lz in range(from_z, to_z + 1):
		var dz := -_half + float(lz) * step - center.y
		for lx in range(from_x, to_x + 1):
			var dx := -_half + float(lx) * step - center.x
			var distance := sqrt(dx * dx + dz * dz)
			if distance >= rim:
				continue
			var index := lz * lattice + lx
			lift[index] = maxf(lift[index], height * (1.0 - smoothstep(shelf, rim, distance)))


## Anota en `side` cuántos metros pasada la pared del cañón (negativo
## adentro) queda cada punto de la retícula que cae en su vaguada, con el
## ancho que tiene el cañón ahí: barre cada tramo del eje a lo ancho y
## redondea los dos extremos.
func _stamp_valley(side: PackedFloat32Array, lattice: int, step: float) -> void:
	var ravine := _layout.ravine
	var reach := ravine.half_width + VALLEY_SHELF + _layout.settings.swell_reach
	for index in ravine.points.size() - 1:
		var from := ravine.points[index]
		var chord := ravine.points[index + 1] - from
		var span := chord.length()
		var along := chord / span
		var across := Vector2(-along.y, along.x)
		var a := 0.0
		while a <= span:
			var wide := ravine.half_at(ravine.along[index] + a)
			var v := -reach
			while v <= reach:
				var at := from + along * a + across * v
				var lx := roundi((at.x + _half) / step)
				var lz := roundi((at.y + _half) / step)
				if lx >= 0 and lz >= 0 and lx < lattice and lz < lattice:
					var cell := lz * lattice + lx
					side[cell] = minf(side[cell], absf(v) - wide)
				v += VALLEY_STEP_ACROSS
			a += VALLEY_STEP_ALONG
	var tips: Array[Vector2] = [ravine.points[0], ravine.points[ravine.points.size() - 1]]
	var tip_wide: Array[float] = [ravine.half_at(0.0), ravine.half_at(ravine.length)]
	for which in 2:
		var tip := tips[which]
		var from_x := clampi(floori((tip.x - reach + _half) / step), 0, lattice - 1)
		var to_x := clampi(ceili((tip.x + reach + _half) / step), 0, lattice - 1)
		var from_z := clampi(floori((tip.y - reach + _half) / step), 0, lattice - 1)
		var to_z := clampi(ceili((tip.y + reach + _half) / step), 0, lattice - 1)
		for lz in range(from_z, to_z + 1):
			for lx in range(from_x, to_x + 1):
				var at := Vector2(-_half + float(lx) * step, -_half + float(lz) * step)
				var cell := lz * lattice + lx
				side[cell] = minf(side[cell], at.distance_to(tip) - tip_wide[which])
