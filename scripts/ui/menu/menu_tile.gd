class_name MenuTile
extends Button
## Tarjeta grande del menú principal (Cacería, Misiones, Colección, Armería):
## un marco de color con contorno de tinta y sombra dura, apenas girado como
## un sticker, con un dibujo grande, el título, una línea de detalle y un dato
## vivo arriba.
##
## Solo gira y crece el MARCO (nodo Frame). El texto es hijo del botón, no del
## marco, así que queda siempre recto y nítido, y el rectángulo que usa el
## control para navegar tampoco gira. Con foco o mouse el marco se endereza,
## crece y muestra el anillo amarillo; al presionar se hunde. El dibujo
## acompaña: con foco sube, se inclina y crece un poco.
##
## El texto y el color de cada tarjeta se ponen en su instancia (MainMenu.tscn).

const STICKER_SHADER: Shader = preload("res://assets/ui/sticker_art.gdshader")

@export_group("Textos")
## Nombre de la sección, en grande.
@export var title_text: String = "Sección":
	set(value):
		title_text = value
		if is_node_ready():
			_title.text = value
## Una línea que explica qué hay adentro.
@export var detail_text: String = "":
	set(value):
		detail_text = value
		if is_node_ready():
			_detail.text = value

@export_group("Marco")
## Color del cuerpo de la tarjeta.
@export var tile_color: Color = UiTheme.ACCENT
## Giro del marco en reposo, en grados (el texto no gira).
@export var tilt_degrees: float = -2.0
## Grosor del contorno de tinta, en píxeles.
@export var border_width: int = 5
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = 20
## Sombra dura en reposo y con foco (desplazamiento en píxeles): con foco la
## tarjeta se levanta, así que su sombra cae más lejos.
@export var shadow_offset: Vector2 = Vector2(0.0, 8.0)
@export var shadow_offset_lifted: Vector2 = Vector2(0.0, 14.0)

@export_group("Dibujo")
## El dibujo de la sección (un SVG de assets/ui/icons o una foto). Vacío deja
## el hueco libre.
@export var art_texture: Texture2D = null:
	set(value):
		art_texture = value
		if is_node_ready():
			_art.texture = value
## Contorno de tinta alrededor del dibujo, en píxeles. 0 para los SVG, que ya
## traen su contorno dibujado; 4 para una foto.
@export var art_outline: float = 0.0
## Sombra dura del dibujo (desplazamiento en píxeles).
@export var art_shadow_offset: Vector2 = Vector2(0.0, 7.0)
## Aire alrededor del dibujo dentro de su hueco (0.08 = 8 % por lado).
@export_range(0.0, 0.3) var art_padding: float = 0.08
## Píxeles que sube el dibujo con foco o mouse encima.
@export var art_lift: float = 10.0
## Inclinación del dibujo con foco, en grados (negativo = hacia la izquierda).
@export var art_lit_tilt: float = -4.0
## Escala del dibujo con foco.
@export var art_lit_scale: float = 1.06
## Duración de la reacción del dibujo, en segundos.
@export var art_time: float = 0.18
## Duración del fundido cuando el dibujo llega tarde (la foto del raider).
@export var art_fade_time: float = 0.18

@export_group("Movimiento")
## Escala del marco con foco o mouse encima.
@export var focus_scale: float = 1.05
## Escala del marco mientras se presiona.
@export var press_scale: float = 0.97
## Duración del cambio de pose (reposo, foco, presionado), en segundos.
@export var pose_time: float = 0.12
## Duración de la entrada de la tarjeta, en segundos.
@export var entrance_time: float = 0.32
## Píxeles que sube la tarjeta al entrar.
@export var entrance_rise: float = 36.0

var _style: StyleBoxFlat
var _pose_tween: Tween = null
var _entrance_tween: Tween = null
var _art_fade_tween: Tween = null
## Cuánto está levantado el dibujo ahora, en píxeles.
var _art_rise: float = 0.0:
	set(value):
		_art_rise = value
		MenuNav.shift(Vector2(0.0, -value), _art)

@onready var _frame: Panel = %Frame
@onready var _ring: Panel = %Ring
@onready var _title: Label = %Title
@onready var _detail: Label = %Detail
@onready var _stat: Label = %Stat
@onready var _art: TextureRect = %Art


func _ready() -> void:
	_title.text = title_text
	_detail.text = detail_text
	_show_stat()
	var sticker := ShaderMaterial.new()
	sticker.shader = STICKER_SHADER
	sticker.set_shader_parameter(&"ink_color", UiTheme.INK)
	sticker.set_shader_parameter(&"outline_px", art_outline)
	sticker.set_shader_parameter(&"shadow_px", art_shadow_offset)
	sticker.set_shader_parameter(&"padding", art_padding)
	_art.material = sticker
	_art.texture = art_texture
	_art.resized.connect(_center_pivot)
	# El botón no dibuja nada propio: su aspecto entero es el marco.
	var none := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, none)
	_style = UiTheme.flat(tile_color, corner_radius)
	_style.set_border_width_all(border_width)
	_style.border_color = UiTheme.INK
	UiTheme.add_hard_shadow(_style, shadow_offset)
	_frame.add_theme_stylebox_override("panel", _style)
	_ring.add_theme_stylebox_override("panel", UiTheme.focus_ring(corner_radius))
	_ring.visible = false
	_frame.rotation_degrees = tilt_degrees
	_frame.resized.connect(_center_pivot)
	_center_pivot()
	focus_entered.connect(_refresh_pose)
	focus_exited.connect(_refresh_pose)
	mouse_entered.connect(_refresh_pose)
	mouse_exited.connect(_refresh_pose)
	button_down.connect(_refresh_pose)
	button_up.connect(_refresh_pose)


## El dato vivo de la esquina ("3 por reclamar", "42 %"). Vacío lo oculta.
func set_stat(text: String) -> void:
	_stat.text = text
	_show_stat()


## Cambia el dibujo con un fundido corto: para uno que llega después de abrir
## (la foto del último raider elegido).
func set_art(texture: Texture2D) -> void:
	art_texture = texture
	if _art_fade_tween != null and _art_fade_tween.is_valid():
		_art_fade_tween.kill()
	_art.modulate.a = 0.0
	_art_fade_tween = create_tween()
	_art_fade_tween.set_ignore_time_scale(true)
	_art_fade_tween.tween_property(_art, "modulate:a", 1.0, art_fade_time) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


## Entrada: el marco y el texto suben desde abajo y aparecen, tras `delay`
## segundos. Decorativa: el foco y los clics funcionan desde el primer frame.
func play_entrance(delay: float) -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	modulate.a = 0.0
	var content := %Content as Control
	var from := Vector2(0.0, entrance_rise)
	_entrance_tween = create_tween().set_parallel()
	_entrance_tween.set_ignore_time_scale(true)
	_entrance_tween.tween_property(self, "modulate:a", 1.0, entrance_time * 0.6) \
			.set_delay(delay)
	for node: Control in [_frame, content]:
		MenuNav.shift(from, node)
		_entrance_tween.tween_method(MenuNav.shift.bind(node), from, Vector2.ZERO,
				entrance_time).set_delay(delay) \
				.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


## Sin texto el dato se vuelve invisible pero conserva su alto: así el hueco
## del dibujo mide lo mismo en las cuatro tarjetas.
func _show_stat() -> void:
	_stat.modulate.a = 0.0 if _stat.text.is_empty() else 1.0


func _center_pivot() -> void:
	_frame.pivot_offset = _frame.size * 0.5
	_art.pivot_offset = _art.size * 0.5


## Lleva el marco a la pose que corresponde: presionado, encendido (foco o
## mouse) o reposo. Interrumpible: cada cambio parte de donde está el marco.
func _refresh_pose() -> void:
	var lit := has_focus() or is_hovered()
	var held := is_pressed()
	var target_scale := press_scale if held else (focus_scale if lit else 1.0)
	var target_tilt := 0.0 if lit else tilt_degrees
	var target_shadow := shadow_offset
	if lit and not held:
		target_shadow = shadow_offset_lifted
	_ring.visible = has_focus()
	z_index = 1 if lit else 0
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween().set_parallel()
	_pose_tween.set_ignore_time_scale(true)
	_pose_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(_frame, "scale", Vector2.ONE * target_scale, pose_time)
	_pose_tween.tween_property(_frame, "rotation_degrees", target_tilt, pose_time)
	_pose_tween.tween_property(_style, "shadow_offset", target_shadow, pose_time)
	# El dibujo: misma curva que el marco, un poco más largo para que se lea
	# como un gesto y no como un salto. Presionado se hunde con la tarjeta.
	var art_scale := press_scale if held else (art_lit_scale if lit else 1.0)
	_pose_tween.tween_property(_art, "scale", Vector2.ONE * art_scale, art_time)
	_pose_tween.tween_property(_art, "rotation_degrees",
			art_lit_tilt if lit else 0.0, art_time)
	_pose_tween.tween_property(self, "_art_rise",
			art_lift if lit and not held else 0.0, art_time)
