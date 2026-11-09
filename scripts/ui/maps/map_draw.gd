class_name MapDraw
extends RefCounted
## El mapa que dibujan el minimapa y el mapa de Tab. Un ayudante, dos
## consumidores: la imagen, la niebla y los marcadores son idénticos para un
## widget de 150 px en una esquina y un mapa de media pantalla, y escribirlos
## dos veces es cómo se separarían.
##
## Reparto del trabajo:
##   - build_background(arena)  una vez por etapa: la imagen del terreno,
##     oscurecida donde la máscara de la arena bloquea el suelo.
##   - composite()              en el tick de la niebla: fondo por niebla en
##     una textura RGBA8 que el consumidor solo copia.
##   - collect_markers()        cada 0.1 s: quién está dónde, filtrado por lo
##     que la niebla ya reveló.
## Ninguno usa un Control, así que un soak headless ejercita todo aunque
## _draw() nunca se despache con el renderizador falso.

## LA tabla de marcadores. Un nodo aparece en el mapa si está en el grupo
## "map_markers" y su map_marker_kind() devuelve un tipo de esta tabla; un
## tipo que no está aquí no se dibuja (por eso `secret_trigger.gd` deja vacío
## su marker_kind: los secretos siguen secretos).
##   color:          color del marcador.
##   shape:          "dot" | "square" | "triangle" | "diamond".
##   size:           radio en píxeles del mapa, a la escala del mapa de Tab.
##   always_visible: se dibuja aunque la niebla no se haya explorado. Solo el
##                   grupo y la salida: lo demás hay que encontrarlo.
const MARKER_STYLES: Dictionary[StringName, Dictionary] = {
	&"player": {"color": Color(0.45, 0.95, 1.0), "shape": "triangle",
		"size": 4.0, "always_visible": true},
	&"boss": {"color": Color(0.98, 0.35, 0.2), "shape": "diamond",
		"size": 5.0, "always_visible": false},
	&"chest": {"color": Color(1.0, 0.82, 0.35), "shape": "square",
		"size": 3.0, "always_visible": false},
	&"chest_free": {"color": Color(1.0, 0.93, 0.72), "shape": "square",
		"size": 3.0, "always_visible": false},
	&"altar": {"color": Color(0.4, 0.8, 1.0), "shape": "dot",
		"size": 3.5, "always_visible": false},
	&"altar_demonic": {"color": Color(1.0, 0.3, 0.25), "shape": "dot",
		"size": 3.5, "always_visible": false},
	&"altar_greed": {"color": Color(0.85, 0.55, 0.95), "shape": "dot",
		"size": 3.5, "always_visible": false},
	&"spring": {"color": Color(0.4, 0.9, 0.75), "shape": "dot",
		"size": 3.0, "always_visible": false},
	&"roulette": {"color": Color(0.95, 0.7, 0.3), "shape": "diamond",
		"size": 3.5, "always_visible": false},
	&"portal": {"color": Color(0.6, 0.85, 1.0), "shape": "diamond",
		"size": 3.0, "always_visible": false},
	&"exit": {"color": Color(1.0, 0.82, 0.35), "shape": "diamond",
		"size": 6.0, "always_visible": true},
	# Power-up en el suelo. Se dibuja con el color de su propia fila vía
	# map_marker_color(), para distinguir una estrella de una Furia.
	&"powerup": {"color": Color(0.95, 0.95, 0.4), "shape": "dot",
		"size": 3.0, "always_visible": false},
	# Puestos y caja de mascota. Un puesto se dibuja con el color de su tipo
	# vía map_marker_color(), pero solo cuando la niebla ya lo reveló: el mapa
	# no adelanta qué puesto llegó.
	&"vendor": {"color": Color(0.9, 0.75, 0.5), "shape": "square",
		"size": 3.5, "always_visible": false},
	&"pet_box": {"color": Color(0.7, 0.95, 0.6), "shape": "square",
		"size": 3.5, "always_visible": false},
	# Bloque de la suerte y altar de eventos.
	&"lucky_block": {"color": Color(1.0, 0.6, 0.85), "shape": "square",
		"size": 3.0, "always_visible": false},
	&"event_altar": {"color": Color(0.8, 0.85, 1.0), "shape": "dot",
		"size": 3.5, "always_visible": false},
}

## Nombre para el jugador por tipo, para la leyenda del mapa de Tab.
const MARKER_LABELS: Dictionary[StringName, String] = {
	&"player": "Jugadores",
	&"boss": "Jefe",
	&"chest": "Cofres",
	&"altar": "Altares",
	&"spring": "Manantial",
	&"roulette": "Ruleta",
	&"portal": "Portales",
	&"exit": "Salida",
	&"powerup": "Power-ups",
	&"vendor": "Vendedores",
	&"pet_box": "Cajas de mascotas",
	&"event_altar": "Altares de eventos",
	&"lucky_block": "Bloques de la suerte",
}

## Tipos que a propósito NO tienen fila en la leyenda: cada uno es una
## VARIANTE de un tipo que ya la tiene (un cofre gratis es un cofre; un altar
## demoníaco o de codicia es un altar). Se nombran aquí para que el lint de
## catálogos distinga una omisión a propósito de un olvido: cualquier otro
## tipo sin fila en MARKER_LABELS es un error.
const LEGEND_VARIANTS: Dictionary[StringName, bool] = {
	&"chest_free": true,
	&"altar_demonic": true,
	&"altar_greed": true,
}

## Cuánto se oscurece el suelo sin explorar en la composición (0-1). No es
## opaco del todo: la forma del mapa es una pista, lo que hay ENCIMA es el premio.
const FOG_ALPHA: float = 0.85
## Píxeles del mapa por metro de arena. 0.5 da 120 px para una arena de
## 240 m; el minimapa (150 px) y el mapa de Tab estiran esa imagen a su tamaño.
const PIXELS_PER_METER: float = 0.5
## Color liso del fondo del mapa cuando la arena no tiene Terrain y no hay
## relieve que dibujar.
const PLAIN_BACKGROUND: Color = Color(0.16, 0.17, 0.2)
## Cuánto se oscurecen en el mapa las celdas que la máscara de la arena
## bloquea (0-1).
const BLOCKED_DARKEN: float = 0.55

## Media extensión, en metros, de la arena que cubre este mapa.
var half_extent: float = 120.0
## La imagen del suelo de la etapa, antes de la niebla.
var background: Image = null
## Fondo por niebla, listo para dibujar.
var texture: ImageTexture = null
## Última instantánea de marcadores: {position: Vector2 (XZ del mundo),
## kind, color, heading (radianes, solo jugadores)}.
var markers: Array[Dictionary] = []

var _composite: Image = null
var _tree: SceneTree = null


func _init(tree: SceneTree) -> void:
	_tree = tree


## Construye la imagen del suelo de la etapa. Se llama una vez por etapa,
## desde el gancho de etapa del consumidor. Un terreno nulo no es un error
## (un HUD puede existir antes de la primera arena): queda una pizarra plana
## sobre la que la composición igual funciona.
func build_background(_arena: Node3D = null) -> void:
	var terrain := Terrain.find(_tree)
	var bounds := _tree.get_first_node_in_group(&"arena_bounds")
	if bounds != null:
		var value: Variant = bounds.get("arena_half_extent")
		if value != null:
			half_extent = float(value)
	if terrain != null:
		terrain.ensure_built()
		half_extent = terrain.size * 0.5
		background = terrain.map_image(PIXELS_PER_METER)
	else:
		var pixels := maxi(int(round(half_extent * 2.0 * PIXELS_PER_METER)), 8)
		background = Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
		background.fill(PLAIN_BACKGROUND)
	_darken_blocked_cells(bounds)
	composite()


## Oscurece las celdas bloqueadas de la máscara de la arena, para que el mapa
## muestre la forma irregular de la etapa y no un cuadrado limpio. Se decide
## por PÍXEL, según la celda donde cae su centro: una celda puede medir una
## fracción de píxeles (5 m a 0.5 px/m son 2.5 px), y pintar cuadrados
## redondeados por celda dejaría franjas más oscuras donde se solapan.
func _darken_blocked_cells(bounds: Node) -> void:
	if bounds == null or background == null or not bounds.has_method(&"blocked_cells"):
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
	var pixels := background.get_width()
	var meters := half_extent * 2.0 / float(pixels)
	for py in pixels:
		var row := floori((-half_extent + (float(py) + 0.5) * meters - corner.y) / cell_size)
		for px in pixels:
			var column := floori((-half_extent + (float(px) + 0.5) * meters - corner.x) / cell_size)
			if blocked.has(Vector2i(column, row)):
				background.set_pixel(px, py, background.get_pixel(px, py).darkened(BLOCKED_DARKEN))


## Fondo por niebla en la textura dibujable. El consumidor lo llama en el
## tick de la niebla, nunca cada cuadro.
func composite() -> void:
	if background == null:
		return
	var pixels := background.get_width()
	if _composite == null or _composite.get_width() != pixels:
		_composite = Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	var fog := FogOfWar.find(_tree)
	var fog_image: Image = fog.image if fog != null else null
	var fog_pixels := fog.pixels() if fog != null else 0
	for py in pixels:
		for px in pixels:
			var tint := background.get_pixel(px, py)
			if fog_image != null and fog_pixels > 0:
				# Píxel de niebla más cercano: la grilla de niebla es más gruesa
				# que el mapa, e interpolar un estado binario solo emborrona su borde.
				var fx := mini(px * fog_pixels / pixels, fog_pixels - 1)
				var fy := mini(py * fog_pixels / pixels, fog_pixels - 1)
				if fog_image.get_pixel(fx, fy).r < 0.5:
					tint = tint.darkened(FOG_ALPHA)
			_composite.set_pixel(px, py, tint)
	if texture == null:
		texture = ImageTexture.create_from_image(_composite)
	else:
		texture.update(_composite)


## Instantánea de cada marcador vivo, filtrada por la niebla. Los jugadores
## y el portal de salida siempre están; lo demás hay que haberlo encontrado.
func collect_markers() -> void:
	markers = []
	var fog := FogOfWar.find(_tree)
	for node: Node in _tree.get_nodes_in_group(&"map_markers"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if not body.has_method(&"map_marker_kind"):
			continue
		var kind: StringName = body.call(&"map_marker_kind")
		if kind.is_empty() or not MARKER_STYLES.has(kind):
			continue
		# Un altar gastado o un cofre abierto no son un lugar adonde ir.
		var available: Variant = body.get("available")
		if available is bool and not bool(available):
			continue
		var at := Vector2(body.global_position.x, body.global_position.z)
		var style: Dictionary = MARKER_STYLES[kind]
		if not bool(style["always_visible"]) and fog != null and not fog.is_explored(at):
			continue
		var color: Color = style["color"]
		if body.has_method(&"map_marker_color"):
			color = body.call(&"map_marker_color")
		markers.append({
			"position": at,
			"kind": kind,
			"color": color,
			# Los jugadores se dibujan como una flecha hacia donde miran; los
			# demás ignoran este campo.
			"heading": body.global_rotation.y,
		})


func marker_count() -> int:
	return markers.size()


## XZ del mundo -> un punto dentro de `rect`, con el norte arriba. LA
## proyección que usan ambos consumidores, para que un marcador nunca caiga
## donde no está el suelo.
func to_screen(xz: Vector2, rect: Rect2) -> Vector2:
	var span := maxf(half_extent * 2.0, 0.001)
	return rect.position + Vector2(
			(xz.x + half_extent) / span * rect.size.x,
			(xz.y + half_extent) / span * rect.size.y)


## Dibuja la composición y cada marcador dentro de `rect` de `canvas`. Ambos
## consumidores lo llaman desde su propio _draw; todo lo que necesita ya lo
## calcularon los métodos de arriba.
func draw_into(canvas: CanvasItem, rect: Rect2, marker_scale: float = 1.0) -> void:
	if texture != null:
		canvas.draw_texture_rect(texture, rect, false)
	for marker: Dictionary in markers:
		var at := to_screen(marker["position"], rect)
		var style: Dictionary = MARKER_STYLES[marker["kind"] as StringName]
		var size: float = float(style["size"]) * marker_scale
		var color: Color = marker["color"]
		match String(style["shape"]):
			"square":
				canvas.draw_rect(Rect2(at - Vector2(size, size), Vector2(size, size) * 2.0),
						color, true)
			"diamond":
				canvas.draw_colored_polygon(PackedVector2Array([
						at + Vector2(0.0, -size), at + Vector2(size, 0.0),
						at + Vector2(0.0, size), at + Vector2(-size, 0.0)]), color)
			"triangle":
				var heading: float = marker["heading"]
				# La flecha del jugador apunta hacia donde mira: en un mapa de
				# 240 m, saber hacia dónde miras es casi todo el valor.
				var tip := at + Vector2(sin(heading), -cos(heading)) * size * 1.6
				var left := at + Vector2(sin(heading + 2.4), -cos(heading + 2.4)) * size
				var right := at + Vector2(sin(heading - 2.4), -cos(heading - 2.4)) * size
				canvas.draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
			_:
				canvas.draw_circle(at, size, color)
