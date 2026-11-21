class_name MapGround
extends RefCounted
## La imagen del suelo que muestran el minimapa y el mapa de Tab: el relieve de
## la etapa (Terrain.map_image, el tinte del bioma sombreado por altura) con
## las formaciones de roca pintadas encima. MapDraw la pide una vez por etapa;
## la niebla no va aquí, la pone el shader map_ground.

# --- Edita aquí: nunca va en una escena, así que no tiene Inspector. --------
## Píxeles de la imagen por metro de arena. 1.0 da 240 px para una arena de
## 240 m; las vistas estiran esa imagen a su tamaño.
const PIXELS_PER_METER: float = 1.0
## Color liso del suelo cuando la arena no tiene Terrain y no hay relieve.
const PLAIN_BACKGROUND: Color = Color(0.16, 0.17, 0.2)
## Color de las formaciones de roca cuando el scatter no trae formation_style.
const ROCK_FALLBACK_COLOR: Color = Color(0.31, 0.32, 0.35)
## Cuánto del color de roca toma el suelo de una celda bloqueada (0-1).
const ROCK_BLEND: float = 0.82
## Cuánto se oscurece el contorno de cada formación (0-1).
const ROCK_OUTLINE_DARKEN: float = 0.45
## Dónde empieza la roca entre una celda abierta (0) y una bloqueada (1). En
## 0.5 el borde cae justo en la frontera de la celda; más bajo, la roca se
## dibuja más gorda, como la formación real, que sobresale de sus celdas.
const ROCK_EDGE: float = 0.38


## Media extensión, en metros, de la arena viva; `fallback` si todavía no hay
## ninguna (un HUD puede existir antes de la primera arena).
static func arena_half_extent(tree: SceneTree, fallback: float) -> float:
	var terrain := Terrain.find(tree)
	if terrain != null:
		terrain.ensure_built()
		return terrain.size * 0.5
	var bounds := tree.get_first_node_in_group(&"arena_bounds")
	if bounds != null:
		var value: Variant = bounds.get("arena_half_extent")
		if value != null:
			return float(value)
	return fallback


## La imagen del suelo de la arena viva, de `half_extent` metros de media
## extensión. Sin terreno queda una pizarra lisa: no es un error.
static func build(tree: SceneTree, half_extent: float) -> Image:
	var terrain := Terrain.find(tree)
	var image: Image
	if terrain != null:
		terrain.ensure_built()
		image = terrain.map_image(PIXELS_PER_METER)
	else:
		var pixels := maxi(int(round(half_extent * 2.0 * PIXELS_PER_METER)), 8)
		image = Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
		image.fill(PLAIN_BACKGROUND)
	_paint_rocks(image, half_extent, tree.get_first_node_in_group(&"arena_bounds"))
	return image


## Pinta las formaciones de roca: las celdas que la máscara de la arena
## bloquea, con el color de roca del bioma, el borde redondeado y un contorno
## oscuro. Recorre solo los píxeles cercanos a una celda bloqueada.
static func _paint_rocks(image: Image, half_extent: float, bounds: Node) -> void:
	if bounds == null or not bounds.has_method(&"blocked_cells"):
		return
	var cells: Variant = bounds.call(&"blocked_cells")
	if cells is not Array:
		return
	var blocked: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		blocked[cell] = true
	if blocked.is_empty():
		return
	var cell_size := float(bounds.call(&"cell_size")) if bounds.has_method(&"cell_size") else 10.0
	# El origen de la propia grilla, con la aritmética del scatter, para que
	# los dos nunca discrepen sobre dónde empieza una celda.
	var corner: Vector2 = bounds.call(&"cell_center", Vector2i.ZERO)
	corner -= Vector2.ONE * cell_size * 0.5
	var rock := _rock_color(bounds)
	var pixels := image.get_width()
	var meters := half_extent * 2.0 / float(pixels)
	var visited := PackedByteArray()
	visited.resize(pixels * pixels)
	for cell: Vector2i in blocked:
		# Los píxeles de la celda más media celda de margen: hasta ahí llega su
		# borde redondeado.
		var low := (corner + (Vector2(cell) - Vector2(0.5, 0.5)) * cell_size
				+ Vector2(half_extent, half_extent)) / meters
		var high := low + Vector2(2.0, 2.0) * cell_size / meters
		for py in range(clampi(floori(low.y), 0, pixels), clampi(ceili(high.y), 0, pixels)):
			for px in range(clampi(floori(low.x), 0, pixels), clampi(ceili(high.x), 0, pixels)):
				if visited[py * pixels + px] == 1:
					continue
				visited[py * pixels + px] = 1
				var at := Vector2(float(px) + 0.5, float(py) + 0.5) * meters \
						- Vector2(half_extent, half_extent)
				var cover := _rock_cover(blocked, (at - corner) / cell_size - Vector2(0.5, 0.5))
				if cover > ROCK_EDGE - 0.16:
					image.set_pixel(px, py, _rock_tint(image.get_pixel(px, py), rock, cover))


## Cuánta roca hay en un punto (0-1), interpolando entre los cuatro centros de
## celda que lo rodean: así una formación se ve como una mancha de borde
## redondo y no como una escalera de cuadrados de 5 m. `at` va en celdas, con
## los centros en coordenadas enteras.
static func _rock_cover(blocked: Dictionary[Vector2i, bool], at: Vector2) -> float:
	var base := Vector2i(floori(at.x), floori(at.y))
	var blend := at - Vector2(base)
	var top := lerpf(float(blocked.has(base)), float(blocked.has(base + Vector2i.RIGHT)), blend.x)
	var bottom := lerpf(float(blocked.has(base + Vector2i.DOWN)),
			float(blocked.has(base + Vector2i.ONE)), blend.x)
	return lerpf(top, bottom, blend.y)


## El suelo `ground` con `cover` de roca encima: el color de roca por dentro
## y una banda oscura a caballo del borde, el contorno de la formación.
static func _rock_tint(ground: Color, rock: Color, cover: float) -> Color:
	var tint := ground.lerp(rock,
			smoothstep(ROCK_EDGE - 0.06, ROCK_EDGE + 0.06, cover) * ROCK_BLEND)
	var rim := smoothstep(ROCK_EDGE - 0.16, ROCK_EDGE - 0.02, cover) \
			* (1.0 - smoothstep(ROCK_EDGE + 0.06, ROCK_EDGE + 0.22, cover))
	return tint.darkened(rim * ROCK_OUTLINE_DARKEN)


## Color de roca del bioma: el del formation_style del scatter, para que el
## mapa se lea como el mismo lugar.
static func _rock_color(bounds: Node) -> Color:
	var style: Variant = bounds.get("formation_style")
	if style is RockFormationStyle:
		return (style as RockFormationStyle).rock_color
	return ROCK_FALLBACK_COLOR
