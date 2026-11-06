class_name StreakPopup
extends Label
## Texto de racha de bajas en el centro de la pantalla. Las bajas dentro de
## una ventana móvil cuentan para los niveles; al cruzar uno, su palabra entra
## grande e inclinada, se asienta, se mantiene y se desvanece, con un color
## más caliente en cada nivel. El HUD llama a on_kill() por cada baja nueva y
## a reset() cuando el contador vuelve a empezar.

## Sonido al disparar un nivel (id de Sfx).
const SOUND := &"streak"

@export_group("Racha")
## Segundos de la ventana móvil: sin bajas durante este tiempo la racha se
## corta y los niveles pueden volver a dispararse.
@export var window_seconds: float = 2.0
## Bajas dentro de la ventana para cada nivel, de menor a mayor.
@export var tier_kills: Array[int] = [8, 15, 25]
## Palabra de cada nivel, en el mismo orden que tier_kills.
@export var tier_words: Array[String] = ["¡TRITURANDO!", "¡ARRASANDO!", "¡IMPARABLE!"]
## Color de cada nivel, en el mismo orden: dorado, naranja, rojo fuego.
@export var tier_colors: Array[Color] = [
	Color(1.0, 0.86, 0.25), Color(1.0, 0.62, 0.16), Color(1.0, 0.34, 0.2)]
@export_group("Animación")
## Escala con la que entra el texto.
@export var slam_scale: float = 2.3
## Inclinación con la que entra, en grados.
@export var slam_tilt_degrees: float = -5.0
## Segundos que tarda en asentarse.
@export var settle_time: float = 0.2
## Segundos que queda quieto.
@export var hold_time: float = 0.55
## Segundos de desvanecido.
@export var fade_time: float = 0.3
@export_group("Letra")
## Espacio extra entre letras, en píxeles.
@export var letter_spacing: int = 3

## Momentos (run_time) de las bajas recientes; se podan a window_seconds en cada baja.
var _kill_times: Array[float] = []
## Índice más alto de tier_kills disparado en esta racha; -1 si ninguno.
var _tier: int = -1
var _tween: Tween


func _ready() -> void:
	add_theme_font_override("font", UiTheme.spaced_font(letter_spacing))


## Cuenta una baja nueva y dispara el texto si la racha cruzó un nivel.
func on_kill() -> void:
	var now: float = RunState.run_time
	while not _kill_times.is_empty() and now - _kill_times[0] > window_seconds:
		_kill_times.pop_front()
	if _kill_times.is_empty():
		_tier = -1  # la racha se cortó: cada nivel puede volver a dispararse
	_kill_times.append(now)
	var in_window := _kill_times.size()
	var tier := -1
	for i in tier_kills.size():
		if in_window >= tier_kills[i]:
			tier = i
	if tier > _tier:
		_tier = tier
		_pop(tier)


## Olvida la racha (el contador de bajas volvió a empezar: partida nueva).
func reset() -> void:
	_kill_times.clear()
	_tier = -1


func _pop(tier: int) -> void:
	Sfx.play(SOUND)
	text = tier_words[tier]
	add_theme_color_override("font_color", tier_colors[tier])
	reset_size()
	pivot_offset = size * 0.5
	visible = true
	modulate.a = 1.0
	scale = Vector2.ONE * slam_scale
	rotation_degrees = slam_tilt_degrees
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, settle_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "rotation_degrees", 0.0, settle_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold_time)
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(hide)
