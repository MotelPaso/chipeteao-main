class_name MateRow
extends HBoxContainer
## Fila de un compañero en la columna de co-op: etiqueta "J2" (con K.O.
## mientras está caído), barra de vida delgada, sus puntos (cada jugador tiene
## su propia billetera) y el conteo de sus power-ups (oculto si no tiene).
## El color del texto de cada etiqueta es el de MateRow.tscn; el script solo
## le agrega la pastilla de fondo.

@export_group("Textos")
## Etiqueta del jugador; %d es su número (1-4).
@export var tag_format: String = "J%d"
## Etiqueta mientras está caído (vida en 0).
@export var knocked_out_format: String = "J%d K.O."
## Puntos del compañero.
@export var points_format: String = "%d pts"
## Conteo de power-ups activos del compañero.
@export var powerups_format: String = "◈%d"
@export_group("Aspecto")
## Tinte de la etiqueta mientras está caído.
@export var knocked_out_tint: Color = Color(1.0, 0.45, 0.4)
## Radio de las esquinas de la barra de vida, en píxeles.
@export var bar_corner_radius: int = 6
@export_group("Animación")
## Escala máxima del golpe de la etiqueta cuando el compañero recibe daño.
@export var hit_pop_scale: float = 1.18
## Escala máxima del golpe de los puntos cuando cambian.
@export var points_pop_scale: float = 1.15
## Duración de esos golpes, en segundos.
@export var pop_time: float = 0.18

var _slot: int = 0
var _health: Health = null
var _hp_color: Callable
var _fill: StyleBoxFlat = null

@onready var _tag: Label = %Tag
@onready var _bar: ProgressBar = %Bar
@onready var _points: Label = %Points
@onready var _powerups: Label = %PowerUps


func _ready() -> void:
	for label: Label in [_tag, _points, _powerups]:
		UiTheme.style_badge(label, label.get_theme_color(&"font_color"))


## Une la fila al compañero en `slot`: su vida, su billetera (si tiene la
## señal points_changed) y la rampa de color de la barra.
func bind(slot: int, health: Health, body: Node, hp_color: Callable) -> void:
	_slot = slot
	_health = health
	_hp_color = hp_color
	_tag.text = tag_format % (slot + 1)
	_bar.max_value = health.max_hp
	_bar.value = health.current_hp
	_fill = UiTheme.style_bar(_bar, hp_color.call(1.0, 1.0), bar_corner_radius)
	# Conexiones a métodos de la fila: se cortan solas cuando la fila se libera.
	health.hp_changed.connect(_refresh)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	if body.has_signal("points_changed"):
		_points.text = points_format % int(body.get("points"))
		body.connect("points_changed", _on_points_changed)
	else:
		# Cuerpos sin billetera (p. ej. un sustituto en una escena de prueba).
		_points.visible = false


## Conteo de power-ups del compañero, de pie o caído (uno caído conserva sus
## power-ups activos). Lo llama MatePanel con su temporizador.
func refresh_powerups() -> void:
	var body := PartySlots.raider_at(get_tree(), _slot)
	var powerups := PowerUps.find_in(body) if body != null else null
	var live := powerups.count() if powerups != null else 0
	_powerups.text = powerups_format % live if live > 0 else ""
	_powerups.visible = live > 0


func _refresh(current: float, max_hp: float) -> void:
	_bar.max_value = max_hp
	_bar.value = current
	UiTheme.recolor_fill(_fill, _hp_color.call(current, max_hp))
	var standing := current > 0.0
	_tag.text = (tag_format if standing else knocked_out_format) % (_slot + 1)
	_tag.modulate = Color.WHITE if standing else knocked_out_tint


func _on_damaged(_amount: float, current: float) -> void:
	_refresh(current, _health.max_hp)
	# No Juice.player_hurt(): la viñeta y la sacudida cubren toda la ventana.
	# Que golpeen a un compañero hace saltar SU fila, no tu pantalla.
	UiTheme.pop(_tag, hit_pop_scale, pop_time)


func _on_died() -> void:
	_refresh(0.0, _health.max_hp)


func _on_points_changed(total: int) -> void:
	_points.text = points_format % total
	UiTheme.pop(_points, points_pop_scale, pop_time)
