class_name LootToast
extends PanelContainer
## Aviso de botín: una tarjeta que sube abajo al centro cada vez que algo
## entra a una bolsa (objeto de cofre, premio de ruleta, tirada del Tomo del
## Azar, power-up). Los avisos se ponen EN COLA en vez de pisarse. El HUD le
## pasa cada premio desde show_loot() (grupo "hud").
## Posición y tamaño de reposo: los de este nodo en HUD.tscn; al aparecer
## sube `slide_distance` píxeles hasta ahí.

@export_group("Tiempos")
## Segundos que la tarjeta queda en pantalla, sin contar la entrada y la salida.
@export var hold_time: float = 3.0
## Segundos de la entrada y del desvanecido.
@export var fade_time: float = 0.25
## Píxeles que sube la tarjeta al entrar.
@export var slide_distance: float = 26.0
@export_group("Aspecto")
## Color de fondo de la tarjeta; el borde y el brillo toman el color del premio.
@export var background_color: Color = Color(UiTheme.TILE_BG, 0.92)
## Grosor del borde, en píxeles.
@export var border_width: int = 2
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = UiTheme.RADIUS_SMALL
## Tamaño del brillo exterior, en píxeles.
@export var glow_size: int = 10
## Opacidad del brillo exterior (0-1).
@export var glow_alpha: float = 0.3
## Cuánto se aclara el color del premio para pintar el título (0-1).
@export var title_lighten: float = 0.25
@export_group("Textos")
## Título en co-op, para saber de quién fue el botín: J<jugador> y el título.
@export var player_title_format: String = "J%d  %s"

var _queue: Array[Dictionary] = []
var _tween: Tween = null
var _showing: bool = false
## Márgenes de reposo, leídos de la escena.
var _rest_top: float = 0.0
var _rest_bottom: float = 0.0

@onready var _title: Label = %Title
@onready var _description: Label = %Description


func _ready() -> void:
	_rest_top = offset_top
	_rest_bottom = offset_bottom


## Pone en cola una tarjeta; `player_index` solo se muestra si el grupo tiene
## más de un jugador.
func show_loot(title: String, description: String, color: Color,
		player_index: int = 0) -> void:
	_queue.append({"title": title, "description": description,
			"color": color, "player_index": player_index})
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		visible = false
		return
	_showing = true
	var entry: Dictionary = _queue.pop_front()
	var color: Color = entry.color
	var title := String(entry.title)
	if Coop.player_count > 1:
		title = player_title_format % [int(entry.player_index) + 1, title]
	_title.text = title
	_title.add_theme_color_override("font_color", color.lightened(title_lighten))
	_description.text = String(entry.description)
	var style := UiTheme.flat(background_color, corner_radius)
	style.border_color = color
	style.set_border_width_all(border_width)
	UiTheme.add_glow(style, color, glow_size, glow_alpha)
	add_theme_stylebox_override("panel", style)
	visible = true
	modulate.a = 0.0
	offset_bottom = _rest_bottom + slide_distance
	offset_top = _rest_top + slide_distance
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, fade_time)
	_tween.tween_property(self, "offset_bottom", _rest_bottom,
			fade_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "offset_top", _rest_top,
			fade_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(hold_time)
	_tween.chain().tween_property(self, "modulate:a", 0.0, fade_time)
	_tween.chain().tween_callback(_show_next)
