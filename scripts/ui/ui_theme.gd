class_name UiTheme
extends RefCounted
## Sistema de diseño de la UI: de aquí sacan menús, cartas, barras y
## botones sus StyleBoxFlat y su movimiento al pasar el mouse o presionar,
## para que todo el juego comparta paleta (fondo azul negro, turquesa para
## acciones, ámbar para jefes, oro y legendario, azul de esquirla), radios,
## bordes y estados. También es dueño del vocabulario de movimiento: crecer
## al pasar el mouse y aplastar al presionar (attach_motion) y el golpe "pop".
## Todos los tweens ignoran Engine.time_scale (seguros con hit-stop) y van
## atados al control, así que las capas que procesan en pausa siguen animando.
## Es estático y nunca va en una escena: edita los valores aquí.

# --- paleta ------------------------------------------------------------------
const PANEL_BG := Color(0.09, 0.1, 0.145, 0.96)
const CARD_BG := Color(0.115, 0.125, 0.17, 0.98)
const CARD_BG_HOVER := Color(0.16, 0.175, 0.24, 0.98)
const CARD_BG_PRESSED := Color(0.085, 0.09, 0.125, 0.98)
const BORDER_DIM := Color(0.29, 0.315, 0.4)
const BORDER_LOCKED := Color(0.2, 0.21, 0.26)
const ACCENT := Color(0.3, 0.82, 0.76)  ## turquesa: acciones y botón principal
const ACCENT_AMBER := Color(0.98, 0.76, 0.28)  ## jefes, oro, legendario
const ACCENT_RED := Color(0.92, 0.28, 0.24)
const SHARD_BLUE := Color(0.55, 0.8, 0.92)
const TEXT_BRIGHT := Color(0.96, 0.97, 0.99)
const TEXT_DIM := Color(0.66, 0.69, 0.75)
const TEXT_FAINT := Color(0.47, 0.5, 0.56)
## Texto normal sobre paneles oscuros (etiquetas de ajustes, botones de co-op).
const TEXT_NORMAL := Color(0.85, 0.87, 0.9)
const OUTLINE_DARK := Color(0.03, 0.035, 0.06, 0.92)
## Fondo oscuro de chips y filas del HUD y de los modales, opaco: cada uso le
## pone su alfa con Color(UiTheme.TILE_BG, alfa).
const TILE_BG := Color(0.07, 0.075, 0.11)
## Destello (modulate) de "no alcanza" (ver reject).
const REJECT_FLASH := Color(1.0, 0.42, 0.42)
## Verde de la experiencia: barra de XP del HUD, anillo de subida de nivel
## (juice.gd) y baliza de essence_rift (world_director.gd). El material de las
## gemas (XpGem.tscn) guarda el mismo verde en su escena: cámbialo ahí también.
const XP_GREEN := Color(0.35, 0.95, 0.6)

## Sombra de los paneles (panel): color y tamaño, en píxeles.
const PANEL_SHADOW := Color(0.0, 0.0, 0.0, 0.45)
const PANEL_SHADOW_SIZE := 14
## Texto de los botones sin relleno; los rellenos usan TEXT_BRIGHT.
const BUTTON_TEXT := Color(0.88, 0.9, 0.94)
## Borde por defecto de las chapas y píldoras (style_badge).
const BADGE_BORDER := Color(0, 0, 0, 0.5)
## Pista del interruptor apagado (toggle_icon); encendido usa su acento.
const TOGGLE_TRACK_OFF := Color(0.16, 0.17, 0.23)
## Canal de las barras (style_bar): fondo y borde.
const BAR_TROUGH := Color(0.04, 0.045, 0.07, 0.85)
const BAR_TROUGH_BORDER := Color(0.0, 0.0, 0.0, 0.6)

## Radio de las esquinas (píxeles): paneles y cartas, chips y botones.
const RADIUS := 10
const RADIUS_SMALL := 7

## Brillo exterior de una carta en el color de su borde (style_card): tamaño
## (píxeles) y alfa. El hover y el foco suman el mismo alfa extra, así que el
## anillo de foco de un control se lee igual de fuerte que el hover del mouse.
const CARD_GLOW_SIZE := 10
const CARD_GLOW_ALPHA := 0.3
const CARD_GLOW_HIGHLIGHT := 0.2

## Escala de un botón al pasar el mouse y al presionarlo, y duración del
## tween (segundos).
const HOVER_GROW := 1.04
const PRESS_SQUASH := 0.95
const MOTION_TIME := 0.12
## Vaivén de "no alcanza" de cartas y botones (ver reject): ángulo (grados)
## de cada paso y su duración (segundos).
const REJECT_SWINGS: Array[float] = [-4.0, 4.0, -2.0, 0.0]
const REJECT_SWING_TIMES: Array[float] = [0.05, 0.08, 0.07, 0.06]
## El vaivén más suave de las filas de las pantallas meta.
const REJECT_SWINGS_ROW: Array[float] = [-2.0, 2.0, 0.0]
const REJECT_SWING_TIMES_ROW: Array[float] = [0.05, 0.08, 0.07]
## Duración (segundos) del destello rojo y de su vuelta al modulate de reposo.
const REJECT_FLASH_TIME := 0.06
const REJECT_RESTORE_TIME := 0.18

# --- textos compartidos ------------------------------------------------------

## Dos escalas de "nivel" que el jugador lee lado a lado: el nivel de la
## PARTIDA (chapa del HUD) y el nivel de mejora de un ARMA (esquina del
## equipamiento, filas de la Colección). Una constante para cada una, así
## cambiar la palabra llega a todas las pantallas a la vez.
const LEVEL_ABBREV := "Nv %d"
const WEAPON_LEVEL_ABBREV := "N%d"
## Saldo de esquirlas ("Esquirlas: 120"): selector y pantallas meta.
const SHARDS_BALANCE := "Esquirlas: %d"
## Cantidad de esquirlas ("120 esquirlas"): precios de raiders y de la Armería.
const SHARDS_AMOUNT := "%d esquirlas"
## Esquirlas ganadas ("+20 esquirlas"): recompensa de una misión.
const SHARDS_GAIN := "+%d esquirlas"
## Puntos de la partida ("35 pts"): HUD y precios del vendedor.
const POINTS_AMOUNT := "%d pts"
## Saldo de puntos en los paneles modales ("Tienes 35 pts").
const POINTS_BALANCE := "Tienes %d pts"
## Aviso de puntos insuficientes en los paneles modales.
const POINTS_SHORT := "No te alcanzan los puntos."
## Etiqueta de un jugador en co-op ("J2").
const PLAYER_TAG := "J%d"


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
	box.border_width_top = 3  # línea de acento del encabezado
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.shadow_color = PANEL_SHADOW
	box.shadow_size = PANEL_SHADOW_SIZE
	return box


## Brillo exterior suave con la sombra del stylebox (cartas elegidas, bordes
## de rareza, misiones por reclamar).
static func add_glow(box: StyleBoxFlat, color: Color, size: int = 8,
		alpha: float = 0.35) -> void:
	box.shadow_color = Color(color.r, color.g, color.b, alpha)
	box.shadow_size = size


## Los cuatro estados de un botón en un diccionario. filled = aspecto de
## botón principal: cuerpo teñido con el acento y texto claro encima.
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


## EL aspecto de carta de toda superficie de "elige una" (cartas de mejora,
## raiders, botones de co-op): un cuerpo por estado, el acento como borde y
## un brillo exterior que sube con el hover Y con el foco (teclado y control
## navegan por ese anillo, así que debe leerse igual de fuerte).
##
## Con `glow` apagado es el aspecto quieto de las cartas no elegidas y
## bloqueadas: solo borde, sin sombra, para que se encienda la elegida.
static func style_card(button: Button, border: Color, width: int = 3,
		glow: bool = true) -> void:
	var bodies: Dictionary[String, Color] = {
		"normal": CARD_BG,
		"hover": CARD_BG_HOVER,
		"pressed": CARD_BG_PRESSED,
		"focus": CARD_BG_HOVER,
	}
	for state: String in bodies:
		var highlighted := state == "hover" or state == "focus"
		var box := flat(bodies[state], RADIUS)
		box.border_color = border.lightened(0.2) if highlighted else border
		box.set_border_width_all(width)
		if glow:
			add_glow(box, border, CARD_GLOW_SIZE,
					(CARD_GLOW_ALPHA + CARD_GLOW_HIGHLIGHT) if highlighted
					else CARD_GLOW_ALPHA)
		button.add_theme_stylebox_override(state, box)


## Aplica el sistema completo a un Button: styleboxes por estado, colores de
## texto y el movimiento de crecer y aplastar. Es la entrada que usa toda
## pantalla.
static func style_button(button: Button, accent: Color = ACCENT,
		filled: bool = false) -> void:
	var states := button_states(accent, filled)
	for state: String in states:
		button.add_theme_stylebox_override(state, states[state])
	button.add_theme_color_override("font_color",
			TEXT_BRIGHT if filled else BUTTON_TEXT)
	button.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	button.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	button.add_theme_color_override("font_focus_color", TEXT_BRIGHT)
	attach_motion(button)


# --- movimiento --------------------------------------------------------------

## Crece al pasar el mouse y se aplasta al presionar, centrado en el pivote.
## Idempotente: la primera llamada gana y conecta una sola vez por botón. La
## escala es solo visual dentro de un contenedor, así que el layout no se mueve.
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


## Golpe de atención (chapa de nivel, contador de esquirlas, carta elegida):
## escala hacia arriba y vuelve. Se puede interrumpir: repetirlo reinicia limpio.
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


## Respuesta de "no alcanza": destello rojo (REJECT_FLASH) y un vaivén de
## rotación que recorre `swings` (grados), cada paso con su tiempo en
## `swing_times` (segundos); con el último paso el modulate vuelve a
## `rest_modulate`. La rotación no pelea con el layout de un contenedor como
## lo haría la posición. El tween queda en la metadata `meta_key`: repetirlo
## lo reinicia en vez de apilar tweens.
static func reject(control: Control, swings: Array[float] = REJECT_SWINGS,
		swing_times: Array[float] = REJECT_SWING_TIMES,
		rest_modulate: Color = Color.WHITE,
		meta_key: StringName = &"ui_reject_tween") -> void:
	control.pivot_offset = control.size * 0.5
	kill_meta_tween(control, meta_key)
	var tween := control.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(control, "modulate", REJECT_FLASH, REJECT_FLASH_TIME)
	for i in swings.size():
		if i == 0:
			tween.parallel().tween_property(control, "rotation_degrees",
					swings[i], swing_times[i])
		else:
			tween.tween_property(control, "rotation_degrees", swings[i], swing_times[i])
	tween.parallel().tween_property(control, "modulate", rest_modulate,
			REJECT_RESTORE_TIME)
	control.set_meta(meta_key, tween)


## Mata el tween guardado en la metadata del nodo con esa llave (el patrón que
## mantiene idempotente cada animación al abrir y cerrar rápido).
static func kill_meta_tween(node: Node, key: StringName) -> void:
	if not node.has_meta(key):
		return
	var old: Variant = node.get_meta(key)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()


# --- tipografía --------------------------------------------------------------

## Un FontVariation compartido por valor de espaciado. Son inmutables una vez
## armados, así que compartirlos es seguro; uno nuevo por llamada invalidaría
## la caché de shaping del TextServer cada vez.
static var _spaced_fonts: Dictionary[int, FontVariation] = {}


## Fuente por defecto con espacio extra entre letras: el tratamiento de
## títulos y etiquetas espaciadas sin cargar una fuente.
static func spaced_font(spacing: int) -> FontVariation:
	if not _spaced_fonts.has(spacing):
		var font := FontVariation.new()
		font.base_font = ThemeDB.fallback_font
		font.spacing_glyph = spacing
		_spaced_fonts[spacing] = font
	return _spaced_fonts[spacing]


## Tratamiento de titular: letras espaciadas, contorno oscuro y color.
static func style_title(label: Label, font_size: int, color: Color,
		spacing: int = 6, outline: int = 10) -> void:
	label.add_theme_font_override("font", spaced_font(spacing))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", outline)


## Chapa o píldora pequeña para chips del HUD y cintas.
static func style_badge(label: Label, text_color: Color,
		bg: Color = PANEL_BG, border: Color = BADGE_BORDER) -> void:
	var box := flat(bg, RADIUS_SMALL)
	box.set_border_width_all(1)
	box.border_color = border
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	label.add_theme_stylebox_override("normal", box)
	label.add_theme_color_override("font_color", text_color)


# --- widgets ------------------------------------------------------------------

## Agarrador redondo de slider hecho con un degradado radial (sin texturas).
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


## Interruptor de píldora dibujado píxel a píxel (sin texturas), para los
## íconos on/off de un CheckButton. `on` corre la perilla a la derecha y llena
## la pista con el acento; apagado es una pista oscura con perilla gris. Los
## bordes se suavizan con la distancia con signo a la cápsula y a la perilla.
static func toggle_icon(on: bool, accent: Color = ACCENT,
		width: int = 46, height: int = 26) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var radius := height * 0.5
	var track := accent.darkened(0.25) if on else TOGGLE_TRACK_OFF
	var rim := accent.lightened(0.2) if on else BORDER_DIM
	var knob := TEXT_BRIGHT if on else TEXT_FAINT
	var knob_center := Vector2(width - radius if on else radius, radius)
	var knob_radius := radius - 4.0
	for y in height:
		for x in width:
			var p := Vector2(x + 0.5, y + 0.5)
			# Distancia a la cápsula: se acota al segmento entre los extremos.
			var cx := clampf(p.x, radius, width - radius)
			var d_track := p.distance_to(Vector2(cx, radius)) - (radius - 0.5)
			var a_track := clampf(0.5 - d_track, 0.0, 1.0)
			if a_track <= 0.0:
				continue
			var color := track
			if d_track > -1.5:
				color = rim
			var d_knob := p.distance_to(knob_center) - knob_radius
			color = color.lerp(knob, clampf(0.5 - d_knob, 0.0, 1.0))
			color.a = a_track
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


## CheckButton como interruptor de píldora: los íconos dibujados en cada
## estado, sin cromo de botón alrededor y un anillo de acento con el foco,
## para que teclado y control vean en qué interruptor están (misma regla que
## style_card: el foco se lee tan fuerte como el hover).
static func style_toggle(check: CheckButton, accent: Color = ACCENT) -> void:
	var on := toggle_icon(true, accent)
	var off := toggle_icon(false, accent)
	for icon_name: String in ["checked", "checked_disabled", "checked_mirrored",
			"checked_disabled_mirrored"]:
		check.add_theme_icon_override(icon_name, on)
	for icon_name: String in ["unchecked", "unchecked_disabled",
			"unchecked_mirrored", "unchecked_disabled_mirrored"]:
		check.add_theme_icon_override(icon_name, off)
	var none := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "hover_pressed",
			"disabled"]:
		check.add_theme_stylebox_override(state, none)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = accent
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(17)
	ring.set_expand_margin_all(4.0)
	add_glow(ring, accent, 6, 0.28)
	check.add_theme_stylebox_override("focus", ring)
	check.focus_mode = Control.FOCUS_ALL
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Barra en capas: canal oscuro y relleno redondeado con una línea de brillo
## arriba y una marca más clara en el borde de avance (borde derecho del
## relleno). Devuelve el relleno para recolorearlo en vivo (vida verde→rojo).
static func style_bar(bar: ProgressBar, fill_color: Color, radius: int = 6,
		inset: int = 3) -> StyleBoxFlat:
	var trough := flat(BAR_TROUGH, radius + 1)
	trough.set_border_width_all(2)
	trough.border_color = BAR_TROUGH_BORDER
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


## Mantiene al día el brillo y la marca cuando un relleno cambia de color.
static func recolor_fill(fill: StyleBoxFlat, color: Color) -> void:
	fill.bg_color = color
	fill.border_color = color.lightened(0.35)
