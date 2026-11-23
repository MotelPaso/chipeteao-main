class_name ReliefField
extends RefCounted
## Convierte un trazado (ReliefLayout) en las alturas de un Terrain con
## relieve por zonas. El Terrain lo usa una vez, al construirse.
##
## Tres rejillas de una muestra por metro, las tres del tamaño del colisionador:
## - `base`: el suelo sin zonas (lomas anchas + ondulación + claros planos).
## - `heights`: lo que va al colisionador y a la malla. Zonas y cañón van
##   como un escalón duro, corrido LEDGE_INSET hacia el lado alto de cada
##   corte: queda escondido bajo la cornisa de roca (CliffWall).
## - `surface`: lo que se pisa, con el escalón en la línea nominal del corte.
##   Es lo que responde Terrain.height_at.
##
## Orden: lomas y vaguada en la retícula gruesa del ruido (ReliefLattice),
## interpolación a 1 m, borde plano, claros y, al final, las zonas encima.

## Edita aquí (no hay Inspector); los valores de diseño están en
## ReliefSettings y en los exports del Terrain.
##
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
	_flatten_rim(terrain.rim_flat_band, layout.settings.rim_blend)
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

## El suelo base: la retícula gruesa de ReliefLattice (ruido, lomas y la
## vaguada del cañón), interpolada a 1 m.
func _build_base(terrain: Terrain, noise_seed: int) -> void:
	var lattice := ReliefLattice.new(_layout, _half)
	lattice.build(terrain, noise_seed)
	_upsample(lattice.heights, lattice.count, lattice.spacing)


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


## Los últimos `band` metros quedan a nivel del borde (0) y el relieve vuelve
## en `blend` metros más: los muros del perímetro siempre alcanzan, y el suelo
## de afuera (OutsideRelief) sale de ese mismo nivel.
func _flatten_rim(band: float, blend: float) -> void:
	var reach := mini(ceili(band + blend), _samples / 2)
	var last := _samples - 1
	for iz in _samples:
		var row := iz * _samples
		var edge_z := mini(iz, last - iz)
		if edge_z < reach:
			for ix in _samples:
				_fade(row + ix, mini(edge_z, mini(ix, last - ix)), band, blend)
			continue
		# Fila interior: solo sus dos franjas laterales.
		for ix in reach:
			_fade(row + ix, ix, band, blend)
			_fade(row + last - ix, ix, band, blend)


func _fade(index: int, edge: int, band: float, blend: float) -> void:
	base[index] *= smoothstep(band, band + maxf(blend, 0.001), float(edge))


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

## Sube la meseta de `zone` y sus rampas sobre el suelo donde se apoya. Las
## zonas llegan con el padre antes que la hija, así la hija pisa lo que dejó
## el padre.
func _raise_zone(zone: ReliefLayout.Zone) -> void:
	var reach := zone.r_max + FINE_REACH
	var from_x := clampi(floori(zone.center.x - reach + _half), 0, _samples - 1)
	var to_x := clampi(ceili(zone.center.x + reach + _half), 0, _samples - 1)
	var from_z := clampi(floori(zone.center.y - reach + _half), 0, _samples - 1)
	var to_z := clampi(ceili(zone.center.y + reach + _half), 0, _samples - 1)
	var inset := ReliefLayout.LEDGE_INSET
	var top := zone.floor + zone.height
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
			surface[index] = base[index] + top
			if rho <= rim - inset * _layout.polar(zone.oblique, angle):
				heights[index] = base[index] + top
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
			var lifted := base[index] + zone.floor \
					+ zone.height * clampf(1.0 - u / ramp.length, 0.0, 1.0)
			surface[index] = maxf(surface[index], lifted)
			if v <= core:
				heights[index] = maxf(heights[index], lifted)


## Hunde el pasillo del cañón, tramo por tramo de su eje.
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
