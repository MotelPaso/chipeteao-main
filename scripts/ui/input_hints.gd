class_name InputHints
extends HBoxContainer
## Indicaciones de botones de los menús ("✕ Elegir  ○ Volver"), dibujadas con
## el addon Controller Icons (addons/controller_icons, MIT; arte CC0 de Xelu).
##
## Cada ícono es un ControllerIconTexture cuya ruta es una ACCIÓN de entrada,
## no un botón: muestra la tecla o el botón del control asignado a esa acción
## en el Input Map, así que reasignarla allí corrige todas las indicaciones.
## El addon sigue el último dispositivo usado y cambia los glifos de teclado
## por los del control (Xbox / PlayStation / Switch, según su nombre) al
## vuelo: aquí nada escucha la entrada.
##
## Uso: add_child(InputHints.build([["ui_accept", "Elegir"],
##        ["ui_cancel", "Volver"]]))
## Se crea con build() y nunca va en una escena: edita los valores aquí.

## Lado del ícono (píxeles) y tamaño de fuente de su texto.
const ICON_SIZE := 28.0
const TEXT_SIZE := 14
## Espacio (píxeles) entre un ícono y su palabra, y entre dos indicaciones.
const ICON_GAP := 6
const HINT_GAP := 22


## Una fila centrada de indicaciones que nunca toma el mouse ni el foco.
## `hints` es una lista de pares [acción, texto].
static func build(hints: Array) -> InputHints:
	var row := InputHints.new()
	row.name = "InputHints"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", HINT_GAP)
	for hint: Array in hints:
		row.add_child(_prompt(String(hint[0]), String(hint[1])))
	return row


static func _prompt(action: String, text: String) -> HBoxContainer:
	var prompt := HBoxContainer.new()
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_theme_constant_override("separation", ICON_GAP)
	var icon := TextureRect.new()
	# El servidor de pantalla headless (tools/verificar.sh corre todos los
	# harness con --headless) no traduce una tecla física a keycode, y el
	# addon registra un ERROR por cada glifo de teclado que resuelve allí; la
	# puerta lo cuenta como falla. Headless no se dibuja nada, así que el
	# ícono guarda su espacio y queda sin textura.
	if DisplayServer.get_name() != "headless":
		var texture := ControllerIconTexture.new()
		texture.path = action
		icon.texture = texture
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_child(icon)
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_child(label)
	return prompt


## Fija la fila en la esquina inferior izquierda de un Control de pantalla
## completa; `margin` en píxeles.
func pin_bottom_left(margin: Vector2 = Vector2(24.0, 8.0)) -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = margin.x
	offset_right = margin.x
	offset_top = -margin.y - ICON_SIZE
	offset_bottom = -margin.y
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
