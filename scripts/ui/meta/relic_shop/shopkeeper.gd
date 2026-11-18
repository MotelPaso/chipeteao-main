class_name Shopkeeper
extends Control
## El vendedor de la Armería (Shopkeeper.tscn): un herrero viejo y gruñón,
## personaje propio del juego, a la izquierda de la lista de reliquias, con un
## globo de diálogo sobre la cabeza. La Armería solo le avisa qué pasó
## (say(Shopkeeper.Line.BOUGHT)); las frases, el globo y el movimiento viven
## aquí y en la escena.
##
## Movimiento: el globo aparece con un golpe corto de escala y opacidad cada
## vez que cambia la frase, y el herrero respira muy despacio mientras la
## pantalla está abierta. Solo scale y modulate.

## Qué le pasó al jugador en la tienda; cada valor tiene su frase.
enum Line {
	OPEN, ## Abrió la Armería.
	BOUGHT, ## Compró un rango.
	CANT_AFFORD, ## No le alcanzan las esquirlas.
	MAXED, ## La compra llevó la reliquia a su rango máximo.
	SOLD_OUT, ## Todas las reliquias están al máximo.
}

@export_group("Frases")
## Al abrir la Armería: una por visita, en este orden y de vuelta al principio.
@export var open_lines: Array[String] = [
	"¿Qué quieres, pequeño superviviente?",
	"Mira sin tocar. Tocar cuesta esquirlas.",
]
## Al comprar un rango.
@export var bought_line: String = "Trato hecho. No acepto devoluciones."
## Cuando las esquirlas no alcanzan.
@export var cant_afford_line: String = "Con eso no te vendo ni el polvo."
## Cuando la compra llevó la reliquia a su rango máximo.
@export var maxed_line: String = "Más de eso ya no cabe en ti."
## Cuando todas las reliquias están al máximo.
@export var sold_out_line: String = "Me dejaste sin mercancía. Largo."
@export_group("Globo")
## Fondo del globo de diálogo.
@export var bubble_color: Color = UiTheme.PAPER
## Contorno del globo y de su punta.
@export var bubble_border_color: Color = UiTheme.INK
## Grosor del contorno del globo, en píxeles.
@export var bubble_border_width: int = 3
## Radio de las esquinas del globo, en píxeles.
@export var bubble_radius: int = UiTheme.RADIUS
## Margen interno del globo, en píxeles (lados, arriba/abajo).
@export var bubble_padding: Vector2 = Vector2(14.0, 10.0)
## Sombra dura bajo el globo (desplazamiento en píxeles).
@export var bubble_shadow_offset: Vector2 = Vector2(0.0, 4.0)
@export_group("Animación")
## Escala desde la que aparece el globo al cambiar de frase.
@export var bubble_start_scale: float = 0.9
## Duración de la aparición del globo, en segundos.
@export var bubble_time: float = 0.18
## Escala vertical máxima del herrero al respirar (1 = quieto).
@export var breath_scale: float = 1.015
## Segundos que tarda en inhalar; exhalar tarda lo mismo.
@export var breath_half_period: float = 1.6

## Visitas a la Armería en esta sesión: decide cuál de open_lines toca.
static var _visits: int = 0

var _bubble_tween: Tween = null

@onready var _speech: Control = %Speech
@onready var _bubble: PanelContainer = %Bubble
@onready var _text: Label = %Text
@onready var _tail: Polygon2D = %Tail
@onready var _tail_outline: Line2D = %TailOutline
@onready var _figure: TextureRect = %Figure


func _ready() -> void:
	var box := UiTheme.flat(bubble_color, bubble_radius)
	box.border_color = bubble_border_color
	box.set_border_width_all(bubble_border_width)
	box.content_margin_left = bubble_padding.x
	box.content_margin_right = bubble_padding.x
	box.content_margin_top = bubble_padding.y
	box.content_margin_bottom = bubble_padding.y
	UiTheme.add_hard_shadow(box, bubble_shadow_offset)
	_bubble.add_theme_stylebox_override("panel", box)
	_tail.color = bubble_color
	_tail_outline.default_color = bubble_border_color
	_tail_outline.width = bubble_border_width
	# El globo crece desde su punta (de donde sale la voz) y el herrero respira
	# desde los pies; los dos tamaños los decide el contenedor.
	_speech.resized.connect(_place_pivots)
	_figure.resized.connect(_place_pivots)
	_place_pivots()
	_breathe()


## El herrero dice la frase de `line`; el globo reaparece con un golpe corto.
## Llamar otra vez a mitad del golpe lo reinicia con la frase nueva.
func say(line: Line) -> void:
	_text.text = _line_text(line)
	if _bubble_tween != null and _bubble_tween.is_valid():
		_bubble_tween.kill()
	_speech.scale = Vector2.ONE * bubble_start_scale
	_speech.modulate.a = 0.0
	_bubble_tween = create_tween().set_parallel()
	_bubble_tween.set_ignore_time_scale(true)
	_bubble_tween.tween_property(_speech, "scale", Vector2.ONE, bubble_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_property(_speech, "modulate:a", 1.0, bubble_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func _line_text(line: Line) -> String:
	match line:
		Line.BOUGHT:
			return bought_line
		Line.CANT_AFFORD:
			return cant_afford_line
		Line.MAXED:
			return maxed_line
		Line.SOLD_OUT:
			return sold_out_line
	if open_lines.is_empty():
		return ""
	var text := open_lines[_visits % open_lines.size()]
	_visits += 1
	return text


## Respiración: el herrero se estira apenas hacia arriba y vuelve, sin parar,
## mientras la pantalla esté abierta (el Tween muere con este nodo).
func _breathe() -> void:
	var tween := create_tween().set_loops()
	tween.set_ignore_time_scale(true)
	tween.tween_property(_figure, "scale:y", breath_scale, breath_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_figure, "scale:y", 1.0, breath_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _place_pivots() -> void:
	_speech.pivot_offset = Vector2(_tail.position.x, _speech.size.y)
	_figure.pivot_offset = Vector2(_figure.size.x * 0.5, _figure.size.y)
