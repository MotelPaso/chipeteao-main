class_name CardFactory
extends RefCounted
## Stateless builders for the select screen's card chrome (iteration 46):
## the labels, content boxes, swatches and lock glyph every card in
## CharacterSelect is made of. Split out of character_select.gd because
## none of it needs the screen's state — it only ever reads its arguments —
## so the screen script is left with selection logic and catalog wiring.
##
## CONTENTS only: the card's own state styleboxes (normal/hover/pressed/
## focus) are UiTheme.style_card, the single card look every "pick one of
## these" surface shares. Colors and radii come from UiTheme too — this is
## the "how a card is assembled" layer, not a second design system.


## Centered card label. Callers add autowrap/line caps themselves — the
## grid cards trim, the wide rows don't.
## Shared height of the portrait frame and the padlock that replaces it,
## so locked and unlocked cards line up row by row.
const PORTRAIT_HEIGHT := 56.0

static func label(label_text: String, font_size: int, color: Color) -> Label:
	var made := Label.new()
	made.text = label_text
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override("font_size", font_size)
	made.add_theme_color_override("font_color", color)
	return made


## Full-rect content VBox inside a card button (UpgradeCardUI convention).
static func card_box(card: Button) -> VBoxContainer:
	var box := _full_rect_box(card, 12.0, 12.0)
	box.add_theme_constant_override("separation", 8)
	return box


## Compact variant for the short map cards (the character card margins are
## too deep for a 54px card).
static func map_card_box(card: Button) -> VBoxContainer:
	var box := _full_rect_box(card, 10.0, 6.0)
	box.add_theme_constant_override("separation", 4)
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


## Tiny biome mood strip: the catalog palette as flat color chips.
static func palette_strip(palette: Array) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 4)
	for entry: Variant in palette:
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(34.0, 10.0)
		chip.add_theme_stylebox_override("panel", UiTheme.flat(entry as Color, 3))
		strip.add_child(chip)
	return strip


## Tinted stand-in for character art in the body color.
static func portrait_swatch(tint: Color, monogram: String = "") -> Panel:
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(0.0, PORTRAIT_HEIGHT)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dark-to-tint body with a bright rim: reads as a portrait frame
	# instead of a flat paint chip.
	var style := UiTheme.flat(tint.darkened(0.35), 10)
	style.border_color = tint.lightened(0.3)
	style.set_border_width_all(2)
	style.border_width_bottom = 4
	UiTheme.add_glow(style, tint, 6, 0.35)
	swatch.add_theme_stylebox_override("panel", style)
	if not monogram.is_empty():
		# The raider's initial, big and outlined, so every card has a face
		# until real portrait art lands.
		var letter := label(monogram.left(1).to_upper(), 30, UiTheme.TEXT_BRIGHT)
		letter.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.add_theme_color_override("font_outline_color", tint.darkened(0.7))
		letter.add_theme_constant_override("outline_size", 6)
		swatch.add_child(letter)
	return swatch


## Small code-drawn padlock (shackle arch over a body box) standing where
## the portrait swatch would be, so "locked" reads without any glyph font.
static func lock_glyph() -> Control:
	var glyph := Control.new()
	glyph.custom_minimum_size = Vector2(0.0, PORTRAIT_HEIGHT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shackle := Panel.new()
	shackle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	shackle.offset_left = -8.0
	shackle.offset_right = 8.0
	shackle.offset_top = 12.0
	shackle.offset_bottom = 28.0
	var arch := StyleBoxFlat.new()
	arch.draw_center = false
	arch.border_color = UiTheme.TEXT_FAINT
	arch.set_border_width_all(3)
	arch.corner_radius_top_left = 8
	arch.corner_radius_top_right = 8
	shackle.add_theme_stylebox_override("panel", arch)
	glyph.add_child(shackle)
	var body := Panel.new()
	body.set_anchors_preset(Control.PRESET_CENTER_TOP)
	body.offset_left = -11.0
	body.offset_right = 11.0
	body.offset_top = 24.0
	body.offset_bottom = 42.0
	body.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.TEXT_FAINT, 3))
	glyph.add_child(body)
	return glyph
