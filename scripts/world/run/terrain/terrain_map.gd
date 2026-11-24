class_name TerrainMap
extends RefCounted
## La imagen cenital del relieve de un Terrain para el minimapa y el mapa de
## Tab (Terrain.map_image): el tinte del bioma, sombreado por altura. Los
## valores son los exports del Terrain (grupo «Minimapa»); ninguna escena usa
## este script.


## La imagen de `terrain` a `px_per_meter` píxeles por metro (suele ser
## bastante menos que 1: un mapa de 121 px para 240 m es 0.5).
static func image(terrain: Terrain, px_per_meter: float) -> Image:
	var size := terrain.size
	var pixels := maxi(int(round(size * px_per_meter)), 8)
	var out := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	var base := _biome_tint(terrain)
	var span := maxf(terrain.max_height - terrain.min_height, 0.001)
	for py in pixels:
		var z := (float(py) + 0.5) / float(pixels) * size - size * 0.5
		for px in pixels:
			var x := (float(px) + 0.5) / float(pixels) * size - size * 0.5
			# Sombreado por altura: más oscuro en las hondonadas y más claro
			# en las cimas, para que el relieve se lea hasta en 121 px.
			var shade := clampf((terrain.height_at(x, z) - terrain.min_height) / span, 0.0, 1.0)
			var tint := base.lerp(base.lightened(terrain.map_peak_lighten), shade)
			tint = tint.darkened(terrain.map_hollow_darken * (1.0 - shade))
			out.set_pixel(px, py, tint)
	return out


## Tinte del suelo: el ground_color del nodo de backdrop_path, para que el
## mapa se lea como el mismo lugar; Terrain.FALLBACK_MAP_TINT si no lo halla.
static func _biome_tint(terrain: Terrain) -> Color:
	var backdrop := terrain.get_node_or_null(terrain.backdrop_path) \
			if not terrain.backdrop_path.is_empty() else null
	if backdrop != null:
		var value: Variant = backdrop.get("ground_color")
		if value is Color:
			return value
	return Terrain.FALLBACK_MAP_TINT
