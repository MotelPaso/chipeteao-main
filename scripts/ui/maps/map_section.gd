class_name MapSection
extends PanelContainer
## Un panel del mapa de Tab, con el aspecto de las tarjetas del menú principal
## (MenuTile): un marco de color plano con contorno de tinta grueso y sombra
## dura, apenas girado como un sticker, y adentro su título y su contenido en
## tinta. Solo gira el MARCO (nodo Frame, bajo un Control que no es
## contenedor); el texto queda siempre recto y nítido.
##
## El contenido son los nodos que MapOverlay.tscn agrega dentro de Content/Box
## (cada panel tiene «Hijos editables» activado en esa escena). Cada instancia
## pone su `title`, su `tile_color` y su `tilt_degrees`.

## Cuánto cabe en el mapa de Tab. MapOverlay parte en ROOMY y baja un escalón
## cada vez que sus paneles no entran en la celda del jugador.
enum Density {
	ROOMY, ## Con espacio: nombres completos y todas las filas.
	COMPACT, ## Celda chica: letra más chica, sin filas en cero ni nombres.
	TIGHT, ## Lo mismo, sin los títulos de los paneles.
}

@export_group("Panel")
## Título del panel, tal como lo ve el jugador.
@export var title: String = ""
## Tamaño de letra del título con espacio, en píxeles.
@export var title_font_size: int = 24
## Tamaño de letra del título en una celda chica, en píxeles.
@export var compact_title_font_size: int = 15

@export_group("Marco")
## Color del cuerpo de la tarjeta.
@export var tile_color: Color = UiTheme.ACCENT
## Giro del marco, en grados (el texto no gira). En una celda chica el marco
## queda derecho: ahí no sobra un píxel.
@export var tilt_degrees: float = -0.8
## Grosor del contorno de tinta con espacio, en píxeles.
@export var border_width: int = 5
## Grosor del contorno de tinta en una celda chica, en píxeles.
@export var compact_border_width: int = 3
## Radio de las esquinas con espacio, en píxeles.
@export var corner_radius: int = 20
## Radio de las esquinas en una celda chica, en píxeles.
@export var compact_corner_radius: int = 12
## Sombra dura bajo la tarjeta con espacio (desplazamiento en píxeles).
@export var shadow_offset: Vector2 = Vector2(0.0, 8.0)
## Sombra dura bajo la tarjeta en una celda chica (desplazamiento en píxeles).
@export var compact_shadow_offset: Vector2 = Vector2(0.0, 4.0)

@export_group("Contenido")
## Margen interior con espacio (horizontal, vertical), en píxeles.
@export var padding: Vector2 = Vector2(18.0, 12.0)
## Margen interior en una celda chica (horizontal, vertical), en píxeles.
@export var compact_padding: Vector2 = Vector2(12.0, 7.0)
## Margen interior de una tarjeta sin título (horizontal, vertical), en píxeles.
@export var tight_padding: Vector2 = Vector2(9.0, 5.0)

@export_group("Movimiento")
## Escala desde la que salta el marco cuando se abre el mapa.
@export var pop_from_scale: float = 0.92
## Duración de ese salto, en segundos.
@export var pop_time: float = 0.16

var _style: StyleBoxFlat = null
var _pop_tween: Tween = null

@onready var _frame: Panel = $Back/Frame
@onready var _content: MarginContainer = $Content
@onready var _title: Label = $Content/Box/Title


func _ready() -> void:
	_title.text = title
	_style = UiTheme.flat(tile_color, corner_radius)
	_style.border_color = UiTheme.INK
	UiTheme.add_hard_shadow(_style, shadow_offset)
	_frame.add_theme_stylebox_override("panel", _style)
	_frame.resized.connect(_center_pivot)
	_center_pivot()
	set_density(Density.ROOMY)


## Ajusta el panel a la densidad del mapa: en COMPACT el marco se afina, deja
## de girar y el título se achica; en TIGHT además el título desaparece.
func set_density(level: Density) -> void:
	var compact := level != Density.ROOMY
	_title.visible = level != Density.TIGHT
	_title.add_theme_font_size_override("font_size",
			compact_title_font_size if compact else title_font_size)
	_style.set_border_width_all(compact_border_width if compact else border_width)
	_style.set_corner_radius_all(compact_corner_radius if compact else corner_radius)
	_style.shadow_offset = compact_shadow_offset if compact else shadow_offset
	_frame.rotation_degrees = 0.0 if compact else tilt_degrees
	var margin := padding
	if level == Density.TIGHT:
		margin = tight_padding
	elif compact:
		margin = compact_padding
	_content.add_theme_constant_override("margin_left", roundi(margin.x))
	_content.add_theme_constant_override("margin_right", roundi(margin.x))
	_content.add_theme_constant_override("margin_top", roundi(margin.y))
	_content.add_theme_constant_override("margin_bottom", roundi(margin.y))


## El salto de entrada del marco, como las tarjetas del menú al aparecer, tras
## `delay` segundos. Es decorativo: el contenido ya está en su lugar.
func pop(delay: float) -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_frame.scale = Vector2.ONE * pop_from_scale
	_pop_tween = create_tween()
	# El hit-stop baja Engine.time_scale; el mapa se abre igual.
	_pop_tween.set_ignore_time_scale(true)
	_pop_tween.tween_property(_frame, "scale", Vector2.ONE, pop_time).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _center_pivot() -> void:
	_frame.pivot_offset = _frame.size * 0.5
