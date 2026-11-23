class_name MapDraw
extends RefCounted
## El mapa que comparten TODAS las vistas del HUD: el minimapa y el mapa de Tab
## de cada jugador dibujan el mismo estado. ViewWidgets crea uno solo y lo
## refresca; las vistas (MapView) solo lo leen. Escrito una vez por vista, la
## imagen, la niebla y los marcadores se separarían entre un widget y otro.
##
## Reparto del trabajo:
##   - build_background(arena)  una vez por etapa: la imagen del suelo que
##     arma MapGround (relieve y formaciones de roca), subida a ground_texture.
##   - refresh()                cada refresco de ViewWidgets: sube la niebla a
##     fog_texture si cambió, junta los marcadores y avisa con `refreshed`.
## Ninguno usa un Control, así que un soak headless ejercita todo aunque nada
## se dibuje con el renderizador falso. La niebla se mezcla con el suelo en
## assets/shaders/map_ground.gdshader, no aquí.

## Hay marcadores y niebla nuevos: las vistas se vuelven a dibujar.
signal refreshed

## LA tabla de marcadores. Un nodo aparece en el mapa si está en el grupo
## "map_markers" y su map_marker_kind() devuelve un tipo de esta tabla; un
## tipo que no está aquí no se dibuja (por eso `secret_trigger.gd` deja vacío
## su marker_kind: los secretos siguen secretos).
##   color:          color del marcador.
##   shape:          "dot" | "square" | "triangle" | "diamond".
##   size:           radio en píxeles, antes de la escala de cada vista
##                   (MapView.marker_scale).
##   always_visible: se dibuja aunque la niebla no se haya explorado. Solo el
##                   grupo y la salida: lo demás hay que encontrarlo.
##   pin:            (opcional) el minimapa lo ancla a su orilla cuando queda
##                   fuera de la vista, para saber hacia dónde está.
##   order:          (opcional, por defecto 0) los más altos se dibujan encima.
const MARKER_STYLES: Dictionary[StringName, Dictionary] = {
	&"player": {"color": Color(0.45, 0.95, 1.0), "shape": "triangle",
		"size": 4.5, "always_visible": true, "pin": true, "order": 3},
	&"boss": {"color": Color(0.98, 0.35, 0.2), "shape": "diamond",
		"size": 5.0, "always_visible": false, "pin": true, "order": 2},
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
		"size": 6.0, "always_visible": true, "pin": true, "order": 1},
	# Power-up en el suelo. Se dibuja con el color de su propia fila vía
	# map_marker_color(), para distinguir una estrella de una Furia.
	&"powerup": {"color": Color(0.95, 0.95, 0.4), "shape": "dot",
		"size": 3.0, "always_visible": false},
	# Puestos. Un puesto se dibuja con el color de su tipo
	# vía map_marker_color(), pero solo cuando la niebla ya lo reveló: el mapa
	# no adelanta qué puesto llegó.
	&"vendor": {"color": Color(0.9, 0.75, 0.5), "shape": "square",
		"size": 3.5, "always_visible": false},
	# Bloque de la suerte.
	&"lucky_block": {"color": Color(1.0, 0.6, 0.85), "shape": "square",
		"size": 3.0, "always_visible": false},
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
	&"lucky_block": "Bloques de la suerte",
}

## Tipos que a propósito NO tienen fila en la leyenda: cada uno es una
## VARIANTE de un tipo que ya la tiene, y aquí dice de cuál (un cofre gratis
## es un cofre; un altar demoníaco o de codicia es un altar). Se nombran aquí
## para que el lint de catálogos distinga una omisión a propósito de un
## olvido: cualquier otro tipo sin fila en MARKER_LABELS es un error.
const LEGEND_VARIANTS: Dictionary[StringName, StringName] = {
	&"chest_free": &"chest",
	&"altar_demonic": &"altar",
	&"altar_greed": &"altar",
}

# --- Edita aquí: se crea con .new(), así que no tiene Inspector. -----------
## Color de la flecha de cada jugador, por ranura (J1 a J4). También es el
## color de su fila en el panel «Jugadores» del mapa de Tab.
const PLAYER_COLORS: Array[Color] = [
	Color(0.45, 0.95, 1.0), Color(1.0, 0.66, 0.3),
	Color(0.96, 0.5, 0.9), Color(0.66, 0.95, 0.4),
]
## Contorno de todos los marcadores: color y grosor en píxeles.
const OUTLINE_COLOR: Color = UiTheme.INK
const OUTLINE_WIDTH: float = 1.6
## Anillo alrededor de la flecha de un jugador caído: color, radio como
## múltiplo del tamaño de la flecha y grosor en píxeles.
const DOWNED_RING_COLOR: Color = UiTheme.ACCENT_RED
const DOWNED_RING_RADIUS: float = 2.3
const DOWNED_RING_WIDTH: float = 2.0
## Lados del polígono con que se dibuja un marcador redondo.
const DOT_SIDES: int = 14

## Media extensión, en metros, de la arena que cubre este mapa.
var half_extent: float = 120.0
## La imagen del suelo de la etapa, sin niebla.
var background: Image = null
## La misma imagen como textura. El objeto no cambia entre etapas: las vistas
## lo guardan una vez.
var ground_texture: ImageTexture = ImageTexture.new()
## La niebla de guerra como textura (blanco = explorado). Tampoco cambia de objeto.
var fog_texture: ImageTexture = ImageTexture.new()
## Última instantánea de marcadores, los de más abajo primero: {position
## (Vector2, XZ del mundo), kind, color, heading (radianes, giro del cuerpo),
## slot (jugadores; -1 en el resto), downed (jugador caído)}.
var markers: Array[Dictionary] = []

var _tree: SceneTree = null
## Niebla ya subida a fog_texture: [id del nodo, revisión]. Vacío = hay que subirla.
var _fog_synced: Array = []


func _init(tree: SceneTree) -> void:
	_tree = tree
	# Hasta que exista una niebla, todo cuenta como explorado.
	fog_texture.set_image(_solid_image(Color.WHITE))


## Color de la flecha del jugador de `slot`.
static func player_color(slot: int) -> Color:
	return PLAYER_COLORS[posmod(slot, PLAYER_COLORS.size())]


## Rehace el suelo con la arena de la etapa. Se llama una vez por etapa, desde
## el gancho de etapa de ViewWidgets. Una arena nula no es un error (un HUD
## puede existir antes de la primera): queda una pizarra lisa.
func build_background(_arena: Node3D = null) -> void:
	half_extent = MapGround.arena_half_extent(_tree, half_extent)
	background = MapGround.build(_tree, half_extent)
	ground_texture.set_image(background)
	# La etapa nueva trae su propia niebla: se sube sin mirar la revisión.
	_fog_synced = []
	refresh()


## Pone al día la niebla y los marcadores y avisa a las vistas.
func refresh() -> void:
	sync_fog()
	collect_markers()
	refreshed.emit()


## Sube la niebla a fog_texture si cambió desde la última vez. FogOfWar sube
## su `revision` cada vez que cambia su imagen, así que mismo nodo y misma
## revisión son los mismos píxeles: la mayoría de los refrescos no sube nada.
func sync_fog() -> void:
	var fog := FogOfWar.find(_tree)
	var key: Array = [fog.get_instance_id(), fog.revision] if fog != null else [0, -1]
	if key == _fog_synced:
		return
	_fog_synced = key
	var image: Image = fog.image if fog != null else null
	if image == null:
		image = _solid_image(Color.WHITE)
	if fog_texture.get_size() == Vector2(image.get_size()) \
			and fog_texture.get_format() == image.get_format():
		fog_texture.update(image)
	else:
		fog_texture.set_image(image)


## Instantánea de cada marcador vivo, filtrada por la niebla. Los jugadores
## y el portal de salida siempre están; lo demás hay que haberlo encontrado.
func collect_markers() -> void:
	var found: Array[Dictionary] = []
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
		var slot := -1
		if kind == &"player":
			slot = int(body.get("player_index"))
			color = player_color(slot)
		elif body.has_method(&"map_marker_color"):
			color = body.call(&"map_marker_color")
		found.append({
			"position": at,
			"kind": kind,
			"color": color,
			# Giro del cuerpo: la flecha de un jugador apunta hacia donde mira.
			"heading": body.global_rotation.y,
			"slot": slot,
			"downed": body.is_in_group(&"downed_players"),
		})
	found.sort_custom(_draws_below)
	markers = found


func marker_count() -> int:
	return markers.size()


## Tipos con fila de leyenda que tienen algún marcador a la vista ahora, en el
## orden de MARKER_LABELS. Una variante cuenta como su familia.
func legend_kinds() -> Array[StringName]:
	var present: Dictionary[StringName, bool] = {}
	for marker: Dictionary in markers:
		var kind: StringName = marker["kind"]
		present[LEGEND_VARIANTS.get(kind, kind)] = true
	var kinds: Array[StringName] = []
	for kind: StringName in MARKER_LABELS:
		if present.has(kind):
			kinds.append(kind)
	return kinds


## XZ del mundo -> UV de la imagen del suelo (0-1), con el norte arriba.
func world_to_uv(xz: Vector2) -> Vector2:
	var span := maxf(half_extent * 2.0, 0.001)
	return (xz + Vector2(half_extent, half_extent)) / span


## Hacia dónde apunta en un mapa con el norte arriba un cuerpo con giro `yaw`
## (rotation.y): un cuerpo camina hacia su -Z local, que con giro 0 es el norte.
static func facing_of(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## Dibuja un marcador en `canvas`: la forma rellena y su contorno de tinta.
## `radius` va en píxeles y `facing` es hacia dónde apunta en pantalla (solo
## lo usa la flecha, "triangle").
static func draw_glyph(canvas: CanvasItem, at: Vector2, shape: String, color: Color,
		radius: float, facing: Vector2 = Vector2.UP) -> void:
	var points := _glyph_points(at, shape, radius, facing)
	canvas.draw_colored_polygon(points, color)
	points.append(points[0])
	canvas.draw_polyline(points, OUTLINE_COLOR, OUTLINE_WIDTH, true)


## Anillo de "caído" alrededor de la flecha de un jugador.
static func draw_downed_ring(canvas: CanvasItem, at: Vector2, radius: float) -> void:
	canvas.draw_arc(at, radius * DOWNED_RING_RADIUS, 0.0, TAU, 24, DOWNED_RING_COLOR,
			DOWNED_RING_WIDTH, true)


static func _glyph_points(at: Vector2, shape: String, radius: float,
		facing: Vector2) -> PackedVector2Array:
	match shape:
		"square":
			return PackedVector2Array([
					at + Vector2(-radius, -radius), at + Vector2(radius, -radius),
					at + Vector2(radius, radius), at + Vector2(-radius, radius)])
		"diamond":
			var reach := radius * 1.25
			return PackedVector2Array([
					at + Vector2(0.0, -reach), at + Vector2(reach, 0.0),
					at + Vector2(0.0, reach), at + Vector2(-reach, 0.0)])
		"triangle":
			# Punta de flecha con muesca atrás: se lee hacia dónde apunta aunque
			# sea chica.
			var side := Vector2(-facing.y, facing.x)
			return PackedVector2Array([
					at + facing * radius * 1.7,
					at - facing * radius * 1.15 + side * radius * 1.2,
					at - facing * radius * 0.45,
					at - facing * radius * 1.15 - side * radius * 1.2])
	var points := PackedVector2Array()
	for step in DOT_SIDES:
		points.append(at + Vector2.from_angle(TAU * float(step) / float(DOT_SIDES)) * radius)
	return points


## Orden de dibujo: primero los de `order` más bajo.
static func _draws_below(a: Dictionary, b: Dictionary) -> bool:
	return _order_of(a) < _order_of(b)


static func _order_of(marker: Dictionary) -> int:
	var style: Dictionary = MARKER_STYLES[marker["kind"] as StringName]
	return int(style.get("order", 0))


## Imagen de un solo píxel, para una textura sin contenido todavía.
func _solid_image(color: Color) -> Image:
	var image := Image.create_empty(1, 1, false, Image.FORMAT_L8)
	image.fill(color)
	return image
