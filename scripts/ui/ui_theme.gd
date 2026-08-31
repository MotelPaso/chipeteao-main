class_name UiTheme
extends RefCounted
## The one UI design system (iteration 29): every menu, card, bar and
## button pulls its StyleBoxFlat looks and its hover/press motion from
## here, so the whole game shares a palette (deep blue-black ground, teal
## for actions, amber for bosses/gold/legendary, the shard blue kept) and
## one set of corner radii, borders and states. Also owns the small
## motion vocabulary: pivot-centered grow-on-hover / squash-on-press for
## every button (attach_motion) and the reusable "pop" punch. All tweens
## ignore Engine.time_scale (hit-stop safe) and bind to the control, so
## layers that process while paused keep animating.

# --- palette ---------------------------------------------------------------
const BG_DEEP := Color(0.045, 0.05, 0.08)
const PANEL_BG := Color(0.09, 0.1, 0.145, 0.96)
const CARD_BG := Color(0.115, 0.125, 0.17, 0.98)
const CARD_BG_HOVER := Color(0.16, 0.175, 0.24, 0.98)
const CARD_BG_PRESSED := Color(0.085, 0.09, 0.125, 0.98)
const BORDER_DIM := Color(0.29, 0.315, 0.4)
const BORDER_LOCKED := Color(0.2, 0.21, 0.26)
const ACCENT := Color(0.3, 0.82, 0.76)  ## teal — actions / primary CTA
const ACCENT_AMBER := Color(0.98, 0.76, 0.28)  ## bosses, gold, legendary
const ACCENT_RED := Color(0.92, 0.28, 0.24)
const SHARD_BLUE := Color(0.55, 0.8, 0.92)
const TEXT_BRIGHT := Color(0.96, 0.97, 0.99)
const TEXT_DIM := Color(0.66, 0.69, 0.75)
const TEXT_FAINT := Color(0.47, 0.5, 0.56)
const OUTLINE_DARK := Color(0.03, 0.035, 0.06, 0.92)

const RADIUS := 10
const RADIUS_SMALL := 7

const HOVER_GROW := 1.04
const PRESS_SQUASH := 0.95
const MOTION_TIME := 0.12


# --- styleboxes ------------------------------------------------------------

static func flat(color: Color, radius: int = RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box


static func panel(bg: Color = PANEL_BG, border: Color = BORDER_DIM,
		margin_h: float = 30.0, margin_v: float = 22.0) -> StyleBoxFlat:
	var box := flat(bg, RADIUS + 2)
	box.border_color = border
	box.set_border_width_all(1)
	box.border_width_top = 3  # header accent line
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	box.shadow_size = 14
	return box


## Soft outer glow via the stylebox shadow (used for selected cards,
## rarity borders, claimable quest rows).
static func add_glow(box: StyleBoxFlat, color: Color, size: int = 8,
		alpha: float = 0.35) -> void:
	box.shadow_color = Color(color.r, color.g, color.b, alpha)
	box.shadow_size = size


## The four button states in one dictionary. filled = hero CTA look
## (accent-tinted body, dark-on-bright is avoided: text stays bright over
## a deep accent fill).
static func button_states(accent: Color = ACCENT,
		filled: bool = false) -> Dictionary[String, StyleBoxFlat]:
	var body := Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.97) \
			if filled else CARD_BG
	var body_hover := Color(accent.r * 0.32, accent.g * 0.32, accent.b * 0.32, 0.97) \
			if filled else CARD_BG_HOVER
	var body_pressed := Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.97) \
			if filled else CARD_BG_PRESSED
	var edge := accent if filled else BORDER_DIM
	var states: Dictionary[String, StyleBoxFlat] = {}
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box := flat(body, RADIUS_SMALL + 2)
		box.set_border_width_all(2)
		box.border_color = edge
		match state:
			"hover":
				box.bg_color = body_hover
				box.border_color = accent
			"pressed":
				box.bg_color = body_pressed
				box.border_color = accent.darkened(0.2)
			"focus":
				box.bg_color = body_hover
				box.border_color = accent
		if filled:
			add_glow(box, accent, 6, 0.28 if state != "pressed" else 0.12)
		states[state] = box
	return states


## Apply the full system to a Button: state styleboxes, font colors, and
## the grow/squash motion. The one entry point every screen uses.
static func style_button(button: Button, accent: Color = ACCENT,
		filled: bool = false) -> void:
	var states := button_states(accent, filled)
	for state: String in states:
		button.add_theme_stylebox_override(state, states[state])
	button.add_theme_color_override("font_color",
			TEXT_BRIGHT if filled else Color(0.88, 0.9, 0.94))
	button.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	button.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	button.add_theme_color_override("font_focus_color", TEXT_BRIGHT)
	attach_motion(button)


# --- motion ----------------------------------------------------------------

## Pivot-centered hover grow + press squash. Idempotent: safe to call on
## every restyle; connects only once per button. Scale is visual-only in
## containers, so layout never shifts.
static func attach_motion(button: BaseButton, grow: float = HOVER_GROW,
		squash: float = PRESS_SQUASH) -> void:
	if button.has_meta(&"ui_motion"):
		return
	button.set_meta(&"ui_motion", true)
	button.mouse_entered.connect(_scale_to.bind(button, grow))
	button.mouse_exited.connect(_scale_to.bind(button, 1.0))
	button.button_down.connect(_scale_to.bind(button, squash))
	button.button_up.connect(func() -> void:
		_scale_to(button, grow if button.is_hovered() else 1.0))


static func _scale_to(button: BaseButton, target: float) -> void:
	if not button.is_inside_tree():
		return
	button.pivot_offset = button.size * 0.5
	kill_meta_tween(button, &"ui_motion_tween")
	var tween := button.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(button, "scale", Vector2.ONE * target, MOTION_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	button.set_meta(&"ui_motion_tween", tween)


## Quick attention punch (level chip, shard counter, chosen card): scales
## up and settles back. Interruptible — re-popping restarts cleanly.
static func pop(control: Control, peak: float = 1.22, duration: float = 0.26) -> void:
	if not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	kill_meta_tween(control, &"ui_pop_tween")
	control.scale = Vector2.ONE
	var tween := control.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(control, "scale", Vector2.ONE * peak, duration * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, duration * 0.65) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta(&"ui_pop_tween", tween)


## Kill-and-forget for tweens parked in metadata (the pattern that keeps
## every animation idempotent under rapid open/close).
static func kill_meta_tween(node: Node, key: StringName) -> void:
	if not node.has_meta(key):
		return
	var old: Variant = node.get_meta(key)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()


# --- typography ------------------------------------------------------------

## Default font with extra per-glyph spacing: the "small caps label" /
## big title treatment without shipping a font asset.
static func spaced_font(spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = spacing
	return font


## Headline treatment: letter-spaced, outlined, colored.
static func style_title(label: Label, font_size: int, color: Color,
		spacing: int = 6, outline: int = 10) -> void:
	label.add_theme_font_override("font", spaced_font(spacing))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", outline)


## Small badge/pill treatment for HUD chips and ribbons.
static func style_badge(label: Label, text_color: Color,
		bg: Color = PANEL_BG, border: Color = Color(0, 0, 0, 0.5)) -> void:
	var box := flat(bg, RADIUS_SMALL)
	box.set_border_width_all(1)
	box.border_color = border
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	label.add_theme_stylebox_override("normal", box)
	label.add_theme_color_override("font_color", text_color)


# --- widgets ---------------------------------------------------------------

## Round slider grabber built from a radial gradient (no texture assets).
static func grabber_icon(color: Color, diameter: int = 18) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color, color, Color(color, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.78, 0.86])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = diameter
	texture.height = diameter
	return texture


## Layered bar treatment: dark trough + rounded fill with a top gloss
## line and a brighter leading-edge tick (right border of the fill).
## Returns the fill so callers can recolor it live (HP green→red ramp).
static func style_bar(bar: ProgressBar, fill_color: Color, radius: int = 6,
		inset: int = 3) -> StyleBoxFlat:
	var trough := flat(Color(0.04, 0.045, 0.07, 0.85), radius + 1)
	trough.set_border_width_all(2)
	trough.border_color = Color(0.0, 0.0, 0.0, 0.6)
	trough.set_content_margin_all(inset)
	bar.add_theme_stylebox_override("background", trough)
	var fill := bar_fill(fill_color, radius - 1)
	bar.add_theme_stylebox_override("fill", fill)
	return fill


static func bar_fill(color: Color, radius: int = 5) -> StyleBoxFlat:
	var fill := flat(color, radius)
	fill.border_width_top = 2
	fill.border_width_right = 3
	fill.border_color = color.lightened(0.35)
	return fill


## Keep the gloss/tick border in step when a fill is recolored live.
static func recolor_fill(fill: StyleBoxFlat, color: Color) -> void:
	fill.bg_color = color
	fill.border_color = color.lightened(0.35)
