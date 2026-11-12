class_name CardFactory
extends RefCounted
## Constructores sin estado de las piezas de una carta armada en código
## (hoy, las ofertas del vendedor): etiquetas y la caja de contenido. Solo
## leen sus argumentos.
##
## Solo el CONTENIDO: los styleboxes de estado de la carta (normal/hover/
## pressed/focus) son UiTheme.style_card, el único aspecto de carta de toda
## superficie de "elige una". Colores y radios también salen de UiTheme.

# --- edita aquí --------------------------------------------------------------
# CardFactory no tiene escena (sus funciones son estáticas), así que sus
# ajustes son estas constantes y no aparecen en el Inspector.

## Margen interior de la caja de contenido de una carta, en píxeles
## (horizontal, vertical).
const CARD_BOX_MARGIN := Vector2(12.0, 12.0)
## Separación vertical entre las piezas de la carta, en píxeles.
const CARD_BOX_SEPARATION := 8
# --- fin de edita aquí -------------------------------------------------------


## Etiqueta centrada. El llamador agrega el ajuste de línea y el tope de
## líneas: las cartas de la cuadrícula recortan, las filas anchas no.
static func label(label_text: String, font_size: int, color: Color) -> Label:
	var made := Label.new()
	made.text = label_text
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override("font_size", font_size)
	made.add_theme_color_override("font_color", color)
	return made


## VBox de contenido que llena el botón de la carta, con márgenes.
static func card_box(card: Button) -> VBoxContainer:
	var box := _full_rect_box(card, CARD_BOX_MARGIN.x, CARD_BOX_MARGIN.y)
	box.add_theme_constant_override("separation", CARD_BOX_SEPARATION)
	return box


static func _full_rect_box(card: Button, margin_h: float, margin_v: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = margin_h
	box.offset_top = margin_v
	box.offset_right = -margin_h
	box.offset_bottom = -margin_v
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	return box
