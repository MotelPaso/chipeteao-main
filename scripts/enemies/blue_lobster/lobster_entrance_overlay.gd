class_name LobsterEntranceOverlay
extends CanvasLayer
## Lo que la cinemática de la Langosta Azul dibuja encima de la imagen (nodo
## Overlay de LobsterEntrance.tscn): el destello del corte, el AGUA que
## inunda la pantalla en el rapto (nodo Flood, con flood_cover.gdshader), el
## CARTEL con su nombre y la indicación de saltar. La cinemática dice qué
## mostrar y cuándo; cómo se ve vive aquí y en los nodos de la escena.
## El cartel es una tarjeta como las del menú principal: un marco de color
## con contorno de tinta y sombra dura, apenas girado. Solo gira el MARCO
## (nodo CardFrame): el texto no es hijo suyo y queda siempre recto.

@export_group("Cartel")
## Color del marco de la tarjeta.
@export var card_color: Color = UiTheme.SHARD_BLUE
## Giro del marco, en grados (el texto no gira).
@export var card_tilt_degrees: float = -2.0
## Grosor del contorno de tinta, en píxeles.
@export var card_border_width: int = 5
## Radio de las esquinas, en píxeles.
@export var card_corner_radius: int = 20
## Sombra dura de la tarjeta (desplazamiento en píxeles).
@export var card_shadow_offset: Vector2 = Vector2(0.0, 8.0)
## Segundos que tarda la tarjeta en entrar de golpe.
@export var card_pop_seconds: float = 0.28
## Escala desde la que entra (1 = sin crecer).
@export var card_pop_from: float = 0.55

@export_group("Agua en la pantalla")
## Segundo del rapto en que el agua empieza a subir por la pantalla.
@export var flood_from: float = 3.9
## Sonido de la pantalla que se inunda (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var flood_sfx: StringName = &"abduction_flood"
## Segundos que tarda el agua en irse en burbujas con el primer plano del fondo del mar.
@export var uncover_seconds: float = 0.7

@export_group("Saltar")
## Segundos desde el corte hasta que aparece la indicación de saltar: el rapto va primero.
@export var skip_hint_delay: float = 1.2
## Opacidad (0-1) de la placa de tinta detrás de la indicación de saltar: sin ella no se lee sobre la arena clara.
@export_range(0.0, 1.0) var skip_plate_alpha: float = 0.55
## Píxeles que esa placa sobresale alrededor de la indicación.
@export var skip_plate_margin: float = 8.0

@export_group("Destello")
## Color de los destellos a pantalla completa.
@export var flash_color: Color = Color(0.86, 0.96, 1.0)
## Opacidad del destello del corte (0-1).
@export_range(0.0, 1.0) var cut_flash_alpha: float = 0.4
## Segundos que dura el destello del corte.
@export var cut_flash_seconds: float = 0.14

## Opacidad del destello con que termina la entrada (0-1).
@export_range(0.0, 1.0) var end_flash_alpha: float = 0.8
## Segundos que dura el destello del final.
@export var end_flash_seconds: float = 0.4

## True mientras muestra el cartel y la indicación de una entrada.
var _staged: bool = false
var _card_shown: bool = false
## Segundo de la entrada en que se abrió (el corte); -1 hasta el primer frame.
var _opened_at: float = -1.0
var _flash_tween: Tween = null
var _card_tween: Tween = null
var _skip_plate: StyleBoxFlat = null
## True mientras el agua tapa la pantalla entera.
var _covered: bool = false
var _flood_sounded: bool = false
## Segundo del fondo del mar en que la pantalla empezó a destaparse (< 0 = sigue tapada).
var _uncover_from: float = -1.0

@onready var _card: Control = %Card
@onready var _card_frame: Panel = %CardFrame
@onready var _title: Label = %Title
@onready var _skip_hint: BoxContainer = %SkipHint
@onready var _skip_bar: ProgressBar = %SkipBar
@onready var _flash: ColorRect = %Flash
@onready var _flood: ColorRect = %Flood


func _ready() -> void:
	visible = false
	var style := UiTheme.flat(card_color, card_corner_radius)
	style.border_color = UiTheme.INK
	style.set_border_width_all(card_border_width)
	UiTheme.add_hard_shadow(style, card_shadow_offset)
	_card_frame.add_theme_stylebox_override("panel", style)
	_title.add_theme_font_override("font", UiTheme.display_font())
	_title.add_theme_color_override("font_color", UiTheme.INK)
	_card.visible = false
	_flood.visible = false
	_skip_plate = UiTheme.flat(Color(UiTheme.INK, skip_plate_alpha),
			roundi(card_corner_radius * 0.5))
	_skip_hint.draw.connect(_draw_skip_plate)
	_card.resized.connect(_center_pivots)
	_center_pivots()


## Arma la indicación de saltar: `action` es la acción ya resuelta para el
## primer jugador y `text` lo que dice al lado.
func set_skip_hint(action: String, text: String) -> void:
	_skip_hint.add_child(InputHints.build([[action, text]]))
	_skip_hint.move_child(_skip_bar, -1)


## El corte: desde aquí hay entrada en pantalla. Deja listos el cartel (aún
## sin mostrar) y la indicación de saltar, y da el destello del susto.
func open(title: String) -> void:
	_title.text = title
	_card.visible = false
	_card_shown = false
	_staged = true
	_opened_at = -1.0
	_flood_sounded = false
	_uncover_from = -1.0
	_skip_hint.visible = false
	visible = true
	_flash_to(cut_flash_alpha, cut_flash_seconds)


## Un frame de la entrada: lleva `elapsed` segundos, el cartel entra en el
## segundo `title_at` y la acción de saltar va mantenida `skip` (0-1).
func show_progress(elapsed: float, title_at: float, skip: float) -> void:
	_skip_bar.value = clampf(skip, 0.0, 1.0) * _skip_bar.max_value
	if not _staged:
		return
	if _opened_at < 0.0:
		_opened_at = elapsed
	_skip_hint.visible = elapsed - _opened_at >= skip_hint_delay
	if not _card_shown and elapsed >= title_at:
		_pop_card()


## El agua sobre la pantalla. `level` es cuánto subió (0 = nada, 1 = la tapa
## entera) y `dissolve` cuánto se fue ya en burbujas (0 = entera, 1 = nada).
func show_flood(level: float, dissolve: float) -> void:
	var shown := level > 0.0 and dissolve < 1.0
	_covered = level >= 1.0 and dissolve <= 0.0
	_flood.visible = shown
	if not shown:
		return
	var material := _flood.material as ShaderMaterial
	material.set_shader_parameter(&"level", clampf(level, 0.0, 1.0))
	material.set_shader_parameter(&"dissolve", clampf(dissolve, 0.0, 1.0))


## Un frame del rapto, que va en su segundo `seconds` de `total`: el agua
## sube por la pantalla desde flood_from y al final la tapa entera.
func flood_rising(seconds: float, total: float) -> void:
	var level := clampf((seconds - flood_from) / maxf(total - flood_from, 0.01), 0.0, 1.0)
	if level > 0.0 and not _flood_sounded:
		_flood_sounded = true
		Sfx.play(flood_sfx)
	show_flood(level, 0.0)


## La pantalla empieza a destaparse en el segundo `seconds` del fondo del mar.
## Solo cuenta la primera vez que se pide.
func begin_uncover(seconds: float) -> void:
	if _uncover_from < 0.0:
		_uncover_from = seconds


## Un frame del fondo del mar, en su segundo `seconds`: el agua tapa la
## pantalla hasta begin_uncover() y después se va en burbujas.
func flood_clearing(seconds: float) -> void:
	var dissolve := 0.0 if _uncover_from < 0.0 \
			else (seconds - _uncover_from) / maxf(uncover_seconds, 0.01)
	show_flood(1.0, dissolve)


## True mientras el agua tapa la pantalla entera.
func is_covered() -> bool:
	return _covered and visible


## Termina la cinemática: se van el cartel, el agua y la indicación, con un destello.
func close() -> void:
	_set_staged(false)
	show_flood(0.0, 1.0)
	_flash_to(end_flash_alpha, end_flash_seconds)


## Quita todo ya (la arena se va o la partida terminó).
func clear() -> void:
	_kill(_flash_tween)
	_set_staged(false)
	show_flood(0.0, 1.0)
	_flash.color.a = 0.0
	visible = false


# --- privados ---------------------------------------------------------------------

## El cartel entra de golpe: crece desde card_pop_from y el marco cae a su giro.
func _pop_card() -> void:
	_card_shown = true
	_card.visible = true
	_center_pivots()
	_kill(_card_tween)
	_card.scale = Vector2.ONE * card_pop_from
	_card_frame.rotation_degrees = card_tilt_degrees * -3.0
	_card_tween = create_tween().set_parallel(true)
	_card_tween.tween_property(_card, "scale", Vector2.ONE, card_pop_seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(_card_frame, "rotation_degrees", card_tilt_degrees,
			card_pop_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_staged(on: bool) -> void:
	_staged = on
	_kill(_card_tween)
	if not on:
		_card.visible = false
		_card_shown = false
		_skip_hint.visible = false



## Un destello a pantalla completa de opacidad `alpha` que se apaga en `seconds`.
func _flash_to(alpha: float, seconds: float) -> void:
	_kill(_flash_tween)
	visible = true
	_flash.color = Color(flash_color, alpha)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, seconds)
	_flash_tween.tween_callback(_after_flash)


## Con el destello apagado el overlay se va, salvo en plena entrada.
func _after_flash() -> void:
	if not _staged:
		visible = false


## La placa de tinta detrás de la indicación de saltar (se dibuja en su
## contenedor, por debajo de la tecla, el texto y la barra).
func _draw_skip_plate() -> void:
	_skip_hint.draw_style_box(_skip_plate,
			Rect2(Vector2.ZERO, _skip_hint.size).grow(skip_plate_margin))


## La tarjeta crece y el marco gira alrededor de su centro.
func _center_pivots() -> void:
	_card.pivot_offset = _card.size * 0.5
	_card_frame.pivot_offset = _card_frame.size * 0.5


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
