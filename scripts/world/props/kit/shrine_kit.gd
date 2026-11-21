class_name ShrineKit
extends RefCounted
## Piezas de piedra que comparten las estructuras del juego (santuarios,
## altares, portales, el puesto del vendedor y la meseta del bosque):
## zócalos escalonados, columnas, braseros, piedras con runa, velas,
## cristales, monedas y musgo. Cada pieza agrega caras a un LowPolyMesh: la
## piedra va a una malla con luz y lo que brilla (llamas, runas, cristales)
## a otra sin sombreado. Quien las usa elige medidas y colores con los
## exports de su escena.
##
## Ninguna escena usa este script: no tiene valores que tocar.


## Material de lo que brilla: color de vértice, sin sombreado ni sombra.
static func glow_material() -> StandardMaterial3D:
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.vertex_color_use_as_albedo = true
	return shine


## Cuelga de `owner` la malla de piedra y la de brillo (si tienen caras),
## con los nombres `Stone` y `Glow`. Ninguna proyecta sombra propia salvo
## la piedra.
static func hang(owner: Node3D, stone: LowPolyMesh, glow: LowPolyMesh) -> void:
	if not stone.is_empty():
		owner.add_child(stone.instance("Stone"))
	if not glow.is_empty():
		var view := glow.instance("GlowMesh")
		view.material_override = glow_material()
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		owner.add_child(view)


## Un zócalo de `tiers` escalones de `sides` lados con el pie en `foot`: el
## de abajo de radio `radius`, cada uno `shrink` veces el anterior, todos de
## `step` metros de alto. El de abajo se mete bajo el suelo, así una loma no
## le deja el borde en el aire. Devuelve la altura de su cara de arriba.
static func plinth(mesh: LowPolyMesh, foot: Vector3, radius: float, tiers: int, step: float,
		shrink: float, sides: int, stone: Color, top: Color, turn: float = 0.0) -> float:
	var y := foot.y
	var reach := radius
	for tier in tiers:
		var sunk := 0.3 if tier == 0 else 0.0
		var lower := mesh.ring(Vector3(foot.x, y - sunk, foot.z), reach, sides, turn)
		var upper := mesh.ring(Vector3(foot.x, y + step, foot.z), reach, sides, turn)
		mesh.band(lower, upper, stone.darkened(0.06 * float(tiers - 1 - tier)))
		mesh.cap(upper, top, Vector3(foot.x, y, foot.z))
		y += step
		reach *= shrink
	return y


## Una columna con basa y capitel, de `height` metros con el pie en `foot`.
## Devuelve el centro de la cara de arriba del capitel.
static func column(mesh: LowPolyMesh, foot: Vector3, height: float, radius: float, sides: int,
		stone: Color, trim: Color, turn: float = 0.0) -> Vector3:
	var band_height := minf(0.24, height * 0.12)
	var base_low := mesh.ring(foot + Vector3.DOWN * 0.1, radius * 1.3, sides, turn)
	var base_top := mesh.ring(foot + Vector3.UP * band_height, radius * 1.3, sides, turn)
	mesh.band(base_low, base_top, trim)
	mesh.cap(base_top, trim, foot)
	var shaft_low := mesh.ring(foot + Vector3.UP * band_height, radius, sides, turn)
	var shaft_top := mesh.ring(foot + Vector3.UP * (height - band_height), radius * 0.86, sides,
			turn)
	mesh.band(shaft_low, shaft_top, stone)
	var cap_low := mesh.ring(foot + Vector3.UP * (height - band_height), radius * 1.34, sides, turn)
	var cap_top := mesh.ring(foot + Vector3.UP * height, radius * 1.34, sides, turn)
	mesh.band(cap_low, cap_top, trim)
	mesh.cap(cap_top, trim, foot + Vector3.UP * (height - band_height))
	mesh.cap(cap_low, trim, foot + Vector3.UP * height)
	return foot + Vector3.UP * height


## Un brasero de hierro con su fuego, apoyado en `top`.
static func brazier(mesh: LowPolyMesh, glow: LowPolyMesh, top: Vector3, radius: float,
		iron: Color, flame: Color, core: Color) -> void:
	var neck := mesh.ring(top, radius * 0.42, 6)
	var bowl_low := mesh.ring(top + Vector3.UP * radius * 0.3, radius * 0.62, 8, 0.2)
	var bowl_top := mesh.ring(top + Vector3.UP * radius * 0.72, radius, 8, 0.2)
	mesh.band(neck, bowl_low, iron)
	mesh.band(bowl_low, bowl_top, iron)
	mesh.cap(neck, iron, top + Vector3.UP)
	var embers := mesh.ring(top + Vector3.UP * radius * 0.64, radius * 0.93, 8, 0.2)
	glow.cap(embers, flame.darkened(0.3), top)
	glow.blob(top + Vector3.UP * radius * 1.3, Vector3(radius * 0.7, radius * 1.15, radius * 0.7),
			flame, 5, 3, 0.2)
	glow.blob(top + Vector3.UP * radius * 1.0, Vector3(radius * 0.38, radius * 0.62, radius * 0.38),
			core, 4, 3, 0.15)


## Una piedra parada con el pie en `foot` y una runa que brilla en la cara
## que mira a `toward`. Se inclina un poco al azar.
static func rune_stone(mesh: LowPolyMesh, glow: LowPolyMesh, foot: Vector3, toward: Vector3,
		height: float, width: float, stone: Color, moss: Color, rune: Color,
		rng: RandomNumberGenerator) -> void:
	var facing := Vector3(toward.x - foot.x, 0.0, toward.z - foot.z)
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.BACK
	var side := Vector3(-facing.z, 0.0, facing.x)
	var up := (Vector3.UP + side * rng.randf_range(-0.06, 0.06)
			+ facing * rng.randf_range(-0.08, 0.03)).normalized()
	var depth := width * 0.5
	var center := foot + up * (height * 0.5 - 0.2)
	mesh.block(Transform3D(Basis(side, up, facing), center), Vector3(width, height + 0.4, depth),
			stone)
	var crown := foot + up * (height - 0.2)
	mesh.plate(crown + side * width * 0.46 + facing * depth * 0.4 + up * 0.02,
			crown - side * width * 0.46 + facing * depth * 0.4 + up * 0.02,
			crown - side * width * 0.46 - facing * depth * 0.4 + up * 0.02,
			crown + side * width * 0.46 - facing * depth * 0.4 + up * 0.02, moss, crown - up)
	glyph(glow, center + up * height * 0.12 + facing * (depth * 0.5 + 0.02), facing, up,
			minf(width * 0.42, height * 0.3), rune)


## Una runa que brilla: un rombo con dos trazos, centrada en `center`,
## mirando hacia `normal`, con `up` hacia arriba y `size` metros de alto.
static func glyph(glow: LowPolyMesh, center: Vector3, normal: Vector3, up: Vector3, size: float,
		color: Color) -> void:
	var side := up.cross(normal).normalized()
	var inside := center - normal * 0.1
	var half := size * 0.5
	glow.plate(center + up * half, center + side * half * 0.55, center - up * half,
			center - side * half * 0.55, color, inside)
	for turn: float in [-1.0, 1.0]:
		var tick := center + side * turn * half * 0.9
		glow.plate(tick + up * half * 0.6, tick + side * turn * half * 0.18 + up * half * 0.45,
				tick + side * turn * half * 0.18 - up * half * 0.45, tick - up * half * 0.6,
				color, inside)


## Unas velas de alturas distintas repartidas a `spread` metros de `center`.
static func candles(mesh: LowPolyMesh, glow: LowPolyMesh, center: Vector3, count: int,
		spread: float, wax: Color, flame: Color, rng: RandomNumberGenerator) -> void:
	for index in count:
		var at := center + Vector3(rng.randf_range(-spread, spread), 0.0,
				rng.randf_range(-spread, spread))
		var tall := rng.randf_range(0.14, 0.36)
		var reach := rng.randf_range(0.035, 0.06)
		var low := mesh.ring(at, reach, 6, rng.randf() * TAU)
		var high := mesh.ring(at + Vector3.UP * tall, reach, 6, rng.randf() * TAU)
		mesh.band(low, high, wax)
		mesh.cap(high, wax.lightened(0.12), at)
		glow.blob(at + Vector3.UP * (tall + 0.07), Vector3(0.04, 0.08, 0.04), flame, 4, 3, 0.1)


## Un cristal facetado (dos pirámides unidas por la cintura) con la cintura
## en `center`.
static func crystal(glow: LowPolyMesh, center: Vector3, height: float, radius: float,
		color: Color, sides: int = 6, turn: float = 0.0) -> void:
	var waist := glow.ring(center, radius, sides, turn)
	var top := center + Vector3.UP * height * 0.62
	var bottom := center + Vector3.DOWN * height * 0.38
	for index in sides:
		var next := (index + 1) % sides
		var bright := 0.18 if index % 2 == 0 else 0.0
		glow.triangle(waist[index], waist[next], top, color.lightened(bright), center)
		glow.triangle(waist[index], waist[next], bottom, color.darkened(0.12 + bright * 0.5),
				center)


## Un montón de monedas de oro de `radius` metros con `count` monedas sueltas
## alrededor.
static func coins(mesh: LowPolyMesh, center: Vector3, radius: float, count: int, gold: Color,
		rng: RandomNumberGenerator) -> void:
	mesh.blob(center + Vector3.UP * radius * 0.12, Vector3(radius, radius * 0.42, radius),
			gold.darkened(0.06), 7, 3, 0.2)
	for index in count:
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(radius * 0.6, radius * 1.4)
		var at := center + Vector3(cos(angle) * reach, 0.02 + rng.randf_range(0.0, 0.05),
				sin(angle) * reach)
		var low := mesh.ring(at, 0.075, 6, rng.randf())
		var high := mesh.ring(at + Vector3.UP * 0.025, 0.075, 6, rng.randf())
		mesh.band(low, high, gold.darkened(0.15))
		mesh.cap(high, gold.lightened(0.1), at)


## Manchas de musgo planas, de hasta `size` metros, en cada punto de `spots`.
static func moss(mesh: LowPolyMesh, spots: PackedVector3Array, size: float, color: Color,
		rng: RandomNumberGenerator) -> void:
	for at: Vector3 in spots:
		var patch := mesh.ring(at + Vector3.UP * 0.02, size * rng.randf_range(0.5, 1.0), 6,
				rng.randf() * TAU, 0.3)
		mesh.cap(patch, color.lerp(color.darkened(0.2), rng.randf()), at + Vector3.DOWN)


## Una calavera: el cráneo, la mandíbula y las cuencas que brillan en `eyes`.
## Mira hacia `facing` (plano).
static func skull(mesh: LowPolyMesh, glow: LowPolyMesh, center: Vector3, facing: Vector3,
		size: float, bone: Color, eyes: Color) -> void:
	var front := Vector3(facing.x, 0.0, facing.z).normalized()
	var side := Vector3(-front.z, 0.0, front.x)
	mesh.blob(center, Vector3(size, size * 0.9, size) * 0.5, bone, 7, 4, 0.08)
	mesh.blob(center + front * size * 0.28 + Vector3.DOWN * size * 0.36,
			Vector3(size * 0.34, size * 0.16, size * 0.3), bone.darkened(0.08), 6, 3, 0.05)
	for turn: float in [-1.0, 1.0]:
		glow.blob(center + front * size * 0.42 + side * turn * size * 0.17 + Vector3.UP * size * 0.02,
				Vector3(size * 0.1, size * 0.08, size * 0.06), eyes, 4, 3, 0.05)


## Un puntal: una barra de sección cuadrada de `thickness` metros entre `a` y `b`.
static func strut(mesh: LowPolyMesh, a: Vector3, b: Vector3, thickness: float,
		color: Color) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.01:
		return
	var along := axis / length
	var across := along.cross(Vector3.UP if absf(along.y) < 0.95 else Vector3.RIGHT).normalized()
	var depth := across.cross(along).normalized()
	mesh.block(Transform3D(Basis(across, along, depth), (a + b) * 0.5),
			Vector3(thickness, length, thickness), color)


## Un anillo plano horizontal entre los radios `inner` y `outer` a la altura
## de `center`, mirando hacia arriba.
static func annulus(mesh: LowPolyMesh, center: Vector3, inner: float, outer: float, sides: int,
		color: Color, turn: float = 0.0) -> void:
	var out_ring := mesh.ring(center, outer, sides, turn)
	var in_ring := mesh.ring(center, inner, sides, turn)
	for index in sides:
		var next := (index + 1) % sides
		mesh.plate(out_ring[index], out_ring[next], in_ring[next], in_ring[index], color,
				center + Vector3.DOWN)


## La pared de ADENTRO de un cuenco: las caras entre los anillos `low` y
## `high` (misma cantidad de puntos) mirando hacia el eje.
static func inner_wall(mesh: LowPolyMesh, low: PackedVector3Array, high: PackedVector3Array,
		color: Color) -> void:
	var count := low.size()
	var axis := Vector3.ZERO
	for point: Vector3 in low:
		axis += point
	axis /= float(count)
	for index in count:
		var next := (index + 1) % count
		var middle := (low[index] + low[next] + high[index] + high[next]) * 0.25
		var outward := Vector3(middle.x - axis.x, 0.0, middle.z - axis.z).normalized()
		mesh.plate(low[index], low[next], high[next], high[index], color, middle + outward)


## Cuánto hay que subir o bajar algo de `owner` en el punto local `local`
## para que apoye en el suelo de ahí (0 sin Terrain).
static func ground_offset(owner: Node3D, local: Vector3) -> float:
	var terrain := Terrain.find(owner.get_tree())
	if terrain == null:
		return 0.0
	var spot := owner.to_global(local)
	return terrain.height_at(spot.x, spot.z) - owner.global_position.y
