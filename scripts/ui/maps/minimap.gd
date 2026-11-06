class_name Minimap
extends Control
## Minimapa con el norte arriba, uno por vista de jugador. Dibuja la
## composición de MapDraw (el relieve de la etapa, oscurecido donde la máscara
## de la arena lo bloquea y atenuado donde la niebla no se ha explorado) más
## los marcadores que la niebla ya reveló.
##
## Los enemigos comunes NUNCA se dibujan: un minimapa con cuarenta puntos es
## ruido, y la horda es lo que el jugador ya está mirando. El mapa sirve para
## lo que NO ves desde donde estás: el cofre tras dos colinas, el altar sin
## cargar, la salida.
##
## Se reconstruye desde WorldDirector.on_stage_started (reenviado por el HUD),
## no desde la señal stage_changed: esa llamada también ocurre en la etapa 0,
## así que la primera etapa no necesita caso especial.

## Lado del widget, en píxeles.
const SIZE: float = 150.0
## Margen del mapa dentro de su marco, en píxeles.
const FRAME_PAD: float = 3.0
## Los marcadores se dibujan más chicos aquí que en el mapa de Tab.
const MARKER_SCALE: float = 0.75
## Segundos entre recolecciones de marcadores y revisiones de la composición.
## La niebla pinta en su propio tick, más lento; esto la convierte en imagen
## cuando cambió (ver _composite_if_changed).
const REFRESH: float = 0.1

var _map: MapDraw = null
var _refresh_left: float = 0.0
## composite_key() de la última composición de este widget. Vacío significa
## "desconocido": el próximo refresco compone sin mirar la clave.
var _composited: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	# Nunca se come un clic destinado al mundo ni toma el foco (Tab tiene que
	# llegar al mapa grande, no recorrer la cadena de foco).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_map = MapDraw.new(get_tree())
	_map.build_background()


## Gancho de etapa, reenviado por el HUD desde WorldDirector.on_stage_started.
func on_stage_started(_arena: Node3D = null) -> void:
	if _map == null:
		_map = MapDraw.new(get_tree())
	_map.build_background()
	# build_background reescribe los píxeles de la imagen, y la clave no ve un
	# cambio dentro de una Image que ya conoce: se olvida, para que el próximo
	# refresco componga sí o sí.
	_composited = []
	_map.collect_markers()
	queue_redraw()


func _process(delta: float) -> void:
	if _map == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH
	# Ambos son métodos simples sin Control, así que un soak headless ejercita
	# el mapa aunque _draw() nunca se despache. Los marcadores se mueven y se
	# recolectan en cada tick; la composición solo cuando cambiaron sus entradas.
	_map.collect_markers()
	_composite_if_changed()
	queue_redraw()


## MapDraw.composite() depende solo de la imagen de fondo y de la de niebla:
## un bucle de get_pixel/set_pixel sobre 14 400 píxeles (~1.5 ms de GDScript).
## La niebla solo cambia cuando un jugador pisa suelo que nadie había visto,
## así que en la mayoría de los ticks la textura sería la que ya está en pantalla.
func _composite_if_changed() -> void:
	var key := composite_key(_map, get_tree())
	if key == _composited:
		return
	_composited = key
	_map.composite()


## Todo lo que lee MapDraw.composite(), como un valor comparable: la Image de
## fondo del mapa (build_background pone una nueva por etapa), el nodo de
## niebla y su revisión (que cambia justo cuando cambia su imagen). Claves
## iguales significan que composite() escribiría los mismos píxeles. Los
## cambios DENTRO del fondo no se ven aquí; por eso cada llamada a
## build_background también borra la clave del llamador. Estático y compartido
## con MapOverlay, para que ambos coincidan sobre cuándo su imagen está vieja.
static func composite_key(map: MapDraw, tree: SceneTree) -> Array:
	var fog := FogOfWar.find(tree)
	return [
		map.background.get_instance_id() if map.background != null else 0,
		fog.get_instance_id() if fog != null else 0,
		fog.revision if fog != null else -1,
	]


func marker_count() -> int:
	return _map.marker_count() if _map != null else 0


func _draw() -> void:
	if _map == null:
		return
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, Color(0.05, 0.055, 0.08, 0.85), true)
	var inner := Rect2(Vector2(FRAME_PAD, FRAME_PAD),
			size - Vector2(FRAME_PAD, FRAME_PAD) * 2.0)
	_map.draw_into(self, inner, MARKER_SCALE)
	draw_rect(frame, UiTheme.ACCENT.darkened(0.2), false, 2.0)
