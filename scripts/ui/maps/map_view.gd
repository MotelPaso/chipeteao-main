class_name MapView
extends Control
## Una vista del mapa compartido (MapDraw). El hijo Ground dibuja el suelo con
## su niebla (shader map_ground) y el hijo Markers los marcadores encima. El
## minimapa usa una (redonda, centrada en su jugador, con zoom) y el mapa de
## Tab otra (cuadrada, con toda la arena y el norte arriba).
##
## Quien la usa le pasa el mapa con set_map y, si la vista se mueve o gira,
## el centro y el giro con look_at_world. La vista siempre es cuadrada: usa el
## cuadrado más grande que cabe en su rectángulo.

const GROUND_SHADER := preload("res://assets/shaders/map_ground.gdshader")

@export_group("Vista")
## Metros de mundo desde el centro de la vista hasta su orilla. 0 muestra
## toda la arena.
@export var view_radius: float = 0.0
## Recorta la vista en un círculo.
@export var round_view: bool = false
## Ancla a la orilla los marcadores importantes que quedan fuera de la vista
## (los que tienen `pin` en MapDraw.MARKER_STYLES): jugadores, jefe y salida.
@export var pin_offscreen: bool = false
## Distancia entre la orilla de la vista y un marcador anclado, en píxeles.
@export var pin_margin: float = 9.0
@export_group("Marcadores")
## Escala de los marcadores sobre el `size` de MapDraw.MARKER_STYLES.
@export var marker_scale: float = 1.0
## Lado de la vista, en píxeles, para el que vale esa escala: en una vista más
## chica los marcadores se achican en proporción, hasta `min_marker_shrink`.
## 0 deja la escala fija.
@export var marker_reference_side: float = 0.0
## Lo más que se achican los marcadores en una vista chica (fracción de su tamaño).
@export_range(0.1, 1.0) var min_marker_shrink: float = 0.7
## Cuánto más grande se dibuja la flecha del jugador dueño de la vista.
@export var own_arrow_scale: float = 1.35
## Radio del halo bajo esa flecha (para encontrarse de un vistazo), como
## múltiplo del tamaño de la flecha.
@export var own_halo_radius: float = 2.6
## Opacidad del halo bajo la flecha propia (0 lo quita).
@export_range(0.0, 1.0) var own_halo_alpha: float = 0.22
## Escala de un marcador anclado a la orilla.
@export var pinned_scale: float = 0.85
## Escribe "J2" junto a la flecha de cada jugador (solo en co-op).
@export var show_player_tags: bool = false
## Tamaño de letra de esas etiquetas, en píxeles.
@export var tag_font_size: int = 13
## Grosor del contorno de esas etiquetas, en píxeles.
@export var tag_outline: int = 5
@export_group("Suelo")
## Color hacia el que se va el suelo que nadie exploró.
@export var unexplored_color: Color = Color(0.043, 0.118, 0.137)
## Cuánto tapa ese color al suelo sin explorar (0-1). No es 1: la forma del
## mapa es una pista, lo que hay ENCIMA es el premio.
@export_range(0.0, 1.0) var unexplored_strength: float = 0.84
## Color de lo que queda fuera de la arena.
@export var outside_color: Color = Color(0.027, 0.063, 0.075)
## Color (con su alfa) de la línea del borde de la arena.
@export var border_color: Color = Color(0.58, 0.82, 0.8, 0.55)
## Grosor de la línea del borde de la arena, en metros.
@export var border_meters: float = 1.2
## Cuánto se oscurece el suelo hacia la orilla de una vista redonda (0-1).
@export_range(0.0, 1.0) var rim_shade: float = 0.0

## Ranura del jugador dueño de la vista: su flecha va más grande y encima de
## todo. -1 si la vista no es de nadie.
var focus_slot: int = -1

var _map: MapDraw = null
var _material: ShaderMaterial = null
## Centro de la vista (XZ del mundo) y giro (radianes): con 0, el norte queda arriba.
var _center: Vector2 = Vector2.ZERO
var _yaw: float = 0.0

@onready var _ground: TextureRect = $Ground
@onready var _markers: Control = $Markers


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = GROUND_SHADER
	_ground.material = _material
	_markers.draw.connect(_draw_markers)
	resized.connect(_fit_square)
	_fit_square()
	_push_look()
	_attach_map()


## El mapa que muestra esta vista.
func set_map(map: MapDraw) -> void:
	if _map != null and _map.refreshed.is_connected(_on_map_refreshed):
		_map.refreshed.disconnect(_on_map_refreshed)
	_map = map
	if is_node_ready():
		_attach_map()


## Centra la vista en `center` (XZ del mundo) y la gira `yaw` radianes: el
## giro de un cuerpo (rotation.y) deja arriba lo que ese cuerpo tiene delante.
func look_at_world(center: Vector2, yaw: float) -> void:
	if center.is_equal_approx(_center) and is_equal_approx(yaw, _yaw):
		return
	_center = center
	_yaw = yaw
	_push_view()
	_markers.queue_redraw()


## Hacia dónde queda el norte del mundo en esta vista (vector unitario de pantalla).
func north() -> Vector2:
	return Vector2.UP.rotated(_yaw)


## Lado, en píxeles, del cuadrado donde se dibuja el mapa.
func side() -> float:
	return minf(size.x, size.y)


## XZ del mundo -> punto dentro de Markers (y de Ground): LA proyección de la
## vista, para que un marcador nunca caiga donde no está su suelo.
func to_view(xz: Vector2) -> Vector2:
	var half := side() * 0.5
	return Vector2(half, half) + ((xz - _center) / _reach()).rotated(_yaw) * half


## Metros de mundo desde el centro hasta la orilla de la vista.
func _reach() -> float:
	if view_radius > 0.0:
		return view_radius
	return maxf(_map.half_extent, 0.001) if _map != null else 120.0


func _attach_map() -> void:
	if _map == null:
		return
	if not _map.refreshed.is_connected(_on_map_refreshed):
		_map.refreshed.connect(_on_map_refreshed)
	_ground.texture = _map.ground_texture
	_material.set_shader_parameter(&"fog_texture", _map.fog_texture)
	# Toda la arena: el centro de la vista es el centro del mapa.
	if view_radius <= 0.0:
		_center = Vector2.ZERO
	_push_view()
	_markers.queue_redraw()


func _on_map_refreshed() -> void:
	# El tamaño de la arena puede cambiar con la etapa, y con él la ventana.
	_push_view()
	_markers.queue_redraw()


## Ground y Markers ocupan el cuadrado centrado más grande que cabe.
func _fit_square() -> void:
	var length := side()
	var corner := (size - Vector2(length, length)) * 0.5
	for layer: Control in [_ground, _markers]:
		layer.position = corner
		layer.size = Vector2(length, length)
	_markers.queue_redraw()


## Los valores del shader que no cambian mientras se juega.
func _push_look() -> void:
	_material.set_shader_parameter(&"round_mask", round_view)
	_material.set_shader_parameter(&"unexplored_color", unexplored_color)
	_material.set_shader_parameter(&"unexplored_strength", unexplored_strength)
	_material.set_shader_parameter(&"outside_color", outside_color)
	_material.set_shader_parameter(&"border_color", border_color)
	_material.set_shader_parameter(&"rim_shade", rim_shade)


## La ventana del mapa que muestra el shader: centro, ancho y giro.
func _push_view() -> void:
	if _map == null or _material == null:
		return
	var arena := maxf(_map.half_extent * 2.0, 0.001)
	_material.set_shader_parameter(&"center", _map.world_to_uv(_center))
	_material.set_shader_parameter(&"span", _reach() * 2.0 / arena)
	# El shader va de pantalla a mundo: el giro inverso al de to_view.
	_material.set_shader_parameter(&"rotation", -_yaw)
	_material.set_shader_parameter(&"border_width", border_meters / arena)


func _draw_markers() -> void:
	if _map == null:
		return
	var half := side() * 0.5
	var middle := Vector2(half, half)
	var own: Dictionary = {}
	for marker: Dictionary in _map.markers:
		if int(marker["slot"]) == focus_slot and focus_slot >= 0:
			own = marker
			continue
		_draw_marker(marker, middle, half, false)
	# La flecha propia va al final: nada la tapa.
	if not own.is_empty():
		_draw_marker(own, middle, half, true)


func _draw_marker(marker: Dictionary, middle: Vector2, half: float, is_own: bool) -> void:
	var style: Dictionary = MapDraw.MARKER_STYLES[marker["kind"] as StringName]
	var at := to_view(marker["position"])
	var scale_now := _marker_scale_now() * (own_arrow_scale if is_own else 1.0)
	var from_middle := at - middle
	var limit := half - pin_margin
	var outside := from_middle.length() > limit if round_view \
			else maxf(absf(from_middle.x), absf(from_middle.y)) > half
	if outside:
		if not (pin_offscreen and bool(style.get("pin", false))):
			return
		at = middle + _clamped(from_middle, limit)
		scale_now *= pinned_scale
	var radius := float(style["size"]) * scale_now
	var facing := MapDraw.facing_of(float(marker["heading"])).rotated(_yaw)
	if is_own and own_halo_alpha > 0.0:
		_markers.draw_circle(at, radius * own_halo_radius,
				Color(marker["color"] as Color, own_halo_alpha))
	MapDraw.draw_glyph(_markers, at, String(style["shape"]), marker["color"], radius, facing)
	if bool(marker["downed"]):
		MapDraw.draw_downed_ring(_markers, at, radius)
	if show_player_tags and int(marker["slot"]) >= 0 and Coop.is_coop():
		_draw_tag(UiTheme.PLAYER_TAG % (int(marker["slot"]) + 1), at, radius, marker["color"])


## La escala de los marcadores para el tamaño que tiene la vista ahora.
func _marker_scale_now() -> float:
	if marker_reference_side <= 0.0:
		return marker_scale
	return marker_scale * clampf(side() / marker_reference_side, min_marker_shrink, 1.0)


## `offset` recortado a la orilla: al círculo en una vista redonda, al
## cuadrado en una cuadrada.
func _clamped(offset: Vector2, limit: float) -> Vector2:
	if round_view:
		return offset.limit_length(limit)
	var longest := maxf(absf(offset.x), absf(offset.y))
	return offset * (limit / longest) if longest > limit else offset


func _draw_tag(text: String, at: Vector2, radius: float, color: Color) -> void:
	var font := UiTheme.display_font()
	var corner := at + Vector2(radius * 1.6, float(tag_font_size) * 0.35)
	# Pegada al borde derecho no cabe: va del otro lado de la flecha.
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tag_font_size).x
	if corner.x + width > side() - 2.0:
		corner.x = at.x - radius * 1.6 - width
	_markers.draw_string_outline(font, corner, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			tag_font_size, tag_outline, UiTheme.INK)
	_markers.draw_string(font, corner, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			tag_font_size, color)
