class_name ReliefField
extends RefCounted
## Convierte un trazado (ReliefLayout) en las alturas de un Terrain con
## relieve por zonas. El Terrain lo usa una vez, al construirse.
##
## Tres rejillas de una muestra por metro, las tres del tamaño del colisionador:
## - `base`: el suelo sin zonas (lomas anchas + ondulación + claros planos).
## - `heights`: lo que va al colisionador y a la malla. Zonas y barranco van
##   como un escalón duro, corrido LEDGE_INSET hacia el lado alto de cada
##   corte: queda escondido bajo la cornisa de roca (CliffWall).
## - `surface`: lo que se pisa, con el escalón en la línea nominal del corte.
##   Es lo que responde Terrain.height_at.
##
## Orden: lomas y vaguada en la retícula gruesa del ruido, interpolación a
## 1 m, borde plano, claros y, al final, las zonas encima.

## Edita aquí (no hay Inspector); los valores de diseño están en
## ReliefSettings y en los exports del Terrain.
##
## Metros desde el contorno de una zona en que su loma sigue a altura completa.
const SWELL_SHELF: float = 3.0
## Metros desde el borde del barranco en que la vaguada sigue a fondo
## completo, y metros que tarda la ondulación del suelo en volver a su fuerza.
const VALLEY_SHELF: float = 4.0
const DETAIL_BLEND: float = 6.0
## Paso del barrido que marca la vaguada sobre la retícula gruesa, en metros
## (a lo largo y a lo ancho del eje). Más fino que la retícula: sin huecos.
const VALLEY_STEP_ALONG: float = 1.0
const VALLEY_STEP_ACROSS: float = 1.5
## Metros a cada lado de un corte donde la malla del suelo va a 1 m.
const FINE_REACH: float = 5.0
## Muestras por lado de un bloque de la malla gruesa (2 m).
const BLOCK: int = 2

var heights := PackedFloat32Array()
var surface := PackedFloat32Array()
var base := PackedFloat32Array()
## 1 en los bloques de malla que van a 1 m (los que tocan un corte).
var fine := PackedByteArray()
var min_height: float = 0.0
var max_height: float = 0.0

var _layout: ReliefLayout = null
var _samples: int = 0
var _half: float = 0.0
var _blocks: int = 0


## Llena las tres rejillas para `terrain` (que ya conoce su tamaño y sus
## muestras). `pads` son los claros planos: {center, radius} y, opcional,
## `level` (si falta, el claro se aplana a la altura del suelo en su centro).
func build(layout: ReliefLayout, terrain: Terrain, noise_seed: int, samples: int,
		pads: Array[Dictionary]) -> void:
	_layout = layout
	_samples = samples
	_half = terrain.size * 0.5
	_blocks = (samples - 1) / BLOCK
	fine.resize(_blocks * _blocks)
	_build_base(terrain, noise_seed)
	_flatten_rim(terrain.rim_flat_band)
	_apply_pads(pads, terrain.pad_blend)
	heights = base.duplicate()
	surface = base.duplicate()
	for zone: ReliefLayout.Zone in layout.zones:
		_raise_zone(zone)
	if layout.ravine != null:
		_sink_ravine()
	_measure()


## Altura del suelo base en un XZ (bilineal). Para apoyar la roca de los
## cortes, que necesita el suelo de cada lado sin el escalón.
func base_at(x: float, z: float) -> float:
	var fx := clampf(x + _half, 0.0, float(_samples - 1))
	var fz := clampf(z + _half, 0.0, float(_samples - 1))
	var ix := mini(int(fx), _samples - 2)
	var iz := mini(int(fz), _samples - 2)
	var tx := fx - float(ix)
	var row := iz * _samples + ix
	return lerpf(lerpf(base[row], base[row + 1], tx),
			lerpf(base[row + _samples], base[row + _samples + 1], tx), fz - float(iz))


# --- suelo base ------------------------------------------------------------------

## Ruido + lomas + vaguada en la retícula gruesa, interpolado a 1 m.
func _build_base(terrain: Terrain, noise_seed: int) -> void:
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
	var edge := _layout.ravine.half_width if _layout.ravine != null else 0.0
	var coarse := PackedFloat32Array()
	coarse.resize(lattice * lattice)
	for lz in lattice:
		var z := -_half + float(lz) * step
		for lx in lattice:
			var index := lz * lattice + lx
			var detail := noise.get_noise_2d(-_half + float(lx) * step, z) * terrain.amplitude
			var across := side[index]
			if across == INF:
				coarse[index] = detail + lift[index]
				continue
			# Junto al barranco: la vaguada tira del suelo hacia abajo y la
			# ondulación se amansa sobre el fondo.
			var valley := 1.0 - smoothstep(edge + VALLEY_SHELF,
					edge + VALLEY_SHELF + settings.swell_reach, across)
			var calm := 1.0 - smoothstep(edge, edge + DETAIL_BLEND, across)
			coarse[index] = detail * lerpf(1.0, settings.ravine_floor_detail, calm) \
					+ lerpf(lift[index], -settings.ravine_valley, valley)
	_upsample(coarse, lattice, step)


## La loma de cada zona elevada y las lomas sueltas: en cada punto gana la
## más alta (no se suman, así la cima del mapa la fija una sola zona).
func _stamp_swells(lift: PackedFloat32Array, lattice: int, step: float) -> void:
	var reach := _layout.settings.swell_reach
	for zone: ReliefLayout.Zone in _layout.zones:
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


## Anota en `side` la distancia al eje del barranco de cada punto de la
## retícula que cae en su vaguada: barre cada tramo del eje a lo ancho y
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
			var v := -reach
			while v <= reach:
				var at := from + along * a + across * v
				var lx := roundi((at.x + _half) / step)
				var lz := roundi((at.y + _half) / step)
				if lx >= 0 and lz >= 0 and lx < lattice and lz < lattice:
					var cell := lz * lattice + lx
					side[cell] = minf(side[cell], absf(v))
				v += VALLEY_STEP_ACROSS
			a += VALLEY_STEP_ALONG
	for tip: Vector2 in [ravine.points[0], ravine.points[ravine.points.size() - 1]]:
		var from_x := clampi(floori((tip.x - reach + _half) / step), 0, lattice - 1)
		var to_x := clampi(ceili((tip.x + reach + _half) / step), 0, lattice - 1)
		var from_z := clampi(floori((tip.y - reach + _half) / step), 0, lattice - 1)
		var to_z := clampi(ceili((tip.y + reach + _half) / step), 0, lattice - 1)
		for lz in range(from_z, to_z + 1):
			for lx in range(from_x, to_x + 1):
				var at := Vector2(-_half + float(lx) * step, -_half + float(lz) * step)
				var cell := lz * lattice + lx
				side[cell] = minf(side[cell], at.distance_to(tip))


## Interpola la retícula gruesa a la rejilla de 1 m (`base`).
func _upsample(coarse: PackedFloat32Array, lattice: int, step: float) -> void:
	base.resize(_samples * _samples)
	var cell := PackedInt32Array()
	var blend := PackedFloat32Array()
	cell.resize(_samples)
	blend.resize(_samples)
	for index in _samples:
		var at := minf(float(index) / step, float(lattice - 1))
		cell[index] = mini(int(at), lattice - 2)
		blend[index] = at - float(cell[index])
	for iz in _samples:
		var row := cell[iz] * lattice
		var tz := blend[iz]
		var out := iz * _samples
		for ix in _samples:
			var at := row + cell[ix]
			var tx := blend[ix]
			base[out + ix] = lerpf(lerpf(coarse[at], coarse[at + 1], tx),
					lerpf(coarse[at + lattice], coarse[at + lattice + 1], tx), tz)


## El suelo baja a 0 dentro de `band` metros del borde, para que los muros
## del perímetro y el suelo lejano del Backdrop encuentren un borde plano.
func _flatten_rim(band: float) -> void:
	var reach := mini(ceili(band), _samples / 2)
	var last := _samples - 1
	for iz in _samples:
		var row := iz * _samples
		var edge_z := mini(iz, last - iz)
		if edge_z < reach:
			for ix in _samples:
				_fade(row + ix, mini(edge_z, mini(ix, last - ix)), band)
			continue
		# Fila interior: solo sus dos franjas laterales.
		for ix in reach:
			_fade(row + ix, ix, band)
			_fade(row + last - ix, ix, band)


func _fade(index: int, edge: int, band: float) -> void:
	base[index] *= smoothstep(0.0, 1.0, float(edge) / maxf(band, 0.001))


## Aplana cada claro a su nivel y lo devuelve al relieve en `blend` metros.
## Los niveles se leen ANTES de aplanar nada, así un claro no hereda el de
## su vecino.
func _apply_pads(pads: Array[Dictionary], blend: float) -> void:
	var levels := PackedFloat32Array()
	for pad: Dictionary in pads:
		var center: Vector2 = pad["center"]
		levels.append(float(pad["level"]) if pad.has("level") else base_at(center.x, center.y))
	for crossing: ReliefLayout.Crossing in _layout.crossings:
		crossing.level = (base_at(crossing.head_a.x, crossing.head_a.y)
				+ base_at(crossing.head_b.x, crossing.head_b.y)) * 0.5
	for index in pads.size():
		var center: Vector2 = pads[index]["center"]
		_flatten_pad(center, float(pads[index]["radius"]), blend, levels[index])
	# Las dos cabeceras de un puente, al nivel de su tablero.
	for crossing: ReliefLayout.Crossing in _layout.crossings:
		for head: Vector2 in [crossing.head_a, crossing.head_b]:
			_flatten_pad(head, _layout.settings.bridgehead_radius, blend, crossing.level)


func _flatten_pad(center: Vector2, radius: float, blend: float, level: float) -> void:
	var reach := radius + blend
	var from_x := clampi(floori(center.x - reach + _half), 0, _samples - 1)
	var to_x := clampi(ceili(center.x + reach + _half), 0, _samples - 1)
	var from_z := clampi(floori(center.y - reach + _half), 0, _samples - 1)
	var to_z := clampi(ceili(center.y + reach + _half), 0, _samples - 1)
	for iz in range(from_z, to_z + 1):
		var dz := float(iz) - _half - center.y
		for ix in range(from_x, to_x + 1):
			var dx := float(ix) - _half - center.x
			var distance := sqrt(dx * dx + dz * dz)
			if distance >= reach:
				continue
			var strength := 1.0 if distance <= radius \
					else 1.0 - smoothstep(0.0, 1.0, (distance - radius) / maxf(blend, 0.001))
			var index := iz * _samples + ix
			base[index] = lerpf(base[index], level, strength)


# --- zonas -----------------------------------------------------------------------

## Sube la meseta de `zone` y sus rampas sobre el suelo base.
func _raise_zone(zone: ReliefLayout.Zone) -> void:
	var reach := zone.r_max + FINE_REACH
	var from_x := clampi(floori(zone.center.x - reach + _half), 0, _samples - 1)
	var to_x := clampi(ceili(zone.center.x + reach + _half), 0, _samples - 1)
	var from_z := clampi(floori(zone.center.y - reach + _half), 0, _samples - 1)
	var to_z := clampi(ceili(zone.center.y + reach + _half), 0, _samples - 1)
	var inset := ReliefLayout.LEDGE_INSET
	for iz in range(from_z, to_z + 1):
		for ix in range(from_x, to_x + 1):
			var rel := Vector2(float(ix) - _half, float(iz) - _half) - zone.center
			var rho := rel.length()
			if rho > reach:
				continue
			var angle := rel.angle()
			var rim := _layout.polar(zone.radii, angle)
			if absf(rho - rim) <= FINE_REACH:
				_mark_fine(ix, iz)
			if rho > rim:
				continue
			var index := iz * _samples + ix
			surface[index] = base[index] + zone.height
			if rho <= rim - inset * _layout.polar(zone.oblique, angle):
				heights[index] = base[index] + zone.height
	for ramp: ReliefLayout.Ramp in zone.ramps:
		_raise_ramp(zone, ramp)


## La rampa: baja de la altura de su zona a 0 a lo largo de su eje. Donde
## pisa la meseta gana la altura mayor, así no le hace una muesca.
func _raise_ramp(zone: ReliefLayout.Zone, ramp: ReliefLayout.Ramp) -> void:
	var box := Rect2(ramp.origin + ramp.dir * ramp.back, Vector2.ZERO)
	for along: float in [ramp.back, ramp.length]:
		for across: float in [-1.0, 1.0]:
			box = box.expand(ramp.origin + ramp.dir * along
					+ ramp.perp * (across * (ramp.half_width + FINE_REACH)))
	var from_x := clampi(floori(box.position.x + _half), 0, _samples - 1)
	var to_x := clampi(ceili(box.end.x + _half), 0, _samples - 1)
	var from_z := clampi(floori(box.position.y + _half), 0, _samples - 1)
	var to_z := clampi(ceili(box.end.y + _half), 0, _samples - 1)
	var core := ramp.half_width - ReliefLayout.LEDGE_INSET
	for iz in range(from_z, to_z + 1):
		for ix in range(from_x, to_x + 1):
			var local := Vector2(float(ix) - _half, float(iz) - _half) - ramp.origin
			var u := local.dot(ramp.dir)
			if u < ramp.back or u >= ramp.length:
				continue
			var v := absf(local.dot(ramp.perp))
			if v > ramp.half_width + FINE_REACH:
				continue
			_mark_fine(ix, iz)
			if v > ramp.half_width:
				continue
			var index := iz * _samples + ix
			var lifted := base[index] + zone.height * clampf(1.0 - u / ramp.length, 0.0, 1.0)
			surface[index] = maxf(surface[index], lifted)
			if v <= core:
				heights[index] = maxf(heights[index], lifted)


## Hunde el pasillo del barranco, tramo por tramo de su eje.
func _sink_ravine() -> void:
	var ravine := _layout.ravine
	var grown := ravine.half_width + ReliefLayout.LEDGE_INSET
	var reach := ravine.half_width + FINE_REACH
	for index in ravine.points.size() - 1:
		var from := ravine.points[index]
		var to := ravine.points[index + 1]
		var chord := to - from
		var span := ravine.along[index + 1] - ravine.along[index]
		var from_x := clampi(floori(minf(from.x, to.x) - reach + _half), 0, _samples - 1)
		var to_x := clampi(ceili(maxf(from.x, to.x) + reach + _half), 0, _samples - 1)
		var from_z := clampi(floori(minf(from.y, to.y) - reach + _half), 0, _samples - 1)
		var to_z := clampi(ceili(maxf(from.y, to.y) + reach + _half), 0, _samples - 1)
		for iz in range(from_z, to_z + 1):
			for ix in range(from_x, to_x + 1):
				var point := Vector2(float(ix) - _half, float(iz) - _half)
				var t := (point - from).dot(chord) / (span * span)
				if t < -ReliefLayout.CHORD_SLACK or t > 1.0 + ReliefLayout.CHORD_SLACK:
					continue
				var s := ravine.along[index] + span * t
				if s < 0.0 or s > ravine.length:
					continue
				var across := point.distance_to(from + chord * clampf(t, 0.0, 1.0))
				if across > reach:
					continue
				if absf(across - ravine.half_width) <= FINE_REACH:
					_mark_fine(ix, iz)
				if across > grown:
					continue
				var cell := iz * _samples + ix
				var sunk := base[cell] - _layout.ravine_drop(s)
				heights[cell] = minf(heights[cell], sunk)
				if across <= ravine.half_width:
					surface[cell] = minf(surface[cell], sunk)


## Marca como fino el bloque de malla de la muestra (ix, iz) y, si la
## muestra cae en una arista entre bloques, también el vecino.
func _mark_fine(ix: int, iz: int) -> void:
	var bx := mini(ix / BLOCK, _blocks - 1)
	var bz := mini(iz / BLOCK, _blocks - 1)
	fine[bz * _blocks + bx] = 1
	if ix % BLOCK == 0 and bx > 0:
		fine[bz * _blocks + bx - 1] = 1
	if iz % BLOCK == 0 and bz > 0:
		fine[(bz - 1) * _blocks + bx] = 1


func _measure() -> void:
	min_height = INF
	max_height = -INF
	for h: float in surface:
		if h < min_height:
			min_height = h
		if h > max_height:
			max_height = h
