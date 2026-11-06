class_name AnnounceBanner
extends Label
## Cartel de anuncios arriba al centro. announce() es el aviso normal (jefes,
## altares, eventos, objetos); announce_major() es el de recompensa
## (evoluciones, etapa nueva, supervivencia): dorado, con un golpe de escala y
## más tiempo en pantalla. El HUD los reenvía desde los grupos "hud" y "boss_ui".

@export_group("Aviso normal")
## Color del texto del aviso normal.
@export var normal_color: Color = Color(1.0, 1.0, 1.0)
## Segundos de aparición.
@export var fade_in_time: float = 0.3
## Segundos que el aviso queda en pantalla.
@export var hold_time: float = 2.4
## Segundos de desvanecido.
@export var fade_out_time: float = 0.6
@export_group("Aviso de recompensa")
## Color del texto del aviso de recompensa.
@export var major_color: Color = UiTheme.ACCENT_AMBER
## Segundos de aparición.
@export var major_fade_in_time: float = 0.15
## Segundos que el aviso queda en pantalla.
@export var major_hold_time: float = 3.2
## Segundos de desvanecido.
@export var major_fade_out_time: float = 0.6
## Escala máxima del golpe al aparecer.
@export var major_pop_scale: float = 1.35
## Duración del golpe, en segundos.
@export var major_pop_time: float = 0.4
@export_group("Letra")
## Espacio extra entre letras, en píxeles.
@export var letter_spacing: int = 3

var _tween: Tween


func _ready() -> void:
	add_theme_font_override("font", UiTheme.spaced_font(letter_spacing))


## Un cartel breve que se desvanece solo.
func announce(message: String) -> void:
	_reset_style()
	text = message
	visible = true
	modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_in_time)
	_tween.tween_interval(hold_time)
	_tween.tween_property(self, "modulate:a", 0.0, fade_out_time)
	_tween.tween_callback(hide)


## El cartel de recompensa: color dorado, golpe de escala y más tiempo.
func announce_major(message: String) -> void:
	_reset_style()
	text = message
	add_theme_color_override("font_color", major_color)
	visible = true
	modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, major_fade_in_time)
	_tween.tween_interval(major_hold_time)
	_tween.tween_property(self, "modulate:a", 0.0, major_fade_out_time)
	_tween.tween_callback(func() -> void:
		hide()
		# Devuelve el color normal para el próximo anuncio simple.
		_reset_style())
	UiTheme.pop(self, major_pop_scale, major_pop_time)


## Limpia lo que dejó el cartel anterior (el color de recompensa, un golpe de
## escala a medias). Sin esto, un announce() dentro de la ventana de
## announce_major mata la animación que iba a limpiar, y todos los carteles
## siguientes de la partida quedan dorados y un poco agrandados.
func _reset_style() -> void:
	UiTheme.kill_meta_tween(self, &"ui_pop_tween")
	add_theme_color_override("font_color", normal_color)
	scale = Vector2.ONE
