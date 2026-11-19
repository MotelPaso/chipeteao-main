class_name Minimap
extends Control
## Minimapa de una vista de jugador (Minimap.tscn): un disco con el aspecto de
## un sticker del menú principal (contorno de tinta grueso, un aro de papel y
## sombra dura) que muestra el mapa alrededor de SU jugador, con la flecha de
## ese jugador al centro. Lo que queda fuera de la vista y vale la pena
## perseguir (compañeros, jefe y salida) se ancla a la orilla.
##
## Los enemigos comunes NUNCA se dibujan: un minimapa con cuarenta puntos es
## ruido, y la horda es lo que el jugador ya está mirando. El mapa sirve para
## lo que NO ves desde donde estás: el cofre tras dos colinas, el altar sin
## cargar, la salida.
##
## El mapa en sí (suelo, niebla y marcadores) es el hijo View, un MapView:
## cuánto terreno muestra, la escala de los marcadores y los colores del suelo
## son exports de ese nodo. El grosor total del aro es el margen de View
## dentro de este nodo. Posición y tamaño los pone quien lo crea: ViewWidgets,
## con el rectángulo de HUD.tscn > ViewWidgets > MinimapSlot.
##
## Ningún nodo de la escena toma foco ni recibe el mouse: Tab tiene que llegar
## al mapa grande, no recorrer la cadena de foco, y un clic es del mundo.

@export_group("Jugador")
## Qué jugador es dueño de este minimapa (ranura 0-3). Lo asigna ViewWidgets.
@export var slot: int = 0
@export_group("Vista")
## Gira el mapa con la cámara del jugador, así lo que tiene delante queda
## arriba. Apagado, el norte queda siempre arriba y solo gira la flecha.
@export var rotate_with_view: bool = true
@export_group("Marco")
## Color del contorno de tinta, por fuera y por dentro del aro.
@export var ring_color: Color = UiTheme.INK
## Color del aro, entre los dos contornos.
@export var band_color: Color = UiTheme.PAPER
## Grosor del contorno de afuera, en píxeles. El aro de color ocupa lo que
## queda del margen de View.
@export var outline_width: float = 4.0
## Grosor del contorno de adentro, en píxeles.
@export var inner_outline_width: float = 2.5
## Color de la sombra dura bajo el disco.
@export var shadow_color: Color = UiTheme.SHADOW_COLOR
## Desplazamiento de la sombra dura bajo el disco, en píxeles.
@export var shadow_offset: Vector2 = Vector2(0.0, 5.0)
@export_group("Norte")
## Distancia del centro de la chapa «N» a la orilla del disco, en píxeles.
@export var north_inset: float = 9.0

## Último cuerpo visto para esta ranura. Solo evita buscarlo en los grupos
## cada cuadro: si deja de servir, se vuelve a buscar.
var _raider: Node3D = null

@onready var _view: MapView = $View
@onready var _north: Label = $North


func _ready() -> void:
	_view.focus_slot = slot
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	var raider := _own_raider()
	if raider == null:
		return
	# Cada cuadro y no en el refresco del mapa: la vista sigue al jugador, y a
	# diez pasos por segundo el mapa se vería a saltos al girar.
	var yaw := _view_yaw(raider) if rotate_with_view else 0.0
	_view.look_at_world(Vector2(raider.global_position.x, raider.global_position.z), yaw)
	_place_north()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var middle := size * 0.5
	# De afuera hacia adentro: sombra, tinta, aro de color y tinta otra vez.
	var inner := radius - _view.offset_left
	_draw_disc(middle + shadow_offset, radius, shadow_color)
	_draw_disc(middle, radius, ring_color)
	_draw_disc(middle, radius - outline_width, band_color)
	_draw_disc(middle, inner + inner_outline_width, ring_color)


## El mapa compartido que muestra este minimapa (lo crea ViewWidgets).
func set_map(map: MapDraw) -> void:
	$View.set_map(map)


## Disco relleno con la orilla suavizada (draw_circle solo deja dientes).
func _draw_disc(middle: Vector2, radius: float, color: Color) -> void:
	draw_circle(middle, radius - 0.5, color)
	draw_arc(middle, radius - 0.75, 0.0, TAU, 64, color, 1.5, true)


## El jugador de esta ranura, de pie o caído; null si la ranura está vacía.
func _own_raider() -> Node3D:
	if is_instance_valid(_raider) and _raider.is_inside_tree() \
			and int(_raider.get("player_index")) == slot:
		return _raider
	_raider = PartySlots.raider_at(get_tree(), slot)
	return _raider


## Giro de la VISTA del jugador: hacia dónde mira su cámara, que en órbita
## libre no es hacia donde mira el cuerpo. Sin cámara, el giro del cuerpo.
func _view_yaw(raider: Node3D) -> float:
	var camera: Camera3D = raider.call(&"view_camera") if raider.has_method(&"view_camera") \
			else null
	if camera == null:
		return raider.global_rotation.y
	var forward := -camera.global_transform.basis.z
	# Mirando recto hacia abajo no hay rumbo plano: se queda con el del cuerpo.
	if Vector2(forward.x, forward.z).length_squared() < 0.0001:
		return raider.global_rotation.y
	return atan2(-forward.x, -forward.z)


## Lleva la chapa «N» a la orilla, hacia donde queda el norte en la vista.
func _place_north() -> void:
	var reach := minf(size.x, size.y) * 0.5 - north_inset
	_north.position = size * 0.5 + _view.north() * reach - _north.size * 0.5
