class_name StatIconChip
extends PanelContainer
## Ficha con el icono de una estadística (StatIconChip.tscn): un cuadrado de
## papel con contorno de tinta y el dibujo del stat adentro. La usan las filas
## de la Armería y las cartas de Objetos y Tomos. Quien la usa pasa el nombre
## del stat (show_stat); la ficha decide cómo se ve.

@export_group("Ficha")
## Lado de la ficha, en píxeles.
@export var chip_size: float = 52.0
## Color del fondo de la ficha.
@export var chip_color: Color = UiTheme.PAPER
## Color del contorno.
@export var border_color: Color = UiTheme.INK
## Grosor del contorno, en píxeles.
@export var border_width: int = 3
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = 12
## Aire entre el contorno y el dibujo, en píxeles.
@export var icon_padding: float = 6.0
## Sombra dura de la ficha (desplazamiento en píxeles).
@export var shadow_offset: Vector2 = Vector2(0.0, 3.0)

## Stat que muestra la ficha.
var stat: String = ""

@onready var _icon: TextureRect = %Icon


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * chip_size
	var style := UiTheme.flat(chip_color, corner_radius)
	style.set_border_width_all(border_width)
	style.border_color = border_color
	style.set_content_margin_all(icon_padding)
	UiTheme.add_hard_shadow(style, shadow_offset)
	add_theme_stylebox_override("panel", style)
	_icon.texture = StatIcons.texture(stat)


## Muestra el icono de ese stat del catálogo ("damage", "max_hp"…). Un stat
## sin icono propio muestra el de respaldo.
func show_stat(stat_name: String) -> void:
	stat = stat_name
	if is_node_ready():
		_icon.texture = StatIcons.texture(stat)
