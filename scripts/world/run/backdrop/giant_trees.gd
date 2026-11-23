class_name GiantTrees
extends RefCounted
## Los ÁRBOLES COLOSALES del horizonte: troncos de más de cien metros que
## rodean la arena por fuera, con la copa asomando sobre la niebla. Hacen
## que el bosque se sienta enorme desde cualquier punto del mapa. Son una
## sola malla sin colisión, hija del Backdrop.
##
## Cuántos, qué tan altos y de qué color son exports del Backdrop (grupo
## «Árboles colosales»): se cambian en la arena, no aquí.

## Lados del tronco y copas menores alrededor de la copa principal.
const TRUNK_SIDES: int = 8
const SATELLITES: int = 5
## El tronco, de abajo arriba: (altura en fracción del árbol, radio en
## fracción del de la base). Arranca bajo el suelo lejano.
const TRUNK: Array[Vector2] = [Vector2(-0.06, 1.9), Vector2(0.05, 1.2), Vector2(0.28, 0.86),
		Vector2(0.58, 0.7), Vector2(0.84, 0.58)]


## La malla de `count` árboles repartidos en el anillo `ring` (distancia al
## centro, mínima y máxima, en metros), con alturas entre las dos de
## `height`, el tronco de radio `trunk` en la base y la copa de radio `crown`.
static func build(rng: RandomNumberGenerator, count: int, ring: Vector2, height: Vector2,
		trunk: float, crown: float, bark: Color, leaf_dark: Color,
		leaf_bright: Color) -> MeshInstance3D:
	var mesh := LowPolyMesh.new(int(rng.seed))
	for index in count:
		var angle := TAU * (float(index) + rng.randf_range(-0.3, 0.3)) / float(count)
		var distance := rng.randf_range(ring.x, ring.y)
		var foot := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var tall := rng.randf_range(height.x, height.y)
		var girth := trunk * rng.randf_range(0.85, 1.2)
		var spread := crown * rng.randf_range(0.85, 1.15)
		var turn := rng.randf() * TAU
		# El tronco se inclina apenas: ninguno queda a plomo.
		var lean := Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05)) * tall
		var lower := PackedVector3Array()
		for step in TRUNK.size():
			var at := foot + Vector3.UP * (TRUNK[step].x * tall) + lean * maxf(TRUNK[step].x, 0.0)
			var upper := mesh.ring(at, girth * TRUNK[step].y, TRUNK_SIDES, turn, 0.08)
			if step > 0:
				mesh.band(lower, upper, bark)
			lower = upper
		var top := foot + lean * 0.9 + Vector3.UP * (tall * 0.9)
		mesh.blob(top, Vector3(spread, spread * 0.4, spread), leaf_dark, 8, 4, 0.16)
		for satellite in SATELLITES:
			var around := turn + TAU * (float(satellite) + rng.randf_range(-0.25, 0.25)) \
					/ float(SATELLITES)
			var reach := spread * rng.randf_range(0.5, 0.72)
			var size := spread * rng.randf_range(0.5, 0.68)
			var center := top + Vector3(cos(around) * reach,
					tall * rng.randf_range(-0.1, 0.03), sin(around) * reach)
			mesh.blob(center, Vector3(size, size * 0.42, size),
					leaf_dark.lerp(leaf_bright, rng.randf()), 7, 4, 0.18)
	var view := mesh.instance("Giants")
	# Material propio: HellSky tiñe los materiales del Backdrop, y el
	# compartido de LowPolyMesh es el de todo lo que se arma en código.
	view.material_override = LowPolyMesh.MATERIAL.duplicate()
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view
