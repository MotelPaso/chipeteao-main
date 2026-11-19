class_name BossBar
extends ProgressBar
## Barra de vida del jefe, arriba al centro, visible solo mientras vive el
## jefe seguido. Un jefe la pide al entrar a la arena (grupo "boss_ui" ->
## HUD.track_boss -> track). Se dibuja entera aquí (_draw): marco de tinta
## con sombra dura, el relleno con su franja de brillo, el RASTRO del daño
## reciente (queda un momento y después se achica), marcas cada décimo y, si
## el jefe tiene fases, un rombo por fase debajo. Al aparecer y en cada fase
## nueva se llena desde cero; si el jefe solo cambia cuánta vida hay detrás
## de la misma barra (otra vida máxima con la misma proporción, como la
## recalcula LobsterLife), se reescala sin moverse. Cada golpe la sacude y la
## hace destellar, y con poca vida late.
## El nombre (%BossNameLabel) es un nodo de HUD.tscn.
## Contratos por nombre con el jefe, todos opcionales:
##   lives_changed(left, total), lives_left(), lives_total()  -> los rombos
##   bar_title() -> el nombre (se vuelve a leer en cada cambio de fase)
##   bar_color() -> el color del relleno (ídem)
##   bar_visible_changed(shown) -> la barra se va (el jefe parece muerto) o
##       vuelve llenándose desde cero, con su nombre y su color de ahora
## Cuando el jefe seguido muere o se va, la barra pasa a otro jefe vivo
## (primero el de etapa) en vez de ocultarse.

## Grupos donde se busca otro jefe vivo cuando el seguido muere, en orden.
const FALLBACK_GROUPS: Array[StringName] = [&"stage_boss", &"boss"]
## Diferencia de proporción (0-1) por debajo de la cual una vida máxima nueva
## es la misma barra reescalada y no una fase nueva (ver _on_hp_changed).
const RESCALE_SLACK: float = 0.001

@export_group("Colores")
## Ámbar del jefe: relleno de esta barra si el jefe no trae color propio, y
## color de la flecha que apunta al jefe (BossArrow lo lee de aquí).
@export var fill_color: Color = Color(0.98, 0.62, 0.16)
## Fondo de la barra, donde ya no queda vida.
@export var trough_color: Color = Color(0.05, 0.13, 0.15, 0.94)
## Rastro del daño reciente.
@export var ghost_color: Color = Color(1.0, 0.95, 0.8)
## Color hacia el que late el relleno cuando queda poca vida.
@export var low_color: Color = Color(0.95, 0.33, 0.18)
## Marcas de cada décimo de la barra.
@export var tick_color: Color = Color(0.08, 0.07, 0.1, 0.4)

@export_group("Forma")
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = 9
## Grosor del marco de tinta, en píxeles.
@export var border_width: int = 4
## Corrimiento de la sombra dura, en píxeles.
@export var shadow_offset: Vector2 = Vector2(0.0, 5.0)
## Alto de la franja de brillo del relleno, como fracción del alto (0-1).
@export_range(0.0, 1.0) var shine_height: float = 0.36
## Cuánto más clara es esa franja (0-1).
@export_range(0.0, 1.0) var shine_lighten: float = 0.28

@export_group("Animación")
## Segundos que tarda el relleno en llegar a su nuevo valor.
@export var tween_time: float = 0.12
## Segundos que el rastro espera antes de empezar a achicarse.
@export var ghost_delay: float = 0.45
## Fracción de la barra por segundo a la que se achica el rastro.
@export var ghost_speed: float = 0.55
## Segundos que tarda en llenarse desde cero al aparecer y en cada fase nueva.
@export var fill_in_time: float = 0.8
## Píxeles que la sacude un golpe.
@export var shake_pixels: float = 4.0
## Segundos que dura esa sacudida y su destello.
@export var shake_time: float = 0.16
## Fracción de vida (0-1) por debajo de la cual el relleno late.
@export_range(0.0, 1.0) var low_fraction: float = 0.25
## Latidos por segundo con poca vida.
@export var low_pulse_speed: float = 2.4

@export_group("Nombre")
## Espacio extra entre las letras del nombre del jefe, en píxeles.
@export var name_letter_spacing: int = 3

@export_group("Fases")
## Tamaño de cada rombo de fase, en píxeles.
@export var pip_size: float = 16.0
## Separación entre rombos, en píxeles.
@export var pip_gap: float = 12.0
## Píxeles entre la barra y la fila de rombos.
@export var pip_drop: float = 16.0
## Color de una fase ya gastada.
@export var pip_spent_color: Color = Color(0.14, 0.2, 0.22)

var _tracked_boss: Node3D = null
var _boss_health: Health = null
var _value_tween: Tween = null
## Vida del jefe en su último aviso (golpe o cambio): con ella se comparan las
## proporciones cuando cambia su vida máxima.
var _known_hp: float = 0.0
## Valor al que llega el rastro del daño (en vida, como `value`).
var _ghost: float = 0.0
var _ghost_wait: float = 0.0
var _shake_left: float = 0.0
var _time: float = 0.0
var _color: Color = Color.WHITE
var _lives_left: int = 0
var _lives_total: int = 0
var _frame_box: StyleBoxFlat = null
var _fill_box: StyleBoxFlat = null

@onready var _name_label: Label = %BossNameLabel


func _ready() -> void:
	# La barra se dibuja en _draw: los estilos propios de ProgressBar van vacíos.
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	_frame_box = UiTheme.flat(trough_color, corner_radius)
	_frame_box.set_border_width_all(border_width)
	_frame_box.border_color = UiTheme.INK
	_fill_box = UiTheme.flat(fill_color, maxi(corner_radius - border_width, 1))
	_color = fill_color
	_name_label.add_theme_font_override("font", UiTheme.spaced_font(name_letter_spacing))
	pivot_offset = size * 0.5
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	_shake_left = maxf(_shake_left - delta, 0.0)
	if _ghost > value:
		_ghost_wait -= delta
		if _ghost_wait <= 0.0:
			_ghost = maxf(_ghost - ghost_speed * max_value * delta, value)
	else:
		_ghost = value
	queue_redraw()


func _draw() -> void:
	var jolt := 0.0
	if _shake_left > 0.0:
		jolt = sin(_time * 90.0) * shake_pixels * (_shake_left / maxf(shake_time, 0.01))
	draw_set_transform(Vector2(jolt, 0.0))
	var frame := Rect2(Vector2.ZERO, size)
	# Sombra dura bajo el marco, como el resto de la interfaz.
	_fill_box.bg_color = UiTheme.INK
	draw_style_box(_fill_box, Rect2(frame.position + shadow_offset, frame.size))
	draw_style_box(_frame_box, frame)
	var inner := frame.grow(-float(border_width))
	var top := maxf(max_value, 0.001)
	_draw_fill(inner, clampf(_ghost / top, 0.0, 1.0), ghost_color)
	var color := _color
	var ratio := clampf(value / top, 0.0, 1.0)
	if ratio < low_fraction:
		color = color.lerp(low_color, 0.5 + 0.5 * sin(_time * low_pulse_speed * TAU))
	if _shake_left > 0.0:
		color = color.lerp(Color.WHITE, 0.6 * _shake_left / maxf(shake_time, 0.01))
	_draw_fill(inner, ratio, color)
	var shine := Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y * shine_height))
	draw_rect(shine, Color(1.0, 1.0, 1.0, shine_lighten))
	for index: int in range(1, 10):
		var x := inner.position.x + inner.size.x * float(index) / 10.0
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), tick_color,
				3.0 if index == 5 else 1.5)
	_draw_pips(frame)


## Un relleno de `ratio` del ancho interior, con las esquinas de la barra.
func _draw_fill(inner: Rect2, ratio: float, color: Color) -> void:
	if ratio <= 0.0:
		return
	_fill_box.bg_color = color
	draw_style_box(_fill_box, Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)))


## Un rombo por fase, centrados bajo la barra; los de fases gastadas, apagados.
func _draw_pips(frame: Rect2) -> void:
	if _lives_total <= 1:
		return
	var step := pip_size + pip_gap
	var start := frame.get_center().x - step * float(_lives_total - 1) * 0.5
	var half := pip_size * 0.5
	for index: int in _lives_total:
		var center := Vector2(start + step * float(index), frame.end.y + pip_drop + half)
		var diamond := PackedVector2Array([center + Vector2(0.0, -half - 3.0),
				center + Vector2(half + 3.0, 0.0), center + Vector2(0.0, half + 3.0),
				center + Vector2(-half - 3.0, 0.0)])
		draw_colored_polygon(diamond, UiTheme.INK)
		var core := PackedVector2Array([center + Vector2(0.0, -half), center + Vector2(half, 0.0),
				center + Vector2(0.0, half), center + Vector2(-half, 0.0)])
		draw_colored_polygon(core, _color if index < _lives_left else pip_spent_color)


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
	if boss.has_signal(&"bar_visible_changed"):
		boss.connect(&"bar_visible_changed", _on_bar_visible_changed)
	_name_label.text = title
	visible = true
	set_process(true)
	_bind_lives(boss)
	_read_look(boss)
	max_value = boss_health.max_hp
	_known_hp = boss_health.current_hp
	_fill_in(boss_health.current_hp)


func _on_damaged(_amount: float, current: float) -> void:
	_known_hp = current
	_shake_left = shake_time
	_ghost_wait = ghost_delay
	_ease_to(current)


func _on_hp_changed(current: float, new_max: float) -> void:
	var before := _known_hp / maxf(max_value, 0.001)
	_known_hp = current
	if is_equal_approx(max_value, new_max):
		_ease_to(current)
	elif absf(current / maxf(new_max, 0.001) - before) <= RESCALE_SLACK:
		_rescale(new_max)
	else:
		# Otra escala con otra proporción es otra fase: se llena desde cero.
		max_value = new_max
		_fill_in(current)


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
	set_process(false)
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
			# Un jefe que se hace el muerto sale del grupo "boss": no cuenta.
			if health == null or health.is_dead or title == null \
					or not boss.is_in_group(&"boss"):
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
		if _tracked_boss.has_signal(&"bar_visible_changed") \
				and _tracked_boss.is_connected(&"bar_visible_changed", _on_bar_visible_changed):
			_tracked_boss.disconnect(&"bar_visible_changed", _on_bar_visible_changed)
	_boss_health = null
	_tracked_boss = null
	_lives_total = 0


## Muestra un rombo por fase si el jefe lleva la cuenta (ver la cabecera).
func _bind_lives(boss: Node3D) -> void:
	if not (boss.has_signal(&"lives_changed") and boss.has_method(&"lives_left")
			and boss.has_method(&"lives_total")):
		_lives_total = 0
		return
	boss.connect(&"lives_changed", _on_lives_changed)
	_lives_left = int(boss.call(&"lives_left"))
	_lives_total = int(boss.call(&"lives_total"))


func _on_lives_changed(left: int, total: int) -> void:
	_lives_left = left
	_lives_total = total
	if _tracked_boss != null:
		_read_look(_tracked_boss)


## El jefe pide que su barra se vaya o vuelva sin dejar de seguirlo. Al
## volver se llena desde cero con su nombre y su color de ahora.
func _on_bar_visible_changed(shown: bool) -> void:
	visible = shown
	set_process(shown)
	if not shown or _tracked_boss == null or _boss_health == null:
		return
	_read_look(_tracked_boss)
	max_value = _boss_health.max_hp
	_known_hp = _boss_health.current_hp
	_fill_in(_boss_health.current_hp)


## Nombre y color que el jefe quiera para su barra ahora (ver la cabecera).
func _read_look(boss: Node3D) -> void:
	_color = fill_color
	if boss.has_method(&"bar_color"):
		_color = boss.call(&"bar_color")
	if boss.has_method(&"bar_title"):
		_name_label.text = String(boss.call(&"bar_title"))


## Llena la barra desde cero hasta `target`: al aparecer y en cada fase nueva.
func _fill_in(target: float) -> void:
	_kill_value_tween()
	value = 0.0
	_ghost = 0.0
	_value_tween = create_tween()
	_value_tween.tween_property(self, "value", target, fill_in_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## La misma proporción con otra vida máxima: la misma barra con más o menos
## vida detrás. Pasa el valor y el rastro del daño a la escala nueva, en la
## misma proporción, y sigue hacia la vida de ahora.
func _rescale(new_max: float) -> void:
	var factor := new_max / maxf(max_value, 0.001)
	var shown := value * factor
	_kill_value_tween()
	max_value = new_max
	value = shown
	_ghost *= factor
	_ease_to(_known_hp)


## Suaviza la barra hacia `target`; mata la animación anterior para que los
## golpes seguidos converjan en vez de apilarse.
func _ease_to(target: float) -> void:
	_kill_value_tween()
	_value_tween = create_tween()
	_value_tween.tween_property(self, "value", target, tween_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _kill_value_tween() -> void:
	if _value_tween != null and _value_tween.is_valid():
		_value_tween.kill()
	_value_tween = null
