class_name StickerNotice
extends CanvasLayer
## Una TARJETA DE AVISO sobre la partida (StickerNotice.tscn): un marco de
## color con contorno de tinta y sombra dura, apenas girado, con un título y
## una línea debajo. Es como las tarjetas del menú principal: solo gira el
## marco (nodo CardFrame); el texto no es hijo suyo y queda siempre recto.
## La usan el presagio de un jefe (BossOmen) y el portal de regreso de su
## arena (BossArenaPortal): ellos dicen qué mostrar, y cómo se ve vive aquí.
## Se esconde sola mientras el HUD está oculto (la cinemática de un jefe).

@export_group("Tarjeta")
## Color del marco de la tarjeta.
@export var card_color: Color = UiTheme.SHARD_BLUE
## Giro del marco, en grados (el texto no gira).
@export var card_tilt_degrees: float = 1.5
## Grosor del contorno de tinta, en píxeles.
@export var card_border_width: int = 4
## Radio de las esquinas, en píxeles.
@export var card_corner_radius: int = 16
## Sombra dura de la tarjeta (desplazamiento en píxeles).
@export var card_shadow_offset: Vector2 = Vector2(0.0, 6.0)
## Segundos que tarda la tarjeta en entrar de golpe.
@export var pop_seconds: float = 0.3
## Escala desde la que entra (1 = sin crecer).
@export var pop_from: float = 0.6

## True desde show_notice() hasta hide_notice().
var _shown: bool = false

@onready var _card: Control = %Card
@onready var _card_frame: Panel = %CardFrame
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle


func _ready() -> void:
	visible = false
	var style := UiTheme.flat(card_color, card_corner_radius)
	style.border_color = UiTheme.INK
	style.set_border_width_all(card_border_width)
	UiTheme.add_hard_shadow(style, card_shadow_offset)
	_card_frame.add_theme_stylebox_override("panel", style)
	_card_frame.rotation_degrees = card_tilt_degrees
	_title.add_theme_font_override("font", UiTheme.display_font())
	_title.add_theme_color_override("font_color", UiTheme.INK)
	_subtitle.add_theme_color_override("font_color", UiTheme.INK)
	set_process(false)


func _process(_delta: float) -> void:
	# Con el HUD oculto (una cinemática) la tarjeta tampoco se ve. El HUD es un
	# CanvasLayer: su `visible` se lee por nombre.
	var hud := get_tree().get_first_node_in_group(&"hud")
	visible = _shown and (hud == null or bool(hud.get(&"visible")))


## Muestra la tarjeta con este título y esta línea debajo; entra de golpe.
func show_notice(title: String, subtitle: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_shown = true
	visible = true
	set_process(true)
	_card.pivot_offset = _card.size * 0.5
	_card_frame.pivot_offset = _card_frame.size * 0.5
	_card.scale = Vector2.ONE * pop_from
	var tween := create_tween()
	tween.tween_property(_card, "scale", Vector2.ONE, pop_seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Cambia la línea de abajo (una cuenta regresiva).
func set_subtitle(text: String) -> void:
	if _subtitle.text != text:
		_subtitle.text = text


## Saca la tarjeta.
func hide_notice() -> void:
	_shown = false
	visible = false
	set_process(false)
