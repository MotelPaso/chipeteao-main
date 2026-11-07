class_name MapSection
extends PanelContainer
## Un panel de la columna del mapa de Tab: un título y un cuerpo de varias
## líneas. El aspecto (fondo, colores y tamaños de letra) vive en
## MapSection.tscn; cada instancia en MapOverlay.tscn solo pone su `title`.

## Título del panel, tal como lo ve el jugador.
@export var title: String = ""
## Espacio extra entre las letras del título, en píxeles.
@export var title_letter_spacing: int = 2

@onready var _title: Label = $Box/Title
@onready var _body: Label = $Box/Body


func _ready() -> void:
	_title.text = title
	_title.add_theme_font_override("font", UiTheme.spaced_font(title_letter_spacing))


## Cambia el texto del cuerpo (varias líneas separadas por \n).
func set_body(text: String) -> void:
	_body.text = text
