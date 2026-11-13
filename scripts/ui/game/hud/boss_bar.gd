class_name BossBar
extends ProgressBar
## Barra de vida del jefe, arriba al centro, visible solo mientras vive el
## jefe seguido. Un jefe la pide al entrar a la arena (grupo "boss_ui" ->
## HUD.track_boss -> track). Las marcas de cuarto (Tick1-3), el nombre
## (%BossNameLabel) y la fila de vidas (%BossLives) son nodos de HUD.tscn.
## Un jefe con varias vidas (Mythos) expone por nombre la señal
## lives_changed(left, total) y los métodos lives_left() y lives_total(): la
## fila muestra una marca por vida. Cuando el jefe seguido muere o se va, la
## barra pasa a otro jefe vivo (primero el de etapa) en vez de ocultarse.

## Grupos donde se busca otro jefe vivo cuando el seguido muere, en orden.
const FALLBACK_GROUPS: Array[StringName] = [&"stage_boss", &"boss"]

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
@export var name_letter_spacing: int = 1
@export_group("Vidas")
## Tamaño de cada marca de vida, en píxeles.
@export var life_pip_size: Vector2 = Vector2(22.0, 8.0)
## Color de una vida que al jefe le queda.
@export var life_pip_color: Color = Color(1.0, 0.8, 0.32)
## Color de una vida ya gastada.
@export var life_pip_spent_color: Color = Color(0.22, 0.15, 0.1, 0.9)
## Radio de las esquinas de cada marca, en píxeles.
@export var life_pip_corner_radius: int = 3

var _tracked_boss: Node3D = null
var _boss_health: Health = null
var _value_tween: Tween = null
var _life_pips: Array[Panel] = []

@onready var _name_label: Label = %BossNameLabel
@onready var _lives_row: HBoxContainer = %BossLives


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
	_bind_lives(boss)
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
	_follow_another_boss()


## Respaldo para un jefe que sale del árbol sin morir (desmontaje de escena).
func _on_boss_gone() -> void:
	_follow_another_boss()


## El jefe seguido murió o se fue: la barra pasa a otro jefe vivo, o se
## oculta si no queda ninguno.
func _follow_another_boss() -> void:
	var gone := _tracked_boss
	_untrack()
	visible = false
	if not is_inside_tree():
		return
	for group: StringName in FALLBACK_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			var boss := node as Node3D
			if boss == null or boss == gone or boss.is_queued_for_deletion() \
					or not boss.is_inside_tree():
				continue
			var health := Health.find_in(boss)
			var title: Variant = boss.get("boss_title")
			if health == null or health.is_dead or title == null:
				continue
			track(boss, String(title))
			return


func _untrack() -> void:
	if _boss_health != null and is_instance_valid(_boss_health):
		_boss_health.damaged.disconnect(_on_damaged)
		_boss_health.hp_changed.disconnect(_on_hp_changed)
		_boss_health.died.disconnect(_on_died)
	if _tracked_boss != null and is_instance_valid(_tracked_boss):
		_tracked_boss.tree_exited.disconnect(_on_boss_gone)
		if _tracked_boss.has_signal(&"lives_changed") \
				and _tracked_boss.is_connected(&"lives_changed", _on_lives_changed):
			_tracked_boss.disconnect(&"lives_changed", _on_lives_changed)
	_boss_health = null
	_tracked_boss = null
	_lives_row.visible = false


## Muestra una marca por vida si el jefe lleva la cuenta (ver la cabecera).
func _bind_lives(boss: Node3D) -> void:
	if not (boss.has_signal(&"lives_changed") and boss.has_method(&"lives_left")
			and boss.has_method(&"lives_total")):
		_lives_row.visible = false
		return
	boss.connect(&"lives_changed", _on_lives_changed)
	_on_lives_changed(int(boss.call(&"lives_left")), int(boss.call(&"lives_total")))


func _on_lives_changed(left: int, total: int) -> void:
	_lives_row.visible = total > 1
	while _life_pips.size() < total:
		var pip := Panel.new()
		pip.custom_minimum_size = life_pip_size
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lives_row.add_child(pip)
		_life_pips.append(pip)
	for index: int in _life_pips.size():
		var pip := _life_pips[index]
		pip.visible = index < total
		pip.add_theme_stylebox_override("panel", UiTheme.flat(
				life_pip_color if index < left else life_pip_spent_color,
				life_pip_corner_radius))


## Suaviza la barra hacia `target`; mata la animación anterior para que los
## golpes seguidos converjan en vez de apilarse.
func _ease_to(target: float) -> void:
	if _value_tween != null and _value_tween.is_valid():
		_value_tween.kill()
	_value_tween = create_tween()
	_value_tween.tween_property(self, "value", target, tween_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
