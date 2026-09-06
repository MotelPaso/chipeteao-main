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
static func portrait_swatch(tint: Color) -> Panel:
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(0.0, 40.0)
	var style := UiTheme.flat(tint, 8)
	style.border_color = tint.lightened(0.25)
	style.set_border_width_all(2)
	UiTheme.add_glow(style, tint, 5, 0.3)
	swatch.add_theme_stylebox_override("panel", style)
	return swatch


## Small code-drawn padlock (shackle arch over a body box) standing where
## the portrait swatch would be, so "locked" reads without any glyph font.
static func lock_glyph() -> Control:
	var glyph := Control.new()
	glyph.custom_minimum_size = Vector2(0.0, 40.0)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shackle := Panel.new()
	shackle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	shackle.offset_left = -8.0
	shackle.offset_right = 8.0
	shackle.offset_top = 4.0
	shackle.offset_bottom = 20.0
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
	body.offset_top = 16.0
	body.offset_bottom = 34.0
	body.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.TEXT_FAINT, 3))
	glyph.add_child(body)
	return glyph
