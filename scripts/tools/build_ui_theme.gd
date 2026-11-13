extends SceneTree
## Genera el Theme global del juego desde los valores de UiTheme:
##   res://assets/ui/theme/game_theme.tres
## project.godot lo usa como tema de todo el proyecto (gui/theme/custom), así
## que cualquier Button, Label, panel o barra nuevo nace con el estilo del
## juego sin escribir código.
##
## Córrelo desde la raíz del proyecto cada vez que cambies un color, una
## fuente o una medida en scripts/ui/ui_theme.gd, y commitea el .tres:
##   godot --headless --path . -s res://scripts/tools/build_ui_theme.gd
##
## No edites game_theme.tres a mano: esta herramienta lo reescribe entero.
## Los valores viven en ui_theme.gd; aquí solo se decide a qué tipo de nodo
## va cada uno. Hermano de generate_sfx.gd: determinista, un recurso, se
## regenera a mano y se commitea. Solo usa UiTheme, que no toca autoloads.
##
## Variaciones de tipo (en el Inspector: Theme > Type Variation):
##   TitleLabel     título de pantalla, fuente de display con contorno
##   HeadingLabel   subtítulo o encabezado de sección
##   DimLabel       texto secundario
##   BadgeLabel     chapa oscura con borde (saldos, precios)
##   PrimaryButton  botón principal amarillo
##   DangerButton   botón de acción peligrosa (rojo naranja)
##   CardPanel      tarjeta: panel más claro con sombra dura

const OUTPUT_PATH: String = "res://assets/ui/theme/game_theme.tres"

## Tamaños de letra de las variaciones de Label, en píxeles.
const TITLE_SIZE: int = 44
const HEADING_SIZE: int = 24
## Grosor del contorno de tinta del título, en píxeles.
const TITLE_OUTLINE: int = 10
## Barra de desplazamiento: ancho del agarrador y radio, en píxeles.
const SCROLL_WIDTH: int = 10
const SCROLL_RADIUS: int = 5
## Slider: alto de la pista y diámetro del agarrador, en píxeles.
const SLIDER_TRACK_HEIGHT: int = 10
const SLIDER_GRABBER_SIZE: int = 22
## Margen interior de los tooltips (horizontal, vertical), en píxeles.
const TOOLTIP_MARGIN: Vector2 = Vector2(10.0, 6.0)


func _init() -> void:
	var theme := Theme.new()
	theme.default_font = UiTheme.text_font()
	theme.default_font_size = UiTheme.TEXT_SIZE
	_add_labels(theme)
	_add_buttons(theme)
	_add_panels(theme)
	_add_bars(theme)
	_add_scroll(theme)
	_add_tooltip(theme)
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var error := ResourceSaver.save(theme, OUTPUT_PATH)
	if error != OK:
		push_error("build_ui_theme: could not save %s (error %d)" % [OUTPUT_PATH, error])
	else:
		print("build_ui_theme: wrote %s" % OUTPUT_PATH)
	quit()


func _add_labels(theme: Theme) -> void:
	theme.set_color(&"font_color", &"Label", UiTheme.TEXT_BRIGHT)
	theme.set_color(&"font_outline_color", &"Label", UiTheme.OUTLINE_DARK)

	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_font(&"font", &"TitleLabel", UiTheme.display_font())
	theme.set_font_size(&"font_size", &"TitleLabel", TITLE_SIZE)
	theme.set_color(&"font_color", &"TitleLabel", UiTheme.ACCENT)
	theme.set_color(&"font_outline_color", &"TitleLabel", UiTheme.OUTLINE_DARK)
	theme.set_constant(&"outline_size", &"TitleLabel", TITLE_OUTLINE)

	theme.set_type_variation(&"HeadingLabel", &"Label")
	theme.set_font(&"font", &"HeadingLabel", UiTheme.display_font())
	theme.set_font_size(&"font_size", &"HeadingLabel", HEADING_SIZE)
	theme.set_color(&"font_color", &"HeadingLabel", UiTheme.TEXT_BRIGHT)

	theme.set_type_variation(&"DimLabel", &"Label")
	theme.set_color(&"font_color", &"DimLabel", UiTheme.TEXT_DIM)

	theme.set_type_variation(&"BadgeLabel", &"Label")
	var badge := UiTheme.flat(UiTheme.TILE_BG, UiTheme.RADIUS_SMALL)
	badge.set_border_width_all(UiTheme.BADGE_BORDER_WIDTH)
	badge.border_color = UiTheme.BADGE_BORDER
	badge.content_margin_left = UiTheme.BADGE_MARGIN.x
	badge.content_margin_right = UiTheme.BADGE_MARGIN.x
	badge.content_margin_top = UiTheme.BADGE_MARGIN.y
	badge.content_margin_bottom = UiTheme.BADGE_MARGIN.y
	theme.set_stylebox(&"normal", &"BadgeLabel", badge)
	theme.set_font(&"font", &"BadgeLabel", UiTheme.display_font())


func _add_buttons(theme: Theme) -> void:
	_set_button(theme, &"Button", UiTheme.ACCENT, false)
	for variation: StringName in [&"PrimaryButton", &"DangerButton"]:
		theme.set_type_variation(variation, &"Button")
	_set_button(theme, &"PrimaryButton", UiTheme.ACCENT, true)
	_set_button(theme, &"DangerButton", UiTheme.ACCENT_RED, true)


func _set_button(theme: Theme, type: StringName, accent: Color, filled: bool) -> void:
	var states := UiTheme.button_states(accent, filled)
	for state: String in states:
		theme.set_stylebox(state, type, states[state])
	theme.set_font(&"font", type, UiTheme.display_font())
	theme.set_font_size(&"font_size", type, UiTheme.BUTTON_TEXT_SIZE)
	for color_name: StringName in [&"font_color", &"font_hover_color",
			&"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		theme.set_color(color_name, type, UiTheme.BUTTON_TEXT)
	theme.set_color(&"font_disabled_color", type, UiTheme.BUTTON_TEXT_DISABLED)


func _add_panels(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"PanelContainer", UiTheme.panel())
	theme.set_stylebox(&"panel", &"Panel", UiTheme.panel())
	theme.set_type_variation(&"CardPanel", &"PanelContainer")
	var card := UiTheme.panel(UiTheme.CARD_BG, UiTheme.INK, 16.0, 12.0)
	card.set_corner_radius_all(UiTheme.RADIUS)
	UiTheme.add_hard_shadow(card, UiTheme.CARD_SHADOW_OFFSET)
	theme.set_stylebox(&"panel", &"CardPanel", card)


func _add_bars(theme: Theme) -> void:
	var trough := UiTheme.flat(UiTheme.BAR_TROUGH, UiTheme.RADIUS_SMALL)
	trough.set_border_width_all(UiTheme.BAR_TROUGH_BORDER_WIDTH)
	trough.border_color = UiTheme.BAR_TROUGH_BORDER
	theme.set_stylebox(&"background", &"ProgressBar", trough)
	theme.set_stylebox(&"fill", &"ProgressBar",
			UiTheme.bar_fill(UiTheme.ACCENT_MINT, UiTheme.RADIUS_SMALL))
	theme.set_font(&"font", &"ProgressBar", UiTheme.display_font())
	theme.set_color(&"font_color", &"ProgressBar", UiTheme.TEXT_BRIGHT)
	theme.set_color(&"font_outline_color", &"ProgressBar", UiTheme.OUTLINE_DARK)

	var track := UiTheme.flat(UiTheme.BAR_TROUGH, SLIDER_TRACK_HEIGHT / 2)
	track.content_margin_top = SLIDER_TRACK_HEIGHT * 0.5
	track.content_margin_bottom = SLIDER_TRACK_HEIGHT * 0.5
	var track_fill := UiTheme.flat(UiTheme.ACCENT, SLIDER_TRACK_HEIGHT / 2)
	theme.set_stylebox(&"slider", &"HSlider", track)
	theme.set_stylebox(&"grabber_area", &"HSlider", track_fill)
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", track_fill)
	var grabber := UiTheme.grabber_icon(UiTheme.PAPER, SLIDER_GRABBER_SIZE)
	for icon_name: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
		theme.set_icon(icon_name, &"HSlider", grabber)


func _add_scroll(theme: Theme) -> void:
	var track := UiTheme.flat(UiTheme.BAR_TROUGH, SCROLL_RADIUS)
	track.content_margin_left = SCROLL_WIDTH * 0.5
	track.content_margin_right = SCROLL_WIDTH * 0.5
	var grabber := UiTheme.flat(UiTheme.TEXT_FAINT, SCROLL_RADIUS)
	var grabber_lit := UiTheme.flat(UiTheme.PAPER, SCROLL_RADIUS)
	theme.set_stylebox(&"scroll", &"VScrollBar", track)
	theme.set_stylebox(&"scroll_focus", &"VScrollBar", track)
	theme.set_stylebox(&"grabber", &"VScrollBar", grabber)
	theme.set_stylebox(&"grabber_highlight", &"VScrollBar", grabber_lit)
	theme.set_stylebox(&"grabber_pressed", &"VScrollBar", grabber_lit)


func _add_tooltip(theme: Theme) -> void:
	var box := UiTheme.flat(UiTheme.INK, UiTheme.RADIUS_SMALL)
	box.content_margin_left = TOOLTIP_MARGIN.x
	box.content_margin_right = TOOLTIP_MARGIN.x
	box.content_margin_top = TOOLTIP_MARGIN.y
	box.content_margin_bottom = TOOLTIP_MARGIN.y
	theme.set_stylebox(&"panel", &"TooltipPanel", box)
	theme.set_color(&"font_color", &"TooltipLabel", UiTheme.TEXT_BRIGHT)
