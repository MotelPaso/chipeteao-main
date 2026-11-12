extends CanvasLayer
## HUD de la partida (capa 5; el selector de cartas, capa 10, dibuja encima).
## Este nodo raíz lleva la vida, la XP, el nivel, el reloj, las bajas, los
## puntos, la dificultad y la etapa. Lo demás son componentes en HUD.tscn,
## cada uno con su aspecto en sus propiedades: racha (%StreakLabel), anuncios
## (%AnnounceLabel), jefe (%BossBar, %BossArrow), franjas de equipo
## (%BuildStrip, %BagStrip), power-ups (%PowerUpRow), compañeros (%MatePanel),
## botín (%LootToast), FPS (%FpsBadge), clima (%WeatherBadge), sonda de
## depuración (%PerfProbe) y mapas (%ViewWidgets).
##
## API por grupo: los demás sistemas llegan aquí con call_group("hud" o
## "boss_ui", "<método>", ...), es decir, por el NOMBRE del método. No cambies
## estos nombres sin buscar cada llamada (grep -rn '"hud"\|"boss_ui"' scripts):
##   announce(message)                 jefes, altares, eventos, objetos
##   announce_major(message)           evoluciones, etapa nueva, supervivencia
##   show_loot(title, description, color, player_index)  bolsas, power-ups, cartas
##   track_boss(boss, title)           BossBase al entrar a la arena
##   track_objective(node)             WorldDirector (portal de salida)
##   show_stage_tag(stage_index, lap)  RunRoot y RunSystems
##   on_stage_started(arena)           WorldDirector, al empezar cada etapa
##   set_quake_offset(shift)           WeatherDirector (terremoto)
## El soak (scenes/tests/arena_probe.gd) lee `offset` de este nodo por el grupo "hud".

@export_group("Vida")
## Color de la barra de vida desde hp_full_ratio hacia arriba.
@export var hp_full_color: Color = Color(0.36, 0.8, 0.42)
## Color de la barra de vida casi en cero; entre ambos se mezclan.
@export var hp_low_color: Color = Color(0.9, 0.22, 0.2)
## Fracción de vida (0-1) desde la que la barra usa hp_full_color. La misma
## rampa colorea las barras de los compañeros (%MatePanel).
@export var hp_full_ratio: float = 0.6
## Radio base de la barra de vida (px): el relleno usa este valor - 1 y el fondo + 1.
@export var hp_corner_radius: int = 8
## Texto sobre la barra: vida actual y máxima.
@export var hp_format: String = "%d / %d"
@export_group("Latido de vida baja")
## Bajo esta fracción de vida (0-1) la barra late para empujar al jugador hacia
## los orbes de vida; al curarse por encima, se detiene.
@export var low_hp_pulse_ratio: float = 0.35
## Un latido completo (bajar y volver) dura el doble de estos segundos.
@export var low_hp_pulse_half_period: float = 0.45
## Opacidad más baja de la barra durante el latido (0-1).
@export var low_hp_pulse_alpha: float = 0.6
## Escala más alta de la barra durante el latido.
@export var low_hp_pulse_scale: Vector2 = Vector2(1.03, 1.08)
@export_group("Experiencia")
## Color de la barra de XP (UiTheme.XP_GREEN, el verde de las gemas de XP).
@export var xp_color: Color = UiTheme.XP_GREEN
## Fondo de la franja de XP.
@export var xp_trough_color: Color = Color(0.04, 0.045, 0.07, 0.85)
## Línea inferior de la franja de XP.
@export var xp_line_color: Color = Color(0.0, 0.0, 0.0, 0.6)
## Radio de las esquinas de la franja de XP y de su relleno, en píxeles (0 = cuadrada).
@export var xp_corner_radius: int = 0
## Grosor de la línea inferior de la franja de XP, en píxeles.
@export var xp_line_width: int = 1
@export_group("Barras")
## Segundos que tardan las barras de vida y XP en llegar a su nuevo valor.
@export var bar_tween_time: float = 0.15
@export_group("Textos")
## Reloj de la partida: minutos y segundos.
@export var timer_format: String = "%02d:%02d"
## Contador de bajas.
@export var kills_format: String = "Bajas: %d"
## Puntos del jugador 1.
@export var points_format: String = UiTheme.POINTS_AMOUNT
## Dificultad de la partida en porcentaje (%% es el signo %).
@export var difficulty_format: String = "Dificultad +%d%%"
## Etiqueta de etapa en la primera vuelta; empieza en E1.
@export var stage_format: String = "E%d"
## Etiqueta de etapa desde la segunda vuelta: etapa y vuelta.
@export var stage_lap_format: String = "E%d · V%d"
@export_group("Animación")
## Escala máxima del golpe del nivel al subir.
@export var level_pop_scale: float = 1.3
## Duración del golpe del nivel, en segundos.
@export var level_pop_time: float = 0.3
## Escala máxima del golpe de los puntos al cambiar.
@export var points_pop_scale: float = 1.15
## Duración del golpe de los puntos, en segundos.
@export var points_pop_time: float = 0.18
@export_group("Letra")
## Espacio extra entre los números del reloj, en píxeles.
@export var timer_letter_spacing: int = 4

var _health: Health
var _hp_fill: StyleBoxFlat
## Últimos (actual, máximo) que dibujó _refresh_hp. NAN nunca es igual a nada,
## así que la primera llamada siempre dibuja.
var _hp_drawn_current: float = NAN
var _hp_drawn_max: float = NAN
var _hp_value_tween: Tween = null
var _xp_value_tween: Tween = null
var _hp_pulse_tween: Tween = null
var _hp_pulsing: bool = false
var _last_kills: int = 0
## Último segundo entero pintado en el reloj: el texto cambia una vez por
## segundo, y darle formato cada cuadro rehace el layout de la fuente espaciada.
var _shown_second: int = -1

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _level_label: Label = %LevelLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _kills_label: Label = %KillsLabel
@onready var _points_label: Label = %PointsLabel
@onready var _curse_label: Label = %CurseLabel
@onready var _stage_label: Label = %StageLabel
@onready var _streak: StreakPopup = %StreakLabel
@onready var _announce: AnnounceBanner = %AnnounceLabel
@onready var _boss_bar: BossBar = %BossBar
@onready var _boss_arrow: BossArrow = %BossArrow
@onready var _build_strip: LoadoutStrip = %BuildStrip
@onready var _bag_strip: LoadoutStrip = %BagStrip
@onready var _powerup_row: PowerUpRow = %PowerUpRow
@onready var _mate_panel: MatePanel = %MatePanel
@onready var _loot_toast: LootToast = %LootToast
@onready var _view_widgets: ViewWidgets = %ViewWidgets


func _ready() -> void:
	add_to_group("boss_ui")
	add_to_group("hud")
	_apply_styles()
	_mate_panel.hp_color = hp_color
	RunState.xp_changed.connect(_on_xp_changed)
	RunState.leveled_up.connect(_on_leveled_up)
	RunState.kills_changed.connect(_on_kills_changed)
	RunState.difficulty_changed.connect(_on_difficulty_changed)
	_on_xp_changed(RunState.xp, RunState.xp_to_next)
	_on_leveled_up(RunState.level)
	_on_kills_changed(RunState.kills)
	_on_difficulty_changed(RunState.difficulty_bonus)
	# Diferido: en co-op los otros jugadores aparecen en RunSystems._ready,
	# que corre después del _ready de este hijo; un salto diferido los ve a todos.
	_bind_party.call_deferred()


func _process(_delta: float) -> void:
	var total := int(RunState.run_time)
	if total != _shown_second:
		_shown_second = total
		_timer_label.text = timer_format % [floori(total / 60.0), total % 60]


# --- API por grupo ("hud" y "boss_ui"): ver la lista arriba. ----------------

## Cartel breve que se desvanece solo.
func announce(message: String) -> void:
	_announce.announce(message)


## Cartel de recompensa: dorado, con golpe de escala y más tiempo en pantalla.
func announce_major(message: String) -> void:
	_announce.announce_major(message)


## Tarjeta de botín en cola; `player_index` solo se muestra en co-op.
func show_loot(title: String, description: String, color: Color,
		player_index: int = 0) -> void:
	_loot_toast.show_loot(title, description, color, player_index)


## La barra del jefe pasa a seguir a `boss` con `title` como nombre.
func track_boss(boss: Node3D, title: String) -> void:
	_boss_bar.track(boss, title)


## La flecha de objetivo apunta a `node` mientras no viva un jefe (null la suelta).
func track_objective(node: Node3D) -> void:
	_boss_arrow.track_objective(node)


## Etiqueta de etapa, sobre los puntos: "E%d" y, desde que el grupo dio la
## vuelta a la lista de mapas, "E%d · V%d". En pantalla ambos empiezan en 1;
## RunState los guarda desde 0. GLOSARIO regla 6: Nivel/Nv es el jugador,
## Etapa/E el mapa, Vuelta/V la vuelta y Rango una reliquia.
func show_stage_tag(stage_index: int, lap: int) -> void:
	_stage_label.visible = true
	_stage_label.text = stage_format % (stage_index + 1) if lap <= 0 \
			else stage_lap_format % [stage_index + 1, lap + 1]


## Gancho de etapa (también en la etapa 0, así el primer mapa no necesita caso
## especial): refresca el minimapa y el mapa de Tab de cada vista.
func on_stage_started(arena: Node3D = null) -> void:
	_view_widgets.on_stage_started(arena)


## Terremoto: mueve ESTA CanvasLayer, lo que desplaza todo lo que contiene
## (barras, reloj, franjas y minimapas) en una sola escritura. El mapa de Tab
## vive en su propia capa y se queda quieto a propósito: un mapa que tiembla no
## se puede leer.
func set_quake_offset(shift: Vector2) -> void:
	offset = shift


## Color de una barra de vida según la vida: hp_low_color en 0, mezclado hasta
## hp_full_color en hp_full_ratio y por encima. Lo usan esta barra y las de
## los compañeros.
func hp_color(current: float, max_hp: float) -> Color:
	var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	return hp_low_color.lerp(hp_full_color, clampf(ratio / hp_full_ratio, 0.0, 1.0))


# --- grupo de jugadores ------------------------------------------------------

## Une la barra de vida, los puntos, las franjas y los power-ups al jugador 1
## y, en co-op, agrega una fila por cada otro jugador. Después crea los mapas
## de cada vista.
func _bind_party() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	players.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get("player_index")) < int(b.get("player_index")))
	for node: Node in players:
		var health := Health.find_in(node)
		if health == null:
			continue
		if _health == null and int(node.get("player_index")) == 0:
			_bind_main_player(node, health)
		elif Coop.is_coop():
			_mate_panel.add_mate(int(node.get("player_index")), health, node)
	_view_widgets.build(players.size())


func _bind_main_player(node: Node, health: Health) -> void:
	_health = health
	_health.damaged.connect(_on_health_damaged)
	_health.hp_changed.connect(_refresh_hp)
	_health.died.connect(_on_health_died)
	_refresh_hp(_health.current_hp, _health.max_hp)
	# Señal del jugador, conectada por nombre (player.gd la declara).
	if node.has_signal("points_changed"):
		node.connect("points_changed", _on_points_changed)
		_on_points_changed(int(node.get("points")))
	_build_strip.set_player(node)
	_bag_strip.set_player(node)
	_powerup_row.set_player(node)


# --- vida ---------------------------------------------------------------------

func _on_health_damaged(_amount: float, current: float) -> void:
	_refresh_hp(current, _health.max_hp)
	Juice.player_hurt()


func _on_health_died() -> void:
	_refresh_hp(0.0, _health.max_hp)


func _refresh_hp(current: float, max_hp: float) -> void:
	# Repetir los números ya dibujados, con la barra quieta en ellos (misma
	# escala, valor exacto y sin animación en curso), no hace nada: el texto,
	# el color y el latido dependen solo de estos dos números. El robo de vida
	# manda justo eso en cada golpe con la vida llena. Si falta cualquier
	# condición corre el camino normal, así una animación cortada se reinicia.
	if current == _hp_drawn_current and max_hp == _hp_drawn_max \
			and _hp_bar.max_value == max_hp and _hp_bar.value == current \
			and (_hp_value_tween == null or not _hp_value_tween.is_valid()):
		return
	_hp_drawn_current = current
	_hp_drawn_max = max_hp
	# Salta directo cuando cambia la escala (partida nueva o más vida máxima)
	# para no animar entre dos escalas distintas; si no, se suaviza.
	if not is_equal_approx(_hp_bar.max_value, max_hp):
		_hp_bar.max_value = max_hp
		_hp_bar.value = current
	else:
		_hp_value_tween = _tween_bar_value(_hp_bar, current, _hp_value_tween)
	# ceili, para que un último pedazo de vida se lea "1" y no un "0" adelantado.
	_hp_label.text = hp_format % [ceili(current), roundi(max_hp)]
	UiTheme.recolor_fill(_hp_fill, hp_color(current, max_hp))
	var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	_update_low_hp_pulse(current > 0.0 and ratio < low_hp_pulse_ratio)


## Suavizado común hacia el nuevo valor de una barra; mata el anterior primero
## para que los golpes seguidos converjan en vez de apilarse.
func _tween_bar_value(bar: ProgressBar, target: float, previous: Tween) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	tween.tween_property(bar, "value", target, bar_tween_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween


## Inicia o detiene el latido de vida baja; idempotente por estado, así el
## daño seguido no reinicia el ciclo a mitad. Con vida cero (muerte) también se
## detiene: ese momento es de la pantalla de fin.
func _update_low_hp_pulse(should_pulse: bool) -> void:
	if should_pulse == _hp_pulsing:
		return
	_hp_pulsing = should_pulse
	if _hp_pulse_tween != null and _hp_pulse_tween.is_valid():
		_hp_pulse_tween.kill()
		_hp_pulse_tween = null
	_hp_bar.pivot_offset = _hp_bar.size * 0.5
	if not should_pulse:
		_hp_bar.modulate.a = 1.0
		_hp_bar.scale = Vector2.ONE
		return
	_hp_pulse_tween = create_tween().set_loops()
	_hp_pulse_tween.tween_property(_hp_bar, "modulate:a", low_hp_pulse_alpha,
			low_hp_pulse_half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.parallel().tween_property(_hp_bar, "scale", low_hp_pulse_scale,
			low_hp_pulse_half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.chain().tween_property(_hp_bar, "modulate:a", 1.0,
			low_hp_pulse_half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.parallel().tween_property(_hp_bar, "scale", Vector2.ONE,
			low_hp_pulse_half_period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- XP, nivel, bajas, puntos y dificultad ------------------------------------

func _on_xp_changed(current_xp: int, xp_to_next: int) -> void:
	# Un umbral nuevo significa que se subió de nivel: salta a la nueva escala.
	if not is_equal_approx(_xp_bar.max_value, float(xp_to_next)):
		_xp_bar.max_value = xp_to_next
		_xp_bar.value = current_xp
	else:
		_xp_value_tween = _tween_bar_value(_xp_bar, float(current_xp), _xp_value_tween)


func _on_leveled_up(new_level: int) -> void:
	_level_label.text = UiTheme.LEVEL_ABBREV % new_level
	UiTheme.pop(_level_label, level_pop_scale, level_pop_time)


func _on_kills_changed(kills: int) -> void:
	_kills_label.text = kills_format % kills
	if kills <= _last_kills:
		# Contador reiniciado (partida nueva), no una baja: se limpia la racha.
		_last_kills = kills
		_streak.reset()
		return
	_last_kills = kills
	_streak.on_kill()


func _on_points_changed(total: int) -> void:
	_points_label.text = points_format % total
	UiTheme.pop(_points_label, points_pop_scale, points_pop_time)


## Dificultad de la partida, arriba al centro (altares demoníacos, Tomo del
## Peligro, ruleta); oculta mientras es cero.
func _on_difficulty_changed(bonus: float) -> void:
	_curse_label.visible = bonus > 0.001
	_curse_label.text = difficulty_format % roundi(bonus * 100.0)


# --- estilos ------------------------------------------------------------------

## Estilos de UiTheme: barras en capas (fondo, relleno, línea de brillo y
## borde de avance) y pastillas para nivel, reloj, bajas y puntos. El color
## del texto de cada pastilla es el de su nodo en HUD.tscn.
func _apply_styles() -> void:
	_hp_fill = UiTheme.style_bar(_hp_bar, hp_full_color, hp_corner_radius)
	# La franja de XP sigue de borde a borde y cuadrada, pero gana la línea de
	# brillo y un borde de avance claro para leer el progreso de un vistazo.
	var xp_trough := UiTheme.flat(xp_trough_color, xp_corner_radius)
	xp_trough.border_width_bottom = xp_line_width
	xp_trough.border_color = xp_line_color
	_xp_bar.add_theme_stylebox_override("background", xp_trough)
	_xp_bar.add_theme_stylebox_override("fill", UiTheme.bar_fill(xp_color, xp_corner_radius))
	for label: Label in [_level_label, _kills_label, _points_label, _timer_label]:
		UiTheme.style_badge(label, label.get_theme_color(&"font_color"))
	_timer_label.add_theme_font_override("font", UiTheme.spaced_font(timer_letter_spacing))
