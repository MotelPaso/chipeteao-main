class_name InputHints
extends HBoxContainer
## Button prompts ("✕ Elegir  ○ Volver") for the menus, drawn with the
## Controller Icons addon (addons/controller_icons, MIT; Xelu's CC0 art).
##
## Each icon is a ControllerIconTexture whose path is an INPUT ACTION, not a
## button: it shows whatever key or pad button that action is bound to in
## the Input Map, so rebinding an action there fixes every prompt at once.
## The addon also watches the last device used and swaps keyboard glyphs
## for pad glyphs (Xbox / PlayStation / Switch, read from the pad's name)
## on the fly — nothing here has to listen for input.
##
## Usage: add_child(InputHints.build([["ui_accept", "Elegir"],
##        ["ui_cancel", "Volver"]]))

const ICON_SIZE := 28.0
const TEXT_SIZE := 14
## Space between an icon and its word, and between two prompts.
const ICON_GAP := 6
const HINT_GAP := 22


## One row of prompts, centred, that never takes the mouse or the focus.
## `hints` is a list of [action, text] pairs.
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
	# The headless display server (tools/verificar.sh runs every harness
	# with --headless) cannot map a physical key to a keycode, and the addon
	# logs an ERROR for each keyboard glyph it resolves there — which the
	# gate counts as a failure. Headless nothing is drawn anyway, so the
	# icon keeps its slot and simply gets no texture.
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


## Pins the row to the bottom-left corner of a full-screen Control.
func pin_bottom_left(margin: Vector2 = Vector2(24.0, 8.0)) -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = margin.x
	offset_right = margin.x
	offset_top = -margin.y - ICON_SIZE
	offset_bottom = -margin.y
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
