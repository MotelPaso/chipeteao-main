class_name DifficultyChip
extends PanelContainer
## Ficha de dificultad de la partida, en la fila de información de arriba a la
## izquierda (HUD.tscn > RunInfo), junto al reloj y la etapa: el icono de
## dificultad (StatIcons "difficulty") y el porcentaje extra. Se oculta
## mientras la dificultad extra es cero. El HUD solo le pasa el número
## (show_bonus); el aspecto vive aquí y en DifficultyChip.tscn.

## Stat de StatIcons que da el icono de la ficha.
const ICON_STAT := "difficulty"
## Por debajo de esta dificultad extra (fracción) la ficha se oculta.
const HIDE_BELOW := 0.001

@export_group("Textos")
## Porcentaje de dificultad extra (%% es el signo %).
@export var text_format: String = "+%d%%"
## Tooltip de la ficha; %d es el mismo porcentaje.
@export var tip_format: String = "Dificultad +%d%%"
@export_group("Recuadro")
## Fondo de la ficha.
@export var body_color: Color = UiTheme.INK
## Contorno de la ficha.
@export var border_color: Color = UiTheme.ACCENT_RED
## Color del porcentaje.
@export var text_color: Color = UiTheme.PAPER
## Grosor del contorno, en píxeles.
@export var border_width: int = 2
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = UiTheme.RADIUS_SMALL
## Margen interno de la ficha, en píxeles (lados, arriba/abajo).
@export var padding: Vector2 = Vector2(8.0, 2.0)
## Sombra dura bajo la ficha (desplazamiento en píxeles).
@export var shadow_offset: Vector2 = Vector2(0.0, 2.0)
@export_group("Animación")
## Escala máxima del golpe de la ficha cuando sube la dificultad.
@export var pop_scale: float = 1.18
## Duración de ese golpe, en segundos.
@export var pop_time: float = 0.2

## Último porcentaje mostrado; -1 antes del primero.
var _shown_percent: int = -1

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


func _ready() -> void:
	var box := UiTheme.flat(body_color, corner_radius)
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.content_margin_left = padding.x
	box.content_margin_right = padding.x
	box.content_margin_top = padding.y
	box.content_margin_bottom = padding.y
	UiTheme.add_hard_shadow(box, shadow_offset)
	add_theme_stylebox_override("panel", box)
	_icon.texture = StatIcons.texture(ICON_STAT)
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_font_override("font", UiTheme.display_font())


## Muestra la dificultad extra de la partida (`bonus` es una fracción: 0.15 se
## lee "+15%"). Cero oculta la ficha; un porcentaje más alto que el anterior
## le da un golpe de escala.
func show_bonus(bonus: float) -> void:
	visible = bonus > HIDE_BELOW
	var percent := roundi(bonus * 100.0)
	if percent == _shown_percent:
		return
	var rose := _shown_percent >= 0 and percent > _shown_percent
	_shown_percent = percent
	_label.text = text_format % percent
	tooltip_text = tip_format % percent
	if rose and visible:
		# Diferido: recién visible, el contenedor todavía no le dio tamaño y
		# el golpe saldría desde su esquina.
		UiTheme.pop.call_deferred(self, pop_scale, pop_time)
