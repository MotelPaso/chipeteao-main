class_name FogOfWar
extends Node
## Niebla de guerra: lo que la party VIO de la etapa actual. Es hijo de
## RunSystems.tscn, así sobrevive al cambio de arena como el resto del bloque
## de la partida, y el WorldDirector la reinicia en cada etapa.
##
## Compartida por toda la party a propósito: en co-op, cuatro raiders en
## cuatro esquinas exploran UN mapa. Solo dura la partida.
##
## El estado es una Image L8 de un canal: 255 explorado, 0 desconocido. Se
## pinta un disco por raider vivo en un tick lento, barato de dejar corriendo
## (una imagen de 120x120 y un radio de 9 píxeles son unos cientos de
## set_pixel cada quinto de segundo) y lo bastante preciso para que el mapa
## se lea como "por donde caminamos".
##
## MapDraw lo compone en la imagen que dibujan el minimapa y el mapa de Tab;
## nada fuera de este nodo escribe la imagen, y por eso `revision` puede
## representar su contenido.

@export_group("Niebla")
## Metros por píxel de niebla. 2 m da 120x120 en una arena de 240 m: lo
## bastante grueso para pintar barato y fino para que un pasillo entre dos
## manchas de máscara se lea como explorado.
@export var meters_per_pixel: float = 2.0
## Cuánto revela un raider a su alrededor, en metros.
@export var reveal_radius: float = 18.0
## Segundos entre pasadas de pintura. No por frame: caminando, un raider
## recorre menos de un metro en este tiempo, un tercio de píxel de niebla.
@export var paint_interval: float = 0.2
@export_group("")

## El estado de verdad. FORMAT_L8: un byte por píxel, sin alfa; MapDraw lo
## convierte en algo dibujable.
var image: Image = null

## Sube cada vez que cambia `image`: una imagen nueva en _rebuild o un
## reveal_at que cambió al menos un píxel. Nunca se reinicia ni sube por otra
## cosa, así "mismo nodo de niebla, misma revisión" significa "mismos
## píxeles". El minimapa y el mapa de Tab cachean su MapDraw.composite() con
## esto (Minimap.composite_key) en vez de rearmar la misma imagen.
var revision: int = 0

var _pixels: int = 0
## Media extensión, en metros, de la arena que cubre la imagen actual.
var _half_extent: float = 120.0
var _paint_left: float = 0.0
## Píxeles explorados, llevados como cuenta corrida para que
## explored_fraction() no recorra toda la imagen en cada refresco del HUD.
var _explored_pixels: int = 0


## EL acceso, como toda búsqueda entre escenas de este proyecto.
static func find(tree: SceneTree) -> FogOfWar:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"fog") as FogOfWar


func _ready() -> void:
	add_to_group(&"fog")
	# Una niebla sin arena todavía es niebla de nada; reset_for_stage arma la
	# real cuando empieza la etapa.
	_rebuild(_half_extent)


## Gancho de etapa que llama WorldDirector.on_stage_started — NO la señal
## stage_changed: esa llega después de colocar la arena, y el minimapa quiere
## una niebla limpia en cuanto existe el mapa. La etapa 0 pasa por la misma
## llamada, sin caso especial.
func reset_for_stage(arena: Node3D) -> void:
	var half := _half_extent
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and (arena == null or arena.is_ancestor_of(bounds)):
		var value: Variant = bounds.get("arena_half_extent")
		if value != null:
			half = float(value)
	_rebuild(half)


func _rebuild(half_extent: float) -> void:
	_half_extent = half_extent
	_pixels = maxi(int(round(half_extent * 2.0 / maxf(meters_per_pixel, 0.5))), 8)
	image = Image.create_empty(_pixels, _pixels, false, Image.FORMAT_L8)
	image.fill(Color(0.0, 0.0, 0.0))
	_explored_pixels = 0
	_paint_left = 0.0
	revision += 1


func _physics_process(delta: float) -> void:
	if image == null:
		return
	_paint_left -= delta
	if _paint_left > 0.0:
		return
	_paint_left = paint_interval
	# Los derribados también revelan: su cuerpo sigue ahí y la party ve el
	# suelo alrededor de un compañero caído.
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null:
				reveal_at(Vector2(body.global_position.x, body.global_position.z))


## Pinta un disco de suelo explorado. Pública para poder revelar desde un
## lugar donde no hay nadie.
func reveal_at(center_xz: Vector2) -> void:
	if image == null:
		return
	var center_px := _to_pixel(center_xz)
	var radius := int(ceil(reveal_radius / maxf(meters_per_pixel, 0.5)))
	var radius_sq := radius * radius
	var explored_before := _explored_pixels
	for dy in range(-radius, radius + 1):
		var py := center_px.y + dy
		if py < 0 or py >= _pixels:
			continue
		for dx in range(-radius, radius + 1):
			var px := center_px.x + dx
			if px < 0 or px >= _pixels:
				continue
			if dx * dx + dy * dy > radius_sq:
				continue
			# Se cuenta aquí, una vez por píxel, para que explored_fraction()
			# no tenga que recorrer toda la imagen.
			if image.get_pixel(px, py).r < 0.5:
				_explored_pixels += 1
				image.set_pixel(px, py, Color(1.0, 1.0, 1.0))
	# Una vez por llamada, no por píxel: al consumidor le basta "no es lo
	# que viste". La cuenta solo se mueve si corrió un set_pixel, así un
	# disco sobre suelo ya explorado no la cambia.
	if _explored_pixels != explored_before:
		revision += 1


## True si la party estuvo cerca de esta posición plana.
func is_explored(xz: Vector2) -> bool:
	if image == null:
		return false
	var px := _to_pixel(xz)
	if px.x < 0 or px.y < 0 or px.x >= _pixels or px.y >= _pixels:
		return false
	return image.get_pixel(px.x, px.y).r >= 0.5


## Fracción 0-1 de la etapa que descubrió la party. La lee el soak.
func explored_fraction() -> float:
	if image == null or _pixels <= 0:
		return 0.0
	return float(_explored_pixels) / float(_pixels * _pixels)


## Tamaño de la imagen de niebla en píxeles (MapDraw escala su composición a él).
func pixels() -> int:
	return _pixels


## Media extensión, en metros, de la arena que cubre esta niebla.
func half_extent() -> float:
	return _half_extent


func _to_pixel(xz: Vector2) -> Vector2i:
	var scale := float(_pixels) / maxf(_half_extent * 2.0, 0.001)
	return Vector2i(
			int(floor((xz.x + _half_extent) * scale)),
			int(floor((xz.y + _half_extent) * scale)))
