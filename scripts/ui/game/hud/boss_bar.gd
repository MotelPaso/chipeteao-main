class_name BossBar
extends ProgressBar
## Barra de vida del jefe, arriba al centro, visible solo mientras vive el
## jefe seguido. Un jefe la pide al entrar a la arena (grupo "boss_ui" ->
## HUD.track_boss -> track). Las marcas de cuarto (Tick1-3) y el nombre
## (%BossNameLabel) son nodos de HUD.tscn.

@export_group("Colores")
## Ámbar del jefe: relleno de esta barra y de la flecha que apunta al jefe
## (BossArrow lo lee de aquí).
@export var fill_color: Color = Color(0.98, 0.62, 0.16)
## Borde del fondo de la barra.
@export var trough_border_color: Color = Color(0.35, 0.22, 0.06, 0.9)
@export_group("Forma")
## Radio base de la barra (px): el relleno usa este valor - 1 y el fondo + 1.
@export var corner_radius: int = 7
## Tamaño del brillo exterior, en píxeles, con el color de relleno.
@export var glow_size: int = 6
## Opacidad del brillo exterior (0-1).
@export var glow_alpha: float = 0.25
@export_group("Animación")
## Segundos que tarda la barra en llegar a su nuevo valor.
@export var tween_time: float = 0.15
@export_group("Nombre")
## Espacio extra entre las letras del nombre del jefe, en píxeles.
@export var name_letter_spacing: int = 3

var _tracked_boss: Node3D = null
var _boss_health: Health = null
var _value_tween: Tween = null

@onready var _name_label: Label = %BossNameLabel


func _ready() -> void:
	UiTheme.style_bar(self, fill_color, corner_radius)
	var trough := get_theme_stylebox("background") as StyleBoxFlat
	trough.border_color = trough_border_color
	UiTheme.add_glow(trough, fill_color, glow_size, glow_alpha)
	_name_label.add_theme_font_override("font", UiTheme.spaced_font(name_letter_spacing))


## Sigue la vida de `boss` con `title` como nombre. Si ya seguía a otro, pasa
## al nuevo (los jefes son secuenciales; con dos vivos se ve el último).
func track(boss: Node3D, title: String) -> void:
	_untrack()
	var boss_health := Health.find_in(boss)
	if boss_health == null:
		return
	_tracked_boss = boss
	_boss_health = boss_health
	boss_health.damaged.connect(_on_damaged)
	boss_health.hp_changed.connect(_on_hp_changed)
	boss_health.died.connect(_on_died)
	boss.tree_exited.connect(_on_boss_gone)
	_name_label.text = title
	visible = true
	_on_hp_changed(boss_health.current_hp, boss_health.max_hp)


func _on_damaged(_amount: float, current: float) -> void:
	_ease_to(current)


func _on_hp_changed(current: float, new_max: float) -> void:
	# Salta directo cuando cambia la escala, para no animar entre dos escalas.
	if not is_equal_approx(max_value, new_max):
		max_value = new_max
		value = current
	else:
		_ease_to(current)


func _on_died() -> void:
	visible = false


## Respaldo para un jefe que sale del árbol sin morir (desmontaje de escena).
func _on_boss_gone() -> void:
	_untrack()
	visible = false


func _untrack() -> void:
	if _boss_health != null and is_instance_valid(_boss_health):
		_boss_health.damaged.disconnect(_on_damaged)
		_boss_health.hp_changed.disconnect(_on_hp_changed)
		_boss_health.died.disconnect(_on_died)
	if _tracked_boss != null and is_instance_valid(_tracked_boss):
		_tracked_boss.tree_exited.disconnect(_on_boss_gone)
	_boss_health = null
	_tracked_boss = null


## Suaviza la barra hacia `target`; mata la animación anterior para que los
## golpes seguidos converjan en vez de apilarse.
func _ease_to(target: float) -> void:
	if _value_tween != null and _value_tween.is_valid():
		_value_tween.kill()
	_value_tween = create_tween()
	_value_tween.tween_property(self, "value", target, tween_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
