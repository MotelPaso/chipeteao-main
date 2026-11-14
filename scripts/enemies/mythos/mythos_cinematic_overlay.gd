class_name MythosCinematicOverlay
extends CanvasLayer
## El cartel de las cinemáticas de Mythos (nodo Overlay de
## MythosCinematic.tscn): las franjas negras, el nombre del jefe con su
## subtítulo, la indicación de saltar y los destellos a pantalla completa. La
## cinemática dice qué mostrar y cuándo; cómo se ve vive aquí y en los nodos
## de la escena. Los destellos y el nombre toman el color de la segunda fase
## junto con el fuego (FireTint).

@export_group("Cartel")
## Segundos que tarda el nombre en aparecer.
@export var title_fade_seconds: float = 0.6
## Espacio extra entre las letras del nombre, en píxeles.
@export var title_letter_spacing: int = 10
## Color del nombre en la segunda fase del jefe (en la primera manda el de la escena).
@export var reborn_title_color: Color = Color(0.72, 0.94, 1.0)
## Color del contorno del nombre en la segunda fase.
@export var reborn_title_outline_color: Color = Color(0.03, 0.08, 0.32)
## Alto de cada franja negra, como fracción del alto de la pantalla.
@export_range(0.0, 0.3) var bar_height_ratio: float = 0.11
## Segundos que tardan las franjas negras en entrar.
@export var bar_seconds: float = 0.7

@export_group("Destello")
## Color de los destellos a pantalla completa en la primera fase.
@export var flash_color: Color = Color(1.0, 0.82, 0.5)
## Color de los destellos en la segunda fase.
@export var reborn_flash_color: Color = Color(0.7, 0.92, 1.0)
## Segundos que dura cada destello.
@export var flash_seconds: float = 0.45
## Opacidad del destello con que termina una cinemática (0-1).
@export_range(0.0, 1.0) var end_flash_alpha: float = 0.85

## True mientras muestra las franjas y el cartel de una cinemática.
var _staged: bool = false
var _flash_tween: Tween = null
## Los colores del nombre que trae la escena (los de la primera fase).
var _title_color: Color = Color.WHITE
var _title_outline_color: Color = Color.BLACK

@onready var _bar_top: ColorRect = %BarTop
@onready var _bar_bottom: ColorRect = %BarBottom
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _skip_hint: BoxContainer = %SkipHint
@onready var _skip_bar: ProgressBar = %SkipBar
@onready var _flash: ColorRect = %Flash


func _ready() -> void:
	visible = false
	_title.add_theme_font_override("font", UiTheme.spaced_font(title_letter_spacing))
	_title_color = _title.get_theme_color(&"font_color")
	_title_outline_color = _title.get_theme_color(&"font_outline_color")


## Arma la indicación de saltar: `action` es la acción ya resuelta para el
## primer jugador y `text` lo que dice al lado.
func set_skip_hint(action: String, text: String) -> void:
	_skip_hint.add_child(InputHints.build([[action, text]]))
	_skip_hint.move_child(_skip_bar, -1)


## Empieza una cinemática: entran las franjas y quedan listos el nombre
## (todavía invisible) y la indicación de saltar. Con `reborn` el nombre
## lleva los colores de la segunda fase.
func open(title: String, subtitle: String, reborn: bool) -> void:
	_kill_flash()
	_title.text = title
	_subtitle.text = subtitle
	_title.add_theme_color_override(&"font_color",
			reborn_title_color if reborn else _title_color)
	_title.add_theme_color_override(&"font_outline_color",
			reborn_title_outline_color if reborn else _title_outline_color)
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_flash.color = Color(_flash_tint(), 0.0)
	_set_staged(true)
	visible = true
	show_progress(0.0, INF, 0.0)


## Un frame de la cinemática: lleva `elapsed` segundos, el nombre aparece en
## el segundo `title_at` y la acción de saltar va mantenida `skip` (0-1).
func show_progress(elapsed: float, title_at: float, skip: float) -> void:
	var height := bar_height_ratio \
			* smoothstep(0.0, 1.0, clampf(elapsed / maxf(bar_seconds, 0.01), 0.0, 1.0))
	_bar_top.anchor_bottom = height
	_bar_bottom.anchor_top = 1.0 - height
	var shown := clampf((elapsed - title_at) / maxf(title_fade_seconds, 0.01), 0.0, 1.0)
	_title.modulate.a = shown
	_subtitle.modulate.a = shown
	_skip_bar.value = clampf(skip, 0.0, 1.0) * _skip_bar.max_value


## Termina la cinemática: se van las franjas, el nombre y la indicación.
func close() -> void:
	_set_staged(false)


## Un destello a pantalla completa de opacidad `alpha` (0-1).
func flash(alpha: float) -> void:
	_kill_flash()
	visible = true
	_flash.color = Color(_flash_tint(), alpha)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, flash_seconds)
	_flash_tween.tween_callback(_after_flash)


## El destello con que termina una cinemática (y el del golpe más fuerte del jefe).
func flash_end() -> void:
	flash(end_flash_alpha)


## Quita todo ya (la arena se va o la partida terminó).
func clear() -> void:
	_kill_flash()
	_set_staged(false)
	visible = false


func _set_staged(on: bool) -> void:
	_staged = on
	_bar_top.visible = on
	_bar_bottom.visible = on
	_title.visible = on
	_subtitle.visible = on
	_skip_hint.visible = on


func _flash_tint() -> Color:
	return flash_color.lerp(reborn_flash_color, FireTint.amount())


## Con el destello apagado el overlay se va, salvo en plena cinemática: ahí
## siguen las franjas y el cartel.
func _after_flash() -> void:
	if not _staged:
		visible = false


func _kill_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
