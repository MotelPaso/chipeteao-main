class_name TerrainHeights
extends RefCounted
## Las alturas CLÁSICAS de un Terrain, las de las arenas sin relieve por
## zonas (Dunas de Ceniza, Ciénaga Lóbrega; las que lo tienen arman las suyas
## en ReliefField): ruido en una retícula gruesa de noise_step metros, leída
## bilineal cada SAMPLE_METERS, que baja a 0 en el borde (rim_flat_band) y en
## los claros (pad_blend). Los valores son los exports del Terrain (grupos
## «Relieve» y «Claros planos»); ninguna escena usa este script.


## Las alturas de `terrain` en `samples` × `samples` muestras, con los claros
## `pads` ({center, radius}) y el ruido sembrado con `noise_seed`:
## {heights: PackedFloat32Array, min: float, max: float}.
static func build(terrain: Terrain, samples: int, pads: Array[Dictionary],
		noise_seed: int) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = 1.0 / maxf(terrain.feature_size, 1.0)
	noise.fractal_octaves = maxi(terrain.octaves, 1)
	# Primero la retícula gruesa (ver noise_step), luego bilineal a 1 m.
	var lattice := maxi(int(ceil(terrain.size / maxf(terrain.noise_step, 0.5))) + 1, 2)
	var coarse := PackedFloat32Array()
	coarse.resize(lattice * lattice)
	var half := terrain.size * 0.5
	for lz in lattice:
		var z := -half + float(lz) * terrain.noise_step
		for lx in lattice:
			var x := -half + float(lx) * terrain.noise_step
			coarse[lz * lattice + lx] = noise.get_noise_2d(x, z) * terrain.amplitude
	var heights := PackedFloat32Array()
	heights.resize(samples * samples)
	var low := INF
	var high := -INF
	for iz in samples:
		var z := -half + float(iz) * Terrain.SAMPLE_METERS
		for ix in samples:
			var x := -half + float(ix) * Terrain.SAMPLE_METERS
			var h := _sample_coarse(terrain, coarse, lattice, x, z)
			h *= _rim_falloff(terrain, x, z)
			h = _apply_pads(terrain, pads, x, z, h)
			heights[iz * samples + ix] = h
			low = minf(low, h)
			high = maxf(high, h)
	if low == INF:
		low = 0.0
		high = 0.0
	return {"heights": heights, "min": low, "max": high}


## Lectura bilineal de la retícula gruesa de ruido en un XZ de mundo.
static func _sample_coarse(terrain: Terrain, coarse: PackedFloat32Array, lattice: int,
		x: float, z: float) -> float:
	var half := terrain.size * 0.5
	var fx := clampf((x + half) / terrain.noise_step, 0.0, float(lattice - 1))
	var fz := clampf((z + half) / terrain.noise_step, 0.0, float(lattice - 1))
	var ix := int(fx)
	var iz := int(fz)
	var nx := mini(ix + 1, lattice - 1)
	var nz := mini(iz + 1, lattice - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := coarse[iz * lattice + ix]
	var h10 := coarse[iz * lattice + nx]
	var h01 := coarse[nz * lattice + ix]
	var h11 := coarse[nz * lattice + nx]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 1 en el centro, bajando a 0 dentro de rim_flat_band del borde: los muros
## del perímetro son estáticos y el disco del backdrop es plano, así que el
## suelo tiene que ser plano donde se encuentran.
static func _rim_falloff(terrain: Terrain, x: float, z: float) -> float:
	var half := terrain.size * 0.5
	var edge := minf(half - absf(x), half - absf(z))
	if edge >= terrain.rim_flat_band:
		return 1.0
	return smoothstep(0.0, 1.0, maxf(edge, 0.0) / maxf(terrain.rim_flat_band, 0.001))


## Aplana `h` hacia 0 dentro de un claro y vuelve al ruido en pad_blend.
## Gana el claro más fuerte, así dos claros superpuestos no se suman.
static func _apply_pads(terrain: Terrain, pads: Array[Dictionary], x: float, z: float,
		h: float) -> float:
	var flat := 0.0
	for pad: Dictionary in pads:
		var center: Vector2 = pad["center"]
		var radius: float = pad["radius"]
		var distance := Vector2(x, z).distance_to(center)
		if distance >= radius + terrain.pad_blend:
			continue
		var strength := 1.0 if distance <= radius \
				else 1.0 - smoothstep(0.0, 1.0, (distance - radius) / terrain.pad_blend)
		flat = maxf(flat, strength)
	return lerpf(h, 0.0, flat)
