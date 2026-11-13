class_name UiTheme
extends RefCounted
## Sistema de diseño de la UI, estilo "cómic de kiosko": contorno de tinta
## grueso, sombra dura desplazada, colores planos y dos fuentes (Lilita One
## para títulos y botones, Nunito para texto). De aquí sacan menús, cartas,
## barras y botones sus StyleBoxFlat y su movimiento, para que todo el juego
## comparta paleta, radios, bordes y estados. También es dueño del vocabulario
## de movimiento: crecer con el mouse o el foco, aplastar al presionar
## (attach_motion) y el golpe "pop". Todos los tweens ignoran
## Engine.time_scale (seguros con hit-stop) y van atados al control, así que
## las capas que procesan en pausa siguen animando.
## Es estático y nunca va en una escena: edita los valores aquí. El Theme
## global (assets/ui/theme/game_theme.tres) se genera desde estos valores con
## scripts/tools/build_ui_theme.gd: después de cambiar un color o una medida
## aquí, vuelve a correr esa herramienta.

# --- fuentes -------------------------------------------------------------------
## Títulos y botones (Lilita One) y texto de lectura (Nunito, fuente variable:
## TEXT_WEIGHT elige su grosor). Se cargan al primer uso (display_font,
## text_font) y no con preload: en un clon recién bajado los scripts se
## compilan antes de que Godot importe las fuentes.
const DISPLAY_FONT_PATH := "res://assets/ui/fonts/LilitaOne-Regular.ttf"
const TEXT_FONT_PATH := "res://assets/ui/fonts/Nunito-Variable.ttf"
## Grosor del texto de lectura (400 normal, 700 negrita, 900 la más gruesa).
const TEXT_WEIGHT := 700
## Tamaño de letra por defecto del texto y de los botones, en píxeles.
const TEXT_SIZE := 16
const BUTTON_TEXT_SIZE := 19

# --- paleta ------------------------------------------------------------------
## Tinta: contornos, sombras duras y texto sobre papel o amarillo.
const INK := Color("15131a")
## Fondo petróleo de respaldo, cuando una pantalla no muestra el mapa detrás.
const BACKDROP := Color("12343b")
## Papel: texto claro y cuerpo de los botones normales.
const PAPER := Color("fff4dc")
const PANEL_BG := Color("143c44", 0.97)
const CARD_BG := Color("1b4b54")
const CARD_BG_HOVER := Color("246370")
const CARD_BG_PRESSED := Color("0f2e34")
## Borde neutro: la tinta.
const BORDER_DIM := INK
const BORDER_LOCKED := Color("0c2327")
const ACCENT := Color("ffd23f")  ## amarillo: acciones, botón principal y foco
const ACCENT_AMBER := Color("ffa62b")  ## oro: jefes, legendario (amarillo más cálido)
const ACCENT_RED := Color("f2542d")  ## rojo naranja: peligro y "no alcanza"
const ACCENT_MINT := Color("5bd6a0")  ## menta: logros, vida, experiencia
const SHARD_BLUE := Color("7fd4f0")
const TEXT_BRIGHT := PAPER
## Texto secundario: teñido hacia el petróleo del fondo, nunca gris puro.
const TEXT_DIM := Color("c3d6d0")
const TEXT_FAINT := Color("93b0ab")
## Texto normal sobre paneles oscuros (etiquetas de ajustes, botones de co-op).
const TEXT_NORMAL := Color("ece2ca")
const OUTLINE_DARK := INK
## Fondo oscuro de chips y filas del HUD y de los modales, opaco: cada uso le
## pone su alfa con Color(UiTheme.TILE_BG, alfa).
const TILE_BG := Color("0d2227")
## Destello (modulate) de "no alcanza" (ver reject).
const REJECT_FLASH := Color(1.0, 0.5, 0.4)
## Verde de la experiencia: barra de XP del HUD, anillo de subida de nivel
## (juice.gd) y baliza de essence_rift (world_director.gd). El material de las
## gemas (XpGem.tscn) guarda el mismo verde en su escena: cámbialo ahí también.
const XP_GREEN := ACCENT_MINT

## Sombra dura (add_hard_shadow): tinta sin difuminar, desplazada hacia abajo.
## Desplazamiento en píxeles para paneles, cartas y botones; SHADOW_BLUR es el
## borde suavizado mínimo que Godot necesita para dibujarla (1 = casi nítida).
const SHADOW_COLOR := INK
const SHADOW_BLUR := 1
const PANEL_SHADOW_OFFSET := Vector2(0.0, 7.0)
const CARD_SHADOW_OFFSET := Vector2(0.0, 5.0)
const BUTTON_SHADOW_OFFSET := Vector2(0.0, 4.0)
## Texto de los botones: tinta sobre papel o sobre su color de acento.
const BUTTON_TEXT := INK
## Texto de un botón deshabilitado.
const BUTTON_TEXT_DISABLED := Color("15131a", 0.45)
## Borde por defecto de las chapas y píldoras (style_badge).
const BADGE_BORDER := INK
## Pista del interruptor apagado (toggle_icon); encendido usa su acento.
const TOGGLE_TRACK_OFF := Color("0d2227")
## Canal de las barras (style_bar): fondo y borde.
const BAR_TROUGH := Color("0d2227")
const BAR_TROUGH_BORDER := INK

## Radio de las esquinas (píxeles): paneles y cartas, chips y botones.
const RADIUS := 14
const RADIUS_SMALL := 9

## Anillo de foco (focus_ring): el contorno amarillo que marca dónde está el
## mando o el teclado. Va por fuera del borde de tinta del control. Grosor y
## cuánto sobresale, en píxeles.
const FOCUS_COLOR := ACCENT
const FOCUS_RING_WIDTH := 4
const FOCUS_RING_EXPAND := 6.0

## Escala de un botón al pasar el mouse y al presionarlo, y duración del
## tween (segundos).
const HOVER_GROW := 1.04
const PRESS_SQUASH := 0.97
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

# --- medidas de los estilos ---------------------------------------------------
# Los números con que las funciones de abajo dibujan cada pieza.

## Panel (panel): radio de las esquinas y grosor del borde de tinta, en píxeles.
const PANEL_RADIUS := RADIUS + 2
const PANEL_BORDER_WIDTH := 4
## Botón (button_states): radio de las esquinas, grosor del borde de tinta y
## margen interior (horizontal, vertical), en píxeles.
const BUTTON_RADIUS := RADIUS_SMALL + 3
const BUTTON_BORDER_WIDTH := 3
const BUTTON_MARGIN := Vector2(16.0, 7.0)
## Cuánto se aclara el cuerpo de un botón con el mouse encima y cuánto se
## oscurece presionado (0-1).
const BUTTON_HOVER_LIGHTEN := 0.35
const BUTTON_PRESSED_DARKEN := 0.18
## Cuánto se mezcla el cuerpo de un botón deshabilitado con el fondo (0-1).
const BUTTON_DISABLED_FADE := 0.55
## Cuánto se aclara el borde de una carta con el mouse encima o con foco (0-1).
const CARD_HIGHLIGHT_LIGHTEN := 0.2
## Píldora (style_badge): grosor del borde y margen interior (horizontal,
## vertical), en píxeles.
const BADGE_BORDER_WIDTH := 2
const BADGE_MARGIN := Vector2(12.0, 3.0)
## Cuánto más oscuro que su texto es el borde de la píldora de esquirlas del
## selector y de las pantallas meta (0-1).
const BADGE_EDGE_DARKEN := 0.45
## Golpe "pop": parte de la duración que toma la subida (0-1); el resto es la
## vuelta con rebote.
const POP_RISE_SHARE := 0.35
## Agarrador de slider (grabber_icon): hasta dónde es sólido y dónde termina
## su borde suave, como fracción del radio (0-1).
const GRABBER_SOLID := 0.78
const GRABBER_EDGE := 0.86
## Interruptor (toggle_icon): cuánto se oscurece la pista y se aclara el
## contorno al estar encendido (0-1), y el grosor del contorno y el hueco
## entre la perilla y el borde, en píxeles.
const TOGGLE_TRACK_DARKEN := 0.25
const TOGGLE_RIM_LIGHTEN := 0.2
const TOGGLE_RIM_WIDTH := 1.5
const TOGGLE_KNOB_INSET := 4.0
## Anillo de foco del interruptor (style_toggle): grosor, radio de las
## esquinas y cuánto sobresale, en píxeles.
const TOGGLE_RING_WIDTH := 3
const TOGGLE_RING_RADIUS := 17
const TOGGLE_RING_EXPAND := 4.0
## Barra (style_bar, bar_fill): grosor del borde del canal, de la línea de
## brillo de arriba y de la marca del borde de avance, en píxeles, y cuánto
## más claras que el relleno son esa línea y esa marca (0-1).
const BAR_TROUGH_BORDER_WIDTH := 3
const BAR_SHINE_WIDTH := 3
const BAR_EDGE_WIDTH := 3
const BAR_EDGE_LIGHTEN := 0.35

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
	var box := flat(bg, PANEL_RADIUS)
	box.border_color = border
	box.set_border_width_all(PANEL_BORDER_WIDTH)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	add_hard_shadow(box, PANEL_SHADOW_OFFSET)
	return box


## Sombra dura de cómic: tinta sin difuminar, desplazada. Es la única forma de
## dar altura a un panel, una carta o un botón.
static func add_hard_shadow(box: StyleBoxFlat, offset: Vector2) -> void:
	box.shadow_color = SHADOW_COLOR
	box.shadow_size = SHADOW_BLUR
	box.shadow_offset = offset


## Brillo exterior suave con la sombra del stylebox. Reservado a lo "ganado"
## (misiones por reclamar, bordes de rareza, barra del jefe): si todo brilla,
## nada destaca.
static func add_glow(box: StyleBoxFlat, color: Color, size: int = 8,
		alpha: float = 0.35) -> void:
	box.shadow_color = Color(color.r, color.g, color.b, alpha)
	box.shadow_size = size
	box.shadow_offset = Vector2.ZERO


## Anillo de foco: solo contorno, por fuera del borde del control. Un Button
## dibuja su stylebox "focus" ENCIMA del estado normal, así que el anillo se
## suma al botón en vez de reemplazarlo.
static func focus_ring(radius: int = RADIUS) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = FOCUS_COLOR
	ring.set_border_width_all(FOCUS_RING_WIDTH)
	ring.set_corner_radius_all(radius + int(FOCUS_RING_EXPAND))
	ring.set_expand_margin_all(FOCUS_RING_EXPAND)
	return ring


## Los estados de un botón en un diccionario. filled = botón principal: cuerpo
## en su color de acento. Sin relleno el cuerpo es papel y, presionado, toma
## el acento: así un botón de alternar (la calidad gráfica) muestra cuál está
## elegido. Siempre contorno de tinta y sombra dura; presionado pierde la
## sombra (se hunde).
static func button_states(accent: Color = ACCENT,
		filled: bool = false) -> Dictionary[String, StyleBoxFlat]:
	var body := accent if filled else PAPER
	var states: Dictionary[String, StyleBoxFlat] = {}
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := flat(body, BUTTON_RADIUS)
		box.set_border_width_all(BUTTON_BORDER_WIDTH)
		box.border_color = INK
		box.content_margin_left = BUTTON_MARGIN.x
		box.content_margin_right = BUTTON_MARGIN.x
		box.content_margin_top = BUTTON_MARGIN.y
		box.content_margin_bottom = BUTTON_MARGIN.y
		match state:
			"hover":
				box.bg_color = body.lightened(BUTTON_HOVER_LIGHTEN)
			"pressed", "hover_pressed":
				box.bg_color = accent.darkened(BUTTON_PRESSED_DARKEN) if filled else accent
			"disabled":
				box.bg_color = body.lerp(PANEL_BG, BUTTON_DISABLED_FADE)
		if not state.ends_with("pressed"):
			add_hard_shadow(box, BUTTON_SHADOW_OFFSET)
		states[state] = box
	states["focus"] = focus_ring(BUTTON_RADIUS)
	return states


## EL aspecto de carta de toda superficie de "elige una" (cartas de mejora,
## raiders, botones de co-op): un cuerpo por estado, el acento como borde
## grueso, sombra dura y el anillo de foco amarillo encima (teclado y control
## navegan por ese anillo).
##
## Con `glow` apagado es el aspecto quieto de las cartas no elegidas y
## bloqueadas: solo borde, sin sombra, para que se levante la elegida.
static func style_card(button: Button, border: Color, width: int = 3,
		glow: bool = true) -> void:
	var bodies: Dictionary[String, Color] = {
		"normal": CARD_BG,
		"hover": CARD_BG_HOVER,
		"pressed": CARD_BG_PRESSED,
	}
	for state: String in bodies:
		var box := flat(bodies[state], RADIUS)
		box.border_color = border.lightened(CARD_HIGHLIGHT_LIGHTEN) \
				if state == "hover" else border
		box.set_border_width_all(width)
		if glow and state != "pressed":
			add_hard_shadow(box, CARD_SHADOW_OFFSET)
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", focus_ring(RADIUS))


## Aplica el sistema completo a un Button: styleboxes por estado, colores de
## texto y el movimiento de crecer y aplastar. Es la entrada que usa toda
## pantalla.
static func style_button(button: Button, accent: Color = ACCENT,
		filled: bool = false) -> void:
	var states := button_states(accent, filled)
	for state: String in states:
		button.add_theme_stylebox_override(state, states[state])
	for color_name: String in ["font_color", "font_hover_color",
			"font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color_name, BUTTON_TEXT)
	button.add_theme_color_override("font_disabled_color", BUTTON_TEXT_DISABLED)
	attach_motion(button)


# --- movimiento --------------------------------------------------------------

## Crece con el mouse o el foco y se aplasta al presionar, centrado en el
## pivote: el mando recibe la misma respuesta que el mouse.
## Idempotente: la primera llamada gana y conecta una sola vez por botón. La
## escala es solo visual dentro de un contenedor, así que el layout no se mueve.
static func attach_motion(button: BaseButton, grow: float = HOVER_GROW,
		squash: float = PRESS_SQUASH) -> void:
	if button.has_meta(&"ui_motion"):
		return
	button.set_meta(&"ui_motion", true)
	button.mouse_entered.connect(_scale_to.bind(button, grow))
	button.focus_entered.connect(_scale_to.bind(button, grow))
	var rest := func() -> void:
		_scale_to(button, grow if _is_lit(button) else 1.0)
	button.mouse_exited.connect(rest)
	button.focus_exited.connect(rest)
	button.button_down.connect(_scale_to.bind(button, squash))
	button.button_up.connect(rest)


## El botón tiene el mouse encima o el foco: se queda crecido.
static func _is_lit(button: BaseButton) -> bool:
	return button.is_hovered() or button.has_focus()


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
	tween.tween_property(control, "scale", Vector2.ONE * peak, duration * POP_RISE_SHARE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, duration * (1.0 - POP_RISE_SHARE)) \
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
static var _display_fonts: Dictionary[int, FontVariation] = {}
static var _text_font: FontVariation = null


## La fuente de display (títulos, botones, chapas) con `spacing` píxeles
## extra entre letras.
static func display_font(spacing: int = 0) -> FontVariation:
	if not _display_fonts.has(spacing):
		var font := FontVariation.new()
		font.base_font = load(DISPLAY_FONT_PATH) as FontFile
		font.spacing_glyph = spacing
		_display_fonts[spacing] = font
	return _display_fonts[spacing]


## Nunito en el grosor de TEXT_WEIGHT: la fuente por defecto del Theme.
static func text_font() -> FontVariation:
	if _text_font == null:
		_text_font = FontVariation.new()
		_text_font.base_font = load(TEXT_FONT_PATH) as FontFile
		var weight_tag := TextServerManager.get_primary_interface().name_to_tag("wght")
		_text_font.variation_opentype = {weight_tag: TEXT_WEIGHT}
	return _text_font


## Mismo nombre que usan los scripts de cada pantalla para sus rótulos:
## devuelve la fuente de display con ese espaciado.
static func spaced_font(spacing: int) -> FontVariation:
	return display_font(spacing)


## Tratamiento de titular: letras espaciadas, contorno oscuro y color.
static func style_title(label: Label, font_size: int, color: Color,
		spacing: int = 6, outline: int = 10) -> void:
	label.add_theme_font_override("font", display_font(spacing))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", outline)


## Chapa pequeña para chips del HUD, saldos y cintas: caja oscura con borde,
## texto en la fuente de display.
static func style_badge(label: Label, text_color: Color,
		bg: Color = PANEL_BG, border: Color = BADGE_BORDER) -> void:
	var box := flat(bg, RADIUS_SMALL)
	box.set_border_width_all(BADGE_BORDER_WIDTH)
	box.border_color = border
	box.content_margin_left = BADGE_MARGIN.x
	box.content_margin_right = BADGE_MARGIN.x
	box.content_margin_top = BADGE_MARGIN.y
	box.content_margin_bottom = BADGE_MARGIN.y
	label.add_theme_stylebox_override("normal", box)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_font_override("font", display_font())


# --- widgets ------------------------------------------------------------------

## Agarrador redondo de slider hecho con un degradado radial (sin texturas).
static func grabber_icon(color: Color, diameter: int = 18) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color, color, Color(color, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, GRABBER_SOLID, GRABBER_EDGE])
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
	var track := accent.darkened(TOGGLE_TRACK_DARKEN) if on else TOGGLE_TRACK_OFF
	var rim := accent.lightened(TOGGLE_RIM_LIGHTEN) if on else BORDER_DIM
	var knob := TEXT_BRIGHT if on else TEXT_FAINT
	var knob_center := Vector2(width - radius if on else radius, radius)
	var knob_radius := radius - TOGGLE_KNOB_INSET
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
			if d_track > -TOGGLE_RIM_WIDTH:
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
	ring.border_color = FOCUS_COLOR
	ring.set_border_width_all(TOGGLE_RING_WIDTH)
	ring.set_corner_radius_all(TOGGLE_RING_RADIUS)
	ring.set_expand_margin_all(TOGGLE_RING_EXPAND)
	check.add_theme_stylebox_override("focus", ring)
	check.focus_mode = Control.FOCUS_ALL
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Barra en capas: canal oscuro y relleno redondeado con una línea de brillo
## arriba y una marca más clara en el borde de avance (borde derecho del
## relleno). Devuelve el relleno para recolorearlo en vivo (vida verde→rojo).
static func style_bar(bar: ProgressBar, fill_color: Color, radius: int = 6,
		inset: int = 3) -> StyleBoxFlat:
	var trough := flat(BAR_TROUGH, radius + 1)
	trough.set_border_width_all(BAR_TROUGH_BORDER_WIDTH)
	trough.border_color = BAR_TROUGH_BORDER
	trough.set_content_margin_all(inset)
	bar.add_theme_stylebox_override("background", trough)
	var fill := bar_fill(fill_color, radius - 1)
	bar.add_theme_stylebox_override("fill", fill)
	return fill


static func bar_fill(color: Color, radius: int = 5) -> StyleBoxFlat:
	var fill := flat(color, radius)
	fill.border_width_top = BAR_SHINE_WIDTH
	fill.border_width_right = BAR_EDGE_WIDTH
	fill.border_color = color.lightened(BAR_EDGE_LIGHTEN)
	return fill


## Mantiene al día el brillo y la marca cuando un relleno cambia de color.
static func recolor_fill(fill: StyleBoxFlat, color: Color) -> void:
	fill.bg_color = color
	fill.border_color = color.lightened(BAR_EDGE_LIGHTEN)
