extends CanvasLayer
## HUD de la partida: barra de vida con su número, barra fina de XP con el
## nivel, reloj MM:SS, contador de bajas y, arriba al centro, la barra del
## jefe (solo mientras vive uno) y el cartel de anuncios. Los demás sistemas
## lo alcanzan por los grupos "hud" y "boss_ui", nunca por ruta de nodo.
## Encuentra al jugador por su grupo y lee RunState por el autoload; las
## señales mueven casi todo y solo el reloj se consulta en _process. Se pausa
## con el árbol: run_time se congela y la capa de cartas (10) dibuja encima
## de esta (5).

## Desde esta fracción de vida hacia arriba la barra es verde pleno; por
## debajo se acerca al rojo.
const LOW_HP_RATIO := 0.6

const HP_FULL_COLOR := Color(0.36, 0.8, 0.42)
const HP_LOW_COLOR := Color(0.9, 0.22, 0.2)
## Mismo verde que el material de las gemas de XP (XpGem.tscn): la barra se
## lee como "gemas juntadas".
const XP_COLOR := Color(0.35, 0.95, 0.6)
## Mismo ámbar que las vetas del núcleo del Rotking.
const BOSS_BAR_COLOR := Color(0.98, 0.62, 0.16)
## Segundos que tarda una barra en llegar a su nuevo valor (no salta).
const BAR_TWEEN_TIME := 0.15

## Racha de bajas: las bajas dentro de esta ventana móvil (segundos) cuentan
## para los umbrales de abajo; 2 s sin bajas reinician la racha y los niveles
## pueden volver a dispararse.
const STREAK_WINDOW := 2.0
const STREAK_KILLS: Array[int] = [8, 15, 25]
const STREAK_WORDS: Array[String] = ["¡TRITURANDO!", "¡ARRASANDO!", "¡IMPARABLE!"]
## Color del texto de racha por nivel: dorado, naranja, rojo fuego.
const STREAK_COLORS: Array[Color] = [
	Color(1.0, 0.86, 0.25), Color(1.0, 0.62, 0.16), Color(1.0, 0.34, 0.2)]

## Variable de entorno que enciende la sonda de rendimiento (verificación headless).
const PERF_PROBE_ENV := "BONK_PERF"
const PERF_PROBE_REFRESH := 0.25

## Indicador de FPS para el jugador, arriba a la derecha; se activa en Ajustes
## y se guarda en SaveData.show_fps. No es la sonda de rendimiento: esa es
## para desarrollo, esta es una opción del juego y solo muestra los FPS.
const FPS_BADGE_REFRESH := 0.25
## Margen derecho y alto desde arriba del indicador, en píxeles.
const FPS_BADGE_OFFSET := Vector2(16.0, 88.0)
## Alto que ocupa el indicador (fuente 13 más el relleno de UiTheme). Solo
## sirve para colocar lo que cuelga debajo, así que basta con que sobre.
const FPS_BADGE_HEIGHT := 26.0
const FPS_BADGE_FONT_SIZE := 13
const FPS_BADGE_TEXT := "%d FPS"

## Sonda de depuración (no es para el jugador): FPS y conteos de enemigos,
## gemas, proyectiles y pools. Viene apagada; se enciende aquí o con BONK_PERF=1.
@export var show_perf_probe: bool = false

## Bajo esta fracción de vida la barra late suavemente (alfa y escala) para
## empujar al jugador hacia los orbes de vida; al curarse por encima, se detiene.
@export var low_hp_pulse_ratio: float = 0.35
## Un latido completo (bajar y volver) dura el doble de estos segundos.
@export var low_hp_pulse_half_period: float = 0.45

## Precargado y no por class_name: así lo resuelven también las corridas
## headless que no construyeron la caché de clases del editor.
const SplitScreenView := preload("res://scripts/systems/split_screen.gd")

## Margen del minimapa respecto de la esquina superior derecha de su celda.
const MINIMAP_MARGIN := Vector2(14.0, 14.0)
## Margen superior del minimapa en las celdas que tocan el borde superior de
## la ventana: lo baja por debajo de la columna de arriba a la derecha.
const MINIMAP_TOP_UNDER_HUD: float = FPS_BADGE_OFFSET.y + FPS_BADGE_HEIGHT + 8.0
## El mapa de Tab dibuja sobre el HUD y bajo el selector de cartas (capa 10).
const MAP_OVERLAY_LAYER: int = 8

## Minimapa y mapa de Tab por jugador; se crean una vez en _bind_party y
## on_stage_started solo refresca su contenido.
var _minimaps: Array[Minimap] = []
var _overlays: Array[MapOverlay] = []

## --- power-ups activos ------------------------------------------------------
## Fila de casillas abajo al centro, cada una con el glifo del power-up y los
## segundos que le quedan. Solo del jugador 1: en co-op la fila de cada
## compañero muestra un conteo.
const POWERUP_ROW_OFFSET := Vector2(0.0, -104.0)
const POWERUP_REFRESH: float = 0.2
var _powerup_box: HBoxContainer = null
## Ids de las casillas de la fila, en orden: su ESTRUCTURA. Solo un cambio
## aquí reconstruye la fila; los segundos de las esquinas se cambian en su lugar.
var _powerup_ids: String = ""
## Texto y Label de la esquina de cada casilla, en orden (ver
## _swap_powerup_corners). Un Label nulo es una casilla sin esquina.
var _powerup_corner_texts: PackedStringArray = PackedStringArray()
var _powerup_corners: Array[Label] = []
var _powerup_refresh_left: float = 0.0
## Ranura -> chip con el conteo de power-ups en la fila de ese compañero.
var _mate_powerup_chips: Dictionary[int, Label] = {}

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _level_label: Label = %LevelLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _kills_label: Label = %KillsLabel
@onready var _points_label: Label = %PointsLabel
@onready var _boss_bar: ProgressBar = %BossBar
@onready var _boss_name_label: Label = %BossNameLabel
@onready var _announce_label: Label = %AnnounceLabel
@onready var _curse_label: Label = %CurseLabel
@onready var _stage_label: Label = %StageLabel
@onready var _streak_label: Label = %StreakLabel

var _hp_fill: StyleBoxFlat
var _health: Health
## Últimos (actual, máximo) que dibujó _refresh_hp. NAN nunca es igual a nada,
## así que la primera llamada siempre dibuja.
var _hp_drawn_current: float = NAN
var _hp_drawn_max: float = NAN
var _hp_value_tween: Tween = null
var _xp_value_tween: Tween = null
var _boss_value_tween: Tween = null
var _hp_pulse_tween: Tween = null
var _hp_pulsing: bool = false
var _tracked_boss: Node3D = null
var _boss_health: Health = null
var _announce_tween: Tween
var _streak_tween: Tween
## Momentos (run_time) de las bajas recientes; se podan a STREAK_WINDOW en cada baja.
var _streak_kill_times: Array[float] = []
## Índice más alto de STREAK_KILLS disparado en esta racha; -1 si ninguno.
var _streak_tier: int = -1
var _last_kills: int = 0
var _probe_label: Label = null
var _probe_refresh_left: float = 0.0
var _fps_label: Label = null
var _fps_refresh_left: float = 0.0
## Último segundo entero pintado en el reloj: el texto cambia una vez por
## segundo, y darle formato cada cuadro rehace el layout de la fuente espaciada.
var _shown_second: int = -1

## Franjas de equipo del jugador 1: abajo a la izquierda armas (con nivel),
## tomos (con pilas) y mascota; abajo a la derecha los objetos (con copias).
## Se reconstruyen solo cuando cambia su firma; se consultan dos veces por segundo.
const LOADOUT_REFRESH := 0.5
const LOADOUT_WEAPON_COLOR := Color(0.3, 0.82, 0.76)
const LOADOUT_TOME_COLOR := Color(0.72, 0.5, 0.95)
const LOADOUT_SLOT_SIZE := Vector2(44.0, 44.0)
const LOADOUT_GLYPH_FONT_SIZE := 16
const LOADOUT_CORNER_FONT_SIZE := 10
## Espacio en blanco entre los grupos de armas, tomos y mascota, en píxeles.
const LOADOUT_GROUP_GAP := 8.0
## Distancia de las dos franjas de abajo al borde inferior de la ventana, y
## su alto, en píxeles.
const BOTTOM_STRIP_MARGIN := 36.0
const BOTTOM_STRIP_HEIGHT := 48.0
## Convención de íconos: una casilla dibuja res://assets/icons/<biblioteca>/<id>.png
## si existe y, si no, ICON_PLACEHOLDER con el glifo del catálogo encima; así se
## agregan sprites por id sin tocar código. El `icon` propio de una fila de
## catálogo gana sobre ambos.
const ICON_ROOT := "res://assets/icons/"
const ICON_PLACEHOLDER := "res://assets/icons/placeholder.png"
const ICON_LIBRARY_WEAPONS := "weapons"
const ICON_LIBRARY_TOMES := "tomes"
const ICON_LIBRARY_ITEMS := "items"
const ICON_LIBRARY_POWERUPS := "powerups"
const ICON_LIBRARY_PETS := "pets"

## --- clima y temblor --------------------------------------------------------
## Nombre para el jugador por id de clima (los ids de WEATHER_CATALOG en
## world_director.gd). Un id sin fila aquí se muestra con su id crudo.
const WEATHER_NAMES: Dictionary[String, String] = {
	"blood_moon": "Luna de sangre",
	"eclipse": "Eclipse",
	"full_moon": "Luna llena",
	"enemy_rain": "Lluvia de enemigos",
	"radioactive_rain": "Lluvia radiactiva",
	"golden_rain": "Lluvia dorada",
	"enemy_tsunami": "Tsunami",
	"earthquake": "Terremoto",
	"meteor_shower": "Lluvia de meteoritos",
}
## Tinte por GRUPO de clima, no por id: tres colores se leen como tres tipos
## de peligro; nueve se leerían como decoración.
const WEATHER_GROUP_COLORS: Dictionary[String, Color] = {
	"moon": Color(0.85, 0.75, 1.0),
	"rain": Color(0.55, 0.9, 1.0),
	"disaster": Color(1.0, 0.55, 0.3),
}
const WEATHER_BADGE_REFRESH: float = 0.2
## Separación, en píxeles, entre el borde inferior del reloj y el chip de
## clima que cuelga debajo.
const WEATHER_BADGE_GAP: float = 4.0
## Caída mínima del chip desde el borde superior del reloj, en píxeles.
const WEATHER_BADGE_MIN_DROP: float = 46.0

var _weather_badge: Label = null
var _weather_refresh_left: float = 0.0
var _weather_signature: String = ""
## Último desplazamiento de terremoto recibido por set_quake_offset.
var _quake_offset: Vector2 = Vector2.ZERO
## Glifo sobre la imagen de reemplazo: más chico que el de una casilla sin
## imagen, para que se lea como etiqueta sobre el arte y no como el arte.
const LOADOUT_PLACEHOLDER_GLYPH_SIZE := 13
## Columna de compañeros (solo co-op): tamaño de la barra y esquina superior izquierda.
const MATE_BAR_SIZE := Vector2(150.0, 16.0)
const MATE_BOX_OFFSET := Vector2(16.0, 96.0)
const MATE_FONT_SIZE := 13
## Los nombres de tomo llevan el tipo como prefijo ("Tomo de Furia") y el
## glifo de respaldo sale de lo que queda. Del más largo al más corto, para que
## "Tomo del Azar" pierda "Tomo del " entero y no solo "Tomo de " (dejaría
## "l Azar"). El prefijo en inglés queda para filas sin traducir.
const TOME_NAME_PREFIXES: Array[String] = ["Tome of ", "Tomo del ", "Tomo de "]
var _loadout_box: HBoxContainer = null
## Franja propia de los objetos, abajo a la derecha: armas y tomos son el
## equipo (con nivel y pilas), los objetos son la bolsa (con copias).
var _items_box: HBoxContainer = null
var _loadout_player: Node = null
var _loadout_signature: String = ""
var _loadout_refresh_left: float = 0.0

## Aviso de botín: una tarjeta que sube abajo al centro cada vez que algo
## entra a una bolsa (objeto de cofre, premio de ruleta, tirada del Tomo del
## Azar, power-up). Llega por el grupo "hud" como show_loot(), así que una
## fuente nueva de botín no necesita cambios en el HUD. Los avisos se ponen
## EN COLA en vez de pisarse.
const LOOT_TOAST_TIME: float = 3.0
const LOOT_TOAST_FADE: float = 0.25
const LOOT_TOAST_SLIDE: float = 26.0
const LOOT_TOAST_WIDTH: float = 340.0
const LOOT_TOAST_BOTTOM: float = -108.0
const LOOT_TITLE_FONT_SIZE: int = 17
const LOOT_DESC_FONT_SIZE: int = 13
## Etiqueta de jugador en co-op, para saber de quién fue el botín.
const LOOT_PLAYER_TAG := "J%d"
var _loot_box: PanelContainer = null
var _loot_title: Label = null
var _loot_desc: Label = null
var _loot_queue: Array[Dictionary] = []
var _loot_tween: Tween = null
var _loot_showing: bool = false


func _ready() -> void:
	# Jefes, spawner y director llegan a esta capa por "boss_ui"; altares,
	# bolsas y demás por "hud". Nunca por ruta de nodo.
	add_to_group("boss_ui")
	add_to_group("hud")
	_apply_styles()
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
	if show_perf_probe or OS.get_environment(PERF_PROBE_ENV) == "1":
		_build_perf_probe()


## Une la barra de vida principal al jugador 1 y, en co-op, crea una fila
## compacta por cada otro jugador (etiqueta, barra y puntos; K.O. mientras
## está caído).
func _bind_party() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	players.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get("player_index")) < int(b.get("player_index")))
	for node: Node in players:
		var health := Health.find_in(node)
		if health == null:
			continue
		if _health == null and int(node.get("player_index")) == 0:
			_health = health
			_health.damaged.connect(_on_health_damaged)
			_health.hp_changed.connect(_refresh_hp)
			_health.died.connect(_on_health_died)
			_refresh_hp(_health.current_hp, _health.max_hp)
			_loadout_player = node
			if node.has_signal("points_changed"):
				node.connect("points_changed", _on_points_changed)
				_on_points_changed(int(node.get("points")))
			_refresh_loadout()
		elif Coop.is_coop():
			_build_mate_bar(int(node.get("player_index")), health, node)
	# Un minimapa y un mapa de Tab POR VISTA, jugador 1 incluido: en pantalla
	# dividida cada jugador mira su propia celda.
	_build_map_widgets(players.size())



## Crea los mapas de cada vista, anclados a la misma celda donde dibuja la
## cámara de ese jugador (SplitScreen.cell_rect): en co-op cada mapa queda en
## la esquina de SU jugador.
func _build_map_widgets(player_count: int) -> void:
	if not _minimaps.is_empty():
		return
	var count := maxi(player_count, 1)
	for slot in count:
		var cell := SplitScreenView.cell_rect(slot, count)
		var minimap := Minimap.new()
		# No usa _anchor_to_cell: el minimapa no LLENA su celda, cuelga de la
		# esquina superior derecha de la celda.
		minimap.anchor_left = cell.position.x + cell.size.x
		minimap.anchor_right = cell.position.x + cell.size.x
		minimap.anchor_top = cell.position.y
		minimap.anchor_bottom = cell.position.y
		minimap.offset_left = -Minimap.SIZE - MINIMAP_MARGIN.x
		minimap.offset_right = -MINIMAP_MARGIN.x
		# Las celdas del borde superior comparten ese borde con la columna de
		# bajas y FPS; las de abajo solo usan su margen.
		var top := MINIMAP_TOP_UNDER_HUD if is_zero_approx(cell.position.y) \
				else MINIMAP_MARGIN.y
		minimap.offset_top = top
		minimap.offset_bottom = top + Minimap.SIZE
		add_child(minimap)
		_minimaps.append(minimap)
		# Su propia CanvasLayer: el mapa de Tab dibuja SOBRE este HUD y bajo
		# el selector de cartas, y un Control no cruza capas.
		var overlay_layer := CanvasLayer.new()
		overlay_layer.layer = MAP_OVERLAY_LAYER
		add_child(overlay_layer)
		var overlay := MapOverlay.new()
		overlay.slot = slot
		_anchor_to_cell(overlay, cell)
		overlay_layer.add_child(overlay)
		_overlays.append(overlay)


func _anchor_to_cell(control: Control, cell: Rect2) -> void:
	control.anchor_left = cell.position.x
	control.anchor_top = cell.position.y
	control.anchor_right = cell.position.x + cell.size.x
	control.anchor_bottom = cell.position.y + cell.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


## Gancho de etapa, reenviado por WorldDirector.on_stage_started por el grupo
## "hud". No es la señal stage_changed: esta llamada también ocurre en la
## etapa 0, así que el primer mapa no necesita caso especial.
func on_stage_started(arena: Node3D = null) -> void:
	for minimap: Minimap in _minimaps:
		if is_instance_valid(minimap):
			minimap.on_stage_started(arena)
	for overlay: MapOverlay in _overlays:
		if is_instance_valid(overlay):
			overlay.on_stage_started(arena)


## Columna de compañeros (solo co-op): etiqueta "J2", barra de vida delgada y
## puntos de cada jugador extra, arriba a la izquierda.
var _mate_box: VBoxContainer = null


func _build_mate_bar(slot: int, health: Health, body: Node) -> void:
	if _mate_box == null:
		_mate_box = VBoxContainer.new()
		_mate_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_mate_box.offset_left = MATE_BOX_OFFSET.x
		_mate_box.offset_top = MATE_BOX_OFFSET.y
		_mate_box.add_theme_constant_override("separation", 6)
		# Hijo directo de la CanvasLayer: las anclas se resuelven contra el viewport.
		add_child(_mate_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag := Label.new()
	tag.text = "J%d" % (slot + 1)
	UiTheme.style_badge(tag, UiTheme.TEXT_BRIGHT)
	row.add_child(tag)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = MATE_BAR_SIZE
	bar.show_percentage = false
	bar.max_value = health.max_hp
	bar.value = health.current_hp
	var fill := UiTheme.style_bar(bar, HP_FULL_COLOR, 6)
	row.add_child(bar)
	# Los puntos son una billetera POR JUGADOR (cofres, manantial y ruleta
	# cobran al que interactúa), así que cada fila lleva su propio contador; el
	# chip ámbar de la derecha es solo del jugador 1.
	_add_mate_points_chip(row, body)
	# Conteo de power-ups de este compañero; oculto mientras no tenga ninguno.
	var powerup_chip := Label.new()
	UiTheme.style_badge(powerup_chip, UiTheme.ACCENT)
	powerup_chip.visible = false
	row.add_child(powerup_chip)
	_mate_powerup_chips[slot] = powerup_chip
	_mate_box.add_child(row)
	var refresh := func(current: float, max_hp: float) -> void:
		bar.max_value = max_hp
		bar.value = current
		var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
		UiTheme.recolor_fill(fill,
				HP_LOW_COLOR.lerp(HP_FULL_COLOR, clampf(ratio / LOW_HP_RATIO, 0.0, 1.0)))
		tag.text = "J%d" % (slot + 1) if current > 0.0 else "J%d K.O." % (slot + 1)
		tag.modulate = Color.WHITE if current > 0.0 else Color(1.0, 0.45, 0.4)
	health.hp_changed.connect(refresh)
	health.damaged.connect(func(_amount: float, current: float) -> void:
		refresh.call(current, health.max_hp)
		# No Juice.player_hurt(): la viñeta y la sacudida cubren toda la
		# ventana. Que golpeen a un compañero hace saltar SU fila, no tu pantalla.
		UiTheme.pop(tag, 1.18, 0.18))
	health.died.connect(func() -> void: refresh.call(0.0, health.max_hp))


## Chip de puntos de una fila de compañero (no se crea para cuerpos sin
## billetera, p. ej. un sustituto en una escena de prueba).
func _add_mate_points_chip(row: HBoxContainer, body: Node) -> void:
	if not body.has_signal("points_changed"):
		return
	var points := Label.new()
	points.add_theme_font_size_override("font_size", MATE_FONT_SIZE)
	UiTheme.style_badge(points, UiTheme.ACCENT_AMBER)
	points.text = "%d pts" % int(body.get("points"))
	row.add_child(points)
	body.connect("points_changed", func(total: int) -> void:
		points.text = "%d pts" % total
		UiTheme.pop(points, 1.15, 0.18))


func _process(delta: float) -> void:
	var total := int(RunState.run_time)
	if total != _shown_second:
		_shown_second = total
		_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	if _probe_label != null:
		_probe_refresh_left -= delta
		if _probe_refresh_left <= 0.0:
			_probe_refresh_left = PERF_PROBE_REFRESH
			_probe_label.text = _probe_text()
	_loadout_refresh_left -= delta
	if _loadout_refresh_left <= 0.0:
		_loadout_refresh_left = LOADOUT_REFRESH
		_refresh_loadout()
	_fps_refresh_left -= delta
	if _fps_refresh_left <= 0.0:
		_fps_refresh_left = FPS_BADGE_REFRESH
		_refresh_fps_badge()
	_powerup_refresh_left -= delta
	if _powerup_refresh_left <= 0.0:
		_powerup_refresh_left = POWERUP_REFRESH
		_refresh_powerups()
	_weather_refresh_left -= delta
	if _weather_refresh_left <= 0.0:
		_weather_refresh_left = WEATHER_BADGE_REFRESH
		_refresh_weather_badge()


## Consulta SaveData.show_fps en vez de escuchar un cambio: la opción se puede
## cambiar desde la pausa con este HUD vivo, y desde el título antes de que exista.
func _refresh_fps_badge() -> void:
	var wanted := SaveData.show_fps
	if not wanted:
		if _fps_label != null:
			_fps_label.visible = false
		return
	if _fps_label == null:
		_fps_label = Label.new()
		_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_fps_label.offset_right = -FPS_BADGE_OFFSET.x
		_fps_label.offset_top = FPS_BADGE_OFFSET.y
		_fps_label.add_theme_font_size_override("font_size", FPS_BADGE_FONT_SIZE)
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.style_badge(_fps_label, UiTheme.TEXT_BRIGHT,
				Color(0.07, 0.075, 0.11, 0.85), Color(0.3, 0.33, 0.4))
		add_child(_fps_label)
	_fps_label.visible = true
	_fps_label.text = FPS_BADGE_TEXT % roundi(Engine.get_frames_per_second())


func _on_points_changed(total: int) -> void:
	_points_label.text = "%d pts" % total
	UiTheme.pop(_points_label, 1.15, 0.18)


## --- chip de clima ----------------------------------------------------------

## Gancho de grupo (WorldDirector, terremoto): mueve ESTA CanvasLayer, lo que
## desplaza todo lo que contiene (barras, reloj, franjas y minimapas) en una
## sola escritura. El mapa de Tab vive en su propia capa y se queda quieto a
## propósito: un mapa que tiembla no se puede leer.
func set_quake_offset(shift: Vector2) -> void:
	_quake_offset = shift
	offset = shift


## Nombre y segundos restantes del clima activo, o nada. Se lee del director
## en vez de que él lo empuje: el chip es una vista, y empujarlo necesitaría
## una señal desde tres grupos de clima distintos.
func _refresh_weather_badge() -> void:
	var director := get_tree().get_first_node_in_group("world_director")
	var live: Variant = director.get("active_weather") if director != null else null
	var weather := live as Dictionary if live is Dictionary else {}
	if weather.is_empty():
		if _weather_badge != null:
			_weather_badge.visible = false
		_weather_signature = ""
		return
	var weather_id := String(weather.get("id", ""))
	var seconds := ceili(maxf(float(weather.get("time_left", 0.0)), 0.0))
	var signature := "%s|%d" % [weather_id, seconds]
	if signature == _weather_signature:
		return
	_weather_signature = signature
	if _weather_badge == null:
		_weather_badge = _build_weather_badge()
	_weather_badge.visible = true
	_weather_badge.text = "%s %ds" % [
			WEATHER_NAMES.get(weather_id, weather_id), seconds]
	_weather_badge.add_theme_color_override("font_color",
			WEATHER_GROUP_COLORS.get(String(weather.get("group", "")), UiTheme.TEXT_BRIGHT))


## Se crea al primer uso como hijo del reloj, así viaja con él sin un segundo
## juego de anclas.
func _build_weather_badge() -> Label:
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_badge(badge, UiTheme.TEXT_BRIGHT)
	badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Bajo la caja del reloj, medido del propio Label: su alto es la fuente
	# más el relleno que le da UiTheme.
	badge.position = Vector2(0.0,
			maxf(_timer_label.size.y, WEATHER_BADGE_MIN_DROP) + WEATHER_BADGE_GAP)
	_timer_label.add_child(badge)
	return badge


## --- power-ups activos ------------------------------------------------------

## Reconstruye la fila cuando cambió el CONJUNTO de power-ups y solo cambia
## las esquinas cuando cambiaron los segundos enteros (una vez por segundo
## mientras corra alguno). Reconstruir ahí rehace varios nodos, un StyleBox y
## hasta tres ResourceLoader.exists por casilla para cambiar un número.
func _refresh_powerups() -> void:
	# Primero los compañeros, y ANTES de la guarda del jugador 1: sus chips
	# leen los power-ups de los DEMÁS y no deben congelarse si falta el
	# cuerpo del jugador 1 (nunca unido, o liberado).
	_refresh_mate_powerups()
	if _loadout_player == null or not is_instance_valid(_loadout_player):
		return
	var powerups := PowerUps.find_in(_loadout_player)
	var entries: Array[Dictionary] = []
	if powerups != null:
		for live: Dictionary in powerups.active():
			var powerup_id := String(live.id)
			var row := PowerUpCatalog.by_id(powerup_id)
			entries.append({
				"glyph": String(row.get("glyph", "??")),
				"library": ICON_LIBRARY_POWERUPS,
				"entry_id": powerup_id,
				"color": row.get("color", Color.WHITE) as Color,
				"corner": "%ds" % ceili(float(live.time_left)),
				"tip": String(row.get("display_name", powerup_id)),
				"icon": String(row.get("icon", "")),
			})
	var ids := ""
	var corners := PackedStringArray()
	for entry: Dictionary in entries:
		ids += "%s;" % entry.entry_id
		corners.append(String(entry.corner))
	if ids == _powerup_ids and _swap_powerup_corners(corners):
		return
	_powerup_ids = ids
	_powerup_corner_texts = corners
	_powerup_box = _rebuild_powerup_row(entries)


## Mismas casillas, segundos nuevos: cada casilla cuya esquina cambió recibe
## un Label nuevo de _make_corner_label (el mismo constructor de una casilla
## nueva) en el mismo lugar, el último hijo de su Control interior. Lo demás
## de una casilla depende solo de su id, que no cambió, así que la fila queda
## igual que tras una reconstrucción. Devuelve false si una casilla no se
## puede parchar (sin Label de esquina, o esquina vacía, que una casilla nueva
## dibujaría sin Label); entonces el llamador reconstruye la fila.
func _swap_powerup_corners(corners: PackedStringArray) -> bool:
	if corners.size() != _powerup_corners.size():
		return false
	for i in corners.size():
		if corners[i] == _powerup_corner_texts[i]:
			continue
		# Se revisa en la celda del arreglo, antes de pasarlo a una variable tipada.
		if not is_instance_valid(_powerup_corners[i]) or corners[i].is_empty():
			return false
		var old: Label = _powerup_corners[i]
		var inner := old.get_parent()
		# Primero fuera del padre, como en cada reconstrucción: queue_free
		# recién actúa al final del cuadro.
		inner.remove_child(old)
		old.queue_free()
		var fresh := _make_corner_label(corners[i])
		inner.add_child(fresh)
		_powerup_corners[i] = fresh
		_powerup_corner_texts[i] = corners[i]
	return true


func _rebuild_powerup_row(entries: Array[Dictionary]) -> HBoxContainer:
	var box := _powerup_box
	if box == null:
		box = HBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		# Los CUATRO márgenes en el mismo punto: así el contenedor toma su
		# tamaño mínimo y crece hacia arriba y a los lados desde el ancla. Con
		# solo dos, quedaría estirado hasta el borde inferior de la ventana.
		box.offset_left = POWERUP_ROW_OFFSET.x
		box.offset_right = POWERUP_ROW_OFFSET.x
		box.offset_top = POWERUP_ROW_OFFSET.y
		box.offset_bottom = POWERUP_ROW_OFFSET.y
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 6)
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(box)
	for child: Node in box.get_children():
		# Primero fuera del contenedor (ver _rebuild_strip): queue_free recién
		# actúa al final del cuadro y la fila saltaría.
		box.remove_child(child)
		child.queue_free()
	_powerup_corners.clear()
	for entry: Dictionary in entries:
		var slot := _make_loadout_slot(entry)
		box.add_child(slot)
		_powerup_corners.append(slot.get_meta(&"corner_label", null) as Label)
		# Entrega única: desde aquí _powerup_corners es dueño del Label, y una
		# meta que quede apuntaría al Label que libera el próximo cambio de esquina.
		slot.remove_meta(&"corner_label")
	return box


## Co-op: la fila de un compañero muestra el CONTEO, no las casillas ("J3
## tiene tres power-ups activos" es todo lo que necesita saber el grupo).
func _refresh_mate_powerups() -> void:
	for slot: int in _mate_powerup_chips:
		var chip := _mate_powerup_chips[slot]
		if not is_instance_valid(chip):
			continue
		var body := _player_at(slot)
		var powerups := PowerUps.find_in(body) if body != null else null
		var live := powerups.count() if powerups != null else 0
		chip.text = "◈%d" % live if live > 0 else ""
		chip.visible = live > 0


## El jugador en `slot`, de pie o caído (un compañero caído conserva sus
## power-ups activos).
func _player_at(slot: int) -> Node:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if int(node.get("player_index")) == slot:
				return node
	return null


## --- franjas de equipo ------------------------------------------------------

## Reconstruye las franjas cuando cambió el equipo: armas (nivel, ★ al
## evolucionar), tomos (pilas), mascota y objetos (copias). Mientras no haya
## sprites, cada casilla es un recuadro del color de su tipo o rareza con el
## glifo de dos letras de su fila; una fila con `icon` muestra esa textura.
func _refresh_loadout() -> void:
	if _loadout_player == null or not is_instance_valid(_loadout_player):
		return
	var entries: Array[Dictionary] = []
	var mount := _loadout_player.get_node_or_null("Weapons")
	if mount != null:
		for child: Node in mount.get_children():
			var weapon := child as WeaponBase
			if weapon == null:
				continue
			# Nombre y glifo salen de los catálogos: la receta de evolución si
			# el arma evolucionó, la biblioteca de armas si no.
			var row := EvolutionCatalog.by_weapon_node(weapon.name) if weapon.evolved \
					else UpgradePool.weapon_by_node(weapon.name)
			var title := weapon.evolved_name if weapon.evolved \
					else UpgradePool.weapon_display_name(weapon.name)
			entries.append({
				"glyph": _catalog_glyph(row, title),
				"library": ICON_LIBRARY_WEAPONS,
				"entry_id": UpgradePool.weapon_id_for_node(weapon.name),
				"color": UiTheme.ACCENT_AMBER if weapon.evolved else LOADOUT_WEAPON_COLOR,
				# Dos lecturas de la misma escala: el NIVEL del arma mientras
				# sube a su primer hito, después el RANGO del hito. "Sube el arma
				# al nivel 10" es esta esquina llegando a N10, y ★2 es el nivel 20.
				"corner": ("★%d" % weapon.ascension_tier) if weapon.ascension_tier > 0 \
						else (UiTheme.WEAPON_LEVEL_ABBREV % weapon.upgrade_level),
				"tip": title, "icon": String(row.get("icon", "")),
			})
	var stats := PlayerStats.find_in(_loadout_player)
	if stats != null:
		for tome_id: String in stats.carried_tome_ids():
			var tome := Tome.by_id(tome_id)
			var title := String(tome.get("display_name", tome_id))
			entries.append({
				"glyph": _catalog_glyph(tome, _tome_short_name(title)),
				"library": ICON_LIBRARY_TOMES,
				"entry_id": tome_id,
				"color": LOADOUT_TOME_COLOR,
				"corner": Tome.stack_label(stats.stack_count(tome_id)),
				"tip": title, "icon": String(tome.get("icon", "")),
			})
	# La mascota cierra la franja de armas y tomos: es un arma fuera del tope
	# de cinco más una estadística, así que va junto a ellos y no entre los objetos.
	var pet_id: Variant = _loadout_player.get("pet_id")
	if pet_id != null and not String(pet_id).is_empty():
		var pet := PetCatalog.by_id(String(pet_id))
		if not pet.is_empty():
			entries.append({
				"glyph": String(pet.get("glyph", "??")),
				"library": ICON_LIBRARY_PETS,
				"entry_id": String(pet_id),
				"color": pet.get("color", Color.WHITE) as Color,
				"corner": "",
				"tip": "%s — %s" % [String(pet.display_name),
						String(pet.get("stat_label", ""))],
				"icon": String(pet.get("icon", "")),
			})
	var items: Array[Dictionary] = []
	var bag := ItemBag.find_in(_loadout_player)
	if bag != null:
		for item_id: String in bag.carried_ids():
			var row := ItemCatalog.by_id(item_id)
			var copies := bag.count(item_id)
			items.append({
				"glyph": _catalog_glyph(row, item_id),
				"library": ICON_LIBRARY_ITEMS,
				"entry_id": item_id,
				"color": ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
				"corner": "x%d" % copies if copies > 1 else "",
				"tip": String(row.get("display_name", item_id)), "icon": String(row.get("icon", "")),
			})
	var signature := ""
	for entry: Dictionary in entries + items:
		signature += "%s|%s|%s;" % [entry.tip, entry.corner, entry.icon]
	if signature == _loadout_signature:
		return
	_loadout_signature = signature
	_loadout_box = _rebuild_strip(_loadout_box, entries, true)
	_items_box = _rebuild_strip(_items_box, items, false)


## Glifo de una casilla: el `glyph` de dos letras de la fila del catálogo si
## lo declara; si no, el de respaldo. Toda fila del juego declara uno: las
## iniciales de los nombres en español chocan ("Vial de sangre" y "Vara de
## brasas" darían "VD"), y esta franja existe para distinguirlos.
func _catalog_glyph(row: Dictionary, fallback_title: String) -> String:
	var glyph := String(row.get("glyph", ""))
	return glyph if not glyph.is_empty() else _glyph_for(fallback_title)


## La parte que distingue un nombre de tomo ("Tomo de Furia" -> "Furia"), para
## el glifo de respaldo de _glyph_for: con el prefijo común todos los glifos
## serían iguales. Se quita un solo prefijo, del más largo al más corto (ver
## TOME_NAME_PREFIXES).
func _tome_short_name(display_name: String) -> String:
	for prefix: String in TOME_NAME_PREFIXES:
		if display_name.begins_with(prefix):
			return display_name.substr(prefix.length())
	return display_name


## SOLO respaldo (ver _catalog_glyph): iniciales de un nombre de varias
## palabras, o sus dos primeras letras. Para una fila de catálogo que olvidó
## declarar su glifo; los nombres en español comparten demasiado la segunda
## palabra ("... de ...") como para que sea la fuente principal.
func _glyph_for(title: String) -> String:
	var words := title.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return title.substr(0, 2).to_upper()


## Crea (una vez) y rellena una franja inferior. `left` elige la esquina:
## abajo a la izquierda el equipo (armas, tomos y mascota), abajo a la
## derecha la bolsa. Devuelve el contenedor para que el llamador lo guarde.
func _rebuild_strip(box: HBoxContainer, entries: Array[Dictionary],
		left: bool) -> HBoxContainer:
	if box == null:
		box = HBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if left
				else Control.PRESET_BOTTOM_RIGHT)
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		box.grow_horizontal = Control.GROW_DIRECTION_END if left \
				else Control.GROW_DIRECTION_BEGIN
		if left:
			box.offset_left = 16.0
		else:
			box.offset_right = -16.0
		box.offset_bottom = -BOTTOM_STRIP_MARGIN
		box.offset_top = -BOTTOM_STRIP_MARGIN - BOTTOM_STRIP_HEIGHT
		box.add_theme_constant_override("separation", 6)
		# PASS y no IGNORE: las casillas necesitan recibir el mouse para sus
		# tooltips, y PASS igual deja pasar el clic al mundo 3D.
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(box)
	for child: Node in box.get_children():
		# Primero fuera del contenedor: queue_free() recién actúa al final del
		# cuadro, y las casillas viejas se acomodarían junto a las nuevas por un
		# cuadro, haciendo saltar la franja cada vez que cambia el equipo.
		box.remove_child(child)
		child.queue_free()
	var last_library := ""
	for entry: Dictionary in entries:
		# Un espacio entre grupos, según la biblioteca que declara cada entrada
		# y no según su color (un arma evolucionada es ámbar).
		var library := String(entry.get("library", ""))
		if not last_library.is_empty() and library != last_library:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(LOADOUT_GROUP_GAP, 0.0)
			box.add_child(spacer)
		last_library = library
		box.add_child(_make_loadout_slot(entry))
	return box


func _make_loadout_slot(entry: Dictionary) -> Control:
	var color: Color = entry.color
	var slot := PanelContainer.new()
	slot.custom_minimum_size = LOADOUT_SLOT_SIZE
	slot.tooltip_text = String(entry.tip)
	# PASS para que al pasar el mouse salga el tooltip (el nombre detrás del
	# glifo); IGNORE lo saca de la detección y el tooltip nunca aparece.
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := UiTheme.flat(Color(0.07, 0.075, 0.11, 0.9), UiTheme.RADIUS_SMALL)
	style.border_color = color
	style.set_border_width_all(2)
	UiTheme.add_glow(style, color, 6, 0.25)
	slot.add_theme_stylebox_override("panel", style)
	# PanelContainer es un Container: reajusta cada hijo DIRECTO a todo su
	# rectángulo en cada pasada de layout y borra anclas y márgenes. Un Control
	# simple absorbe ese ajuste y dentro de él las anclas funcionan: así la
	# esquina queda en la esquina y no sobre el glifo.
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(inner)
	var icon_path := _icon_path_for(entry)
	var on_placeholder := icon_path == ICON_PLACEHOLDER
	if not icon_path.is_empty():
		var texture := TextureRect.new()
		texture.texture = load(icon_path)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.add_child(texture)
	if icon_path.is_empty() or on_placeholder:
		# El glifo es el arte mientras no hay sprite: solo sobre una casilla
		# vacía, o sobre la imagen de reemplazo para que se siga leyendo.
		var glyph := Label.new()
		glyph.text = String(entry.glyph)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size",
				LOADOUT_PLACEHOLDER_GLYPH_SIZE if on_placeholder else LOADOUT_GLYPH_FONT_SIZE)
		glyph.add_theme_color_override("font_color", color.lightened(0.25))
		glyph.add_theme_color_override("font_outline_color", UiTheme.OUTLINE_DARK)
		glyph.add_theme_constant_override("outline_size", 4 if on_placeholder else 0)
		glyph.add_theme_font_override("font", UiTheme.spaced_font(1))
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.add_child(glyph)
	var corner_text := String(entry.corner)
	if not corner_text.is_empty():
		var corner := _make_corner_label(corner_text)
		inner.add_child(corner)
		# La fila de power-ups cambia el texto de este Label en vez de
		# reconstruir la casilla (ver _swap_powerup_corners).
		slot.set_meta(&"corner_label", corner)
	return slot


## La etiqueta de nivel, pilas o segundos en la esquina inferior derecha de
## una casilla. Se crea suelta y se coloca con su preset ANTES de tener padre,
## en los dos caminos que la crean (casilla nueva y esquina parchada), para
## que no puedan acomodarse distinto.
func _make_corner_label(text: String) -> Label:
	var corner := Label.new()
	corner.text = text
	corner.add_theme_font_size_override("font_size", LOADOUT_CORNER_FONT_SIZE)
	corner.add_theme_color_override("font_color", UiTheme.TEXT_BRIGHT)
	corner.add_theme_color_override("font_outline_color", UiTheme.OUTLINE_DARK)
	corner.add_theme_constant_override("outline_size", 4)
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	corner.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Preset MINSIZE: fija en la esquina inferior derecha a su tamaño de texto,
	# 3 px hacia adentro del borde.
	corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_MODE_MINSIZE, 3)
	return corner


## La textura que dibuja una casilla, en este orden: el `icon` propio de la
## fila, luego la convención por id (assets/icons/<biblioteca>/<id>.png) y
## luego el reemplazo común. ResourceLoader.exists con el tipo es la
## comprobación que también sirve en una build exportada, donde el PNG va
## empacado como .ctex y FileAccess sobre el .png responde false.
func _icon_path_for(entry: Dictionary) -> String:
	var declared := String(entry.get("icon", ""))
	if not declared.is_empty() and ResourceLoader.exists(declared, "Texture2D"):
		return declared
	var library := String(entry.get("library", ""))
	var entry_id := String(entry.get("entry_id", ""))
	if not library.is_empty() and not entry_id.is_empty():
		var path := "%s%s/%s.png" % [ICON_ROOT, library, entry_id]
		if ResourceLoader.exists(path, "Texture2D"):
			return path
	if ResourceLoader.exists(ICON_PLACEHOLDER, "Texture2D"):
		return ICON_PLACEHOLDER
	return ""


func _on_health_damaged(_amount: float, current: float) -> void:
	_refresh_hp(current, _health.max_hp)
	Juice.player_hurt()


func _on_health_died() -> void:
	_refresh_hp(0.0, _health.max_hp)


func _refresh_hp(current: float, max_hp: float) -> void:
	# Repetir los números ya dibujados, con la barra quieta en ellos (misma
	# escala, valor exacto y sin animación en curso), no hace nada: la
	# animación iría de `current` a `current`, y el texto, el color y el
	# latido dependen solo de estos dos números. El robo de vida manda
	# justo eso en cada golpe con la vida llena. Si falta cualquier condición
	# corre el camino normal, así una animación cortada a medias se reinicia.
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
	_hp_label.text = "%d / %d" % [ceili(current), roundi(max_hp)]
	var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	UiTheme.recolor_fill(_hp_fill,
			HP_LOW_COLOR.lerp(HP_FULL_COLOR, clampf(ratio / LOW_HP_RATIO, 0.0, 1.0)))
	_update_low_hp_pulse(current > 0.0 and ratio < low_hp_pulse_ratio)


## Suavizado común (BAR_TWEEN_TIME) hacia el nuevo valor de una barra; mata el
## anterior primero para que los golpes seguidos converjan en vez de apilarse.
func _tween_bar_value(bar: ProgressBar, target: float, previous: Tween) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	tween.tween_property(bar, "value", target, BAR_TWEEN_TIME) \
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
	_hp_pulse_tween.tween_property(_hp_bar, "modulate:a", 0.6, low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.parallel().tween_property(_hp_bar, "scale",
			Vector2(1.03, 1.08), low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.chain().tween_property(_hp_bar, "modulate:a", 1.0, low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.parallel().tween_property(_hp_bar, "scale", Vector2.ONE,
			low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_xp_changed(current_xp: int, xp_to_next: int) -> void:
	# Un umbral nuevo significa que se subió de nivel: salta a la nueva escala.
	if not is_equal_approx(_xp_bar.max_value, float(xp_to_next)):
		_xp_bar.max_value = xp_to_next
		_xp_bar.value = current_xp
	else:
		_xp_value_tween = _tween_bar_value(_xp_bar, float(current_xp), _xp_value_tween)


func _on_leveled_up(new_level: int) -> void:
	_level_label.text = UiTheme.LEVEL_ABBREV % new_level
	UiTheme.pop(_level_label, 1.3, 0.3)


func _on_kills_changed(kills: int) -> void:
	_kills_label.text = "Bajas: %d" % kills
	if kills <= _last_kills:
		# Contador reiniciado (partida nueva), no una baja: se limpia la racha.
		_last_kills = kills
		_streak_kill_times.clear()
		_streak_tier = -1
		return
	_last_kills = kills
	_register_streak_kill()


func _register_streak_kill() -> void:
	var now: float = RunState.run_time
	while not _streak_kill_times.is_empty() and now - _streak_kill_times[0] > STREAK_WINDOW:
		_streak_kill_times.pop_front()
	if _streak_kill_times.is_empty():
		_streak_tier = -1  # la racha se cortó: cada nivel puede volver a dispararse
	_streak_kill_times.append(now)
	var in_window := _streak_kill_times.size()
	var tier := -1
	for i in STREAK_KILLS.size():
		if in_window >= STREAK_KILLS[i]:
			tier = i
	if tier > _streak_tier:
		_streak_tier = tier
		_pop_streak(STREAK_WORDS[tier], tier)


## Texto de golpe: entra grande e inclinado, se asienta, se mantiene y se
## desvanece. El color sube por nivel para que las rachas grandes se lean más
## calientes.
func _pop_streak(word: String, tier: int) -> void:
	Sfx.play(&"streak")
	_streak_label.text = word
	_streak_label.add_theme_color_override("font_color", STREAK_COLORS[tier])
	_streak_label.reset_size()
	_streak_label.pivot_offset = _streak_label.size * 0.5
	_streak_label.visible = true
	_streak_label.modulate.a = 1.0
	_streak_label.scale = Vector2(2.3, 2.3)
	_streak_label.rotation_degrees = -5.0
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	_streak_tween = create_tween()
	_streak_tween.tween_property(_streak_label, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.parallel().tween_property(_streak_label, "rotation_degrees", 0.0, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.tween_interval(0.55)
	_streak_tween.tween_property(_streak_label, "modulate:a", 0.0, 0.3)
	_streak_tween.tween_callback(_streak_label.hide)


## Dificultad de la partida, arriba al centro (altares demoníacos, Tomo del
## Peligro, ruleta); oculta mientras es cero.
func _on_difficulty_changed(bonus: float) -> void:
	_curse_label.visible = bonus > 0.001
	_curse_label.text = "Dificultad +%d%%" % roundi(bonus * 100.0)


## Contadores de depuración arriba a la derecha, creados en código para que la
## escena del juego no los lleve (ver show_perf_probe).
func _build_perf_probe() -> void:
	_probe_label = Label.new()
	_probe_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_probe_label.offset_left = -560.0
	_probe_label.offset_right = -12.0
	_probe_label.offset_top = 46.0
	_probe_label.offset_bottom = 120.0
	_probe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_probe_label.add_theme_font_size_override("font_size", 12)
	_probe_label.modulate = Color(1.0, 1.0, 1.0, 0.85)
	add_child(_probe_label)


func _probe_text() -> String:
	var tree := get_tree()
	return "FPS %d | enemies %d | gems %d | shots %d | bolts %d\npools (created/parked): %s" % [
			Engine.get_frames_per_second(),
			tree.get_node_count_in_group(&"enemies"),
			tree.get_node_count_in_group(&"xp_gems"),
			tree.get_node_count_in_group(&"player_shots"),
			tree.get_node_count_in_group(&"enemy_bolts"),
			Pools.stats_line()]


## Etiqueta de etapa abajo a la derecha, sobre los puntos, enviada por el grupo
## "hud" (RunRoot y RunSystems): "E%d" para la etapa y " · V%d" desde que el
## grupo dio la vuelta a la lista de mapas. En pantalla ambos empiezan en 1;
## RunState los guarda desde 0. GLOSARIO regla 6: Nivel/Nv es el jugador,
## Etapa/E el mapa, Vuelta/V la vuelta y Rango una reliquia.
func show_stage_tag(stage_index: int, lap: int) -> void:
	_stage_label.visible = true
	_stage_label.text = "E%d" % (stage_index + 1) if lap <= 0 \
			else "E%d · V%d" % [stage_index + 1, lap + 1]


## Relevo de la flecha de objetivo (grupo "boss_ui"): WorldDirector apunta la
## flecha al portal de salida cuando la etapa abre uno.
func track_objective(node: Node3D) -> void:
	var arrow := get_node_or_null("BossArrow")
	if arrow != null and arrow.has_method("track_objective"):
		arrow.call("track_objective", node)


## Lo llama por el grupo "boss_ui" un jefe al entrar a la arena. Si ya se
## sigue uno, la barra pasa al más nuevo (los jefes son secuenciales; con dos
## vivos se ve el último).
func track_boss(boss: Node3D, title: String) -> void:
	_untrack_boss()
	var boss_health := Health.find_in(boss)
	if boss_health == null:
		return
	_tracked_boss = boss
	_boss_health = boss_health
	boss_health.damaged.connect(_on_boss_damaged)
	boss_health.hp_changed.connect(_on_boss_hp_changed)
	boss_health.died.connect(_on_boss_health_died)
	boss.tree_exited.connect(_on_boss_gone)
	_boss_name_label.text = title
	_boss_bar.visible = true
	_on_boss_hp_changed(boss_health.current_hp, boss_health.max_hp)


## Por los grupos "boss_ui" y "hud" (avisos de jefe, altares, eventos): un
## cartel centrado breve que se desvanece solo.
func announce(message: String) -> void:
	_reset_announce_style()
	_announce_label.text = message
	_announce_label.visible = true
	_announce_label.modulate.a = 0.0
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_label, "modulate:a", 1.0, 0.3)
	_announce_tween.tween_interval(2.4)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, 0.6)
	_announce_tween.tween_callback(_announce_label.hide)


## Por el grupo "hud" cuando un jugador recibe botín (cofres, ruleta, Tomo del
## Azar, power-ups). Pone en cola una tarjeta por premio; `player_index` solo
## se muestra como etiqueta si el grupo tiene más de un jugador.
func show_loot(title: String, description: String, color: Color,
		player_index: int = 0) -> void:
	_loot_queue.append({"title": title, "description": description,
			"color": color, "player_index": player_index})
	if not _loot_showing:
		_show_next_loot()


func _show_next_loot() -> void:
	if _loot_queue.is_empty():
		_loot_showing = false
		if _loot_box != null:
			_loot_box.visible = false
		return
	_loot_showing = true
	var entry: Dictionary = _loot_queue.pop_front()
	_build_loot_toast()
	var color: Color = entry.color
	var title := String(entry.title)
	if Coop.player_count > 1:
		title = "%s  %s" % [LOOT_PLAYER_TAG % (int(entry.player_index) + 1), title]
	_loot_title.text = title
	_loot_title.add_theme_color_override("font_color", color.lightened(0.25))
	_loot_desc.text = String(entry.description)
	var style := UiTheme.flat(Color(0.07, 0.075, 0.11, 0.92), UiTheme.RADIUS_SMALL)
	style.border_color = color
	style.set_border_width_all(2)
	UiTheme.add_glow(style, color, 10, 0.3)
	_loot_box.add_theme_stylebox_override("panel", style)
	_loot_box.visible = true
	_loot_box.modulate.a = 0.0
	_loot_box.offset_bottom = LOOT_TOAST_BOTTOM + LOOT_TOAST_SLIDE
	_loot_box.offset_top = _loot_box.offset_bottom - 64.0
	if _loot_tween != null and _loot_tween.is_valid():
		_loot_tween.kill()
	_loot_tween = create_tween()
	_loot_tween.set_parallel(true)
	_loot_tween.tween_property(_loot_box, "modulate:a", 1.0, LOOT_TOAST_FADE)
	_loot_tween.tween_property(_loot_box, "offset_bottom", LOOT_TOAST_BOTTOM,
			LOOT_TOAST_FADE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_loot_tween.tween_property(_loot_box, "offset_top", LOOT_TOAST_BOTTOM - 64.0,
			LOOT_TOAST_FADE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_loot_tween.chain().tween_interval(LOOT_TOAST_TIME)
	_loot_tween.chain().tween_property(_loot_box, "modulate:a", 0.0, LOOT_TOAST_FADE)
	_loot_tween.chain().tween_callback(_show_next_loot)


## Se crea una vez, con el primer premio de la partida: la mayoría de las
## partidas muestra uno, y no vale la pena armarlo antes.
func _build_loot_toast() -> void:
	if _loot_box != null:
		return
	_loot_box = PanelContainer.new()
	_loot_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_loot_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_loot_box.custom_minimum_size = Vector2(LOOT_TOAST_WIDTH, 0.0)
	_loot_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_loot_box.offset_left = -LOOT_TOAST_WIDTH * 0.5
	_loot_box.offset_right = LOOT_TOAST_WIDTH * 0.5
	_loot_box.anchor_left = 0.5
	_loot_box.anchor_right = 0.5
	# IGNORE y no PASS: esta tarjeta tapa la zona de juego tres segundos y
	# nunca debe comerse un clic destinado al mundo.
	_loot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loot_box.visible = false
	add_child(_loot_box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loot_box.add_child(column)
	_loot_title = Label.new()
	_loot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_title.add_theme_font_size_override("font_size", LOOT_TITLE_FONT_SIZE)
	_loot_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_loot_title)
	_loot_desc = Label.new()
	_loot_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loot_desc.add_theme_font_size_override("font_size", LOOT_DESC_FONT_SIZE)
	_loot_desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_loot_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_loot_desc)


## Hermano mayor de announce() para momentos de recompensa (evoluciones de
## arma, etapa nueva, supervivencia): dorado, con un golpe de escala y más
## tiempo en pantalla.
func announce_major(message: String) -> void:
	_reset_announce_style()
	_announce_label.text = message
	_announce_label.add_theme_color_override("font_color", UiTheme.ACCENT_AMBER)
	_announce_label.visible = true
	_announce_label.modulate.a = 0.0
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_label, "modulate:a", 1.0, 0.15)
	_announce_tween.tween_interval(3.2)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, 0.6)
	_announce_tween.tween_callback(func() -> void:
		_announce_label.hide()
		# Devuelve el color normal del cartel para el próximo anuncio simple.
		_reset_announce_style())
	UiTheme.pop(_announce_label, 1.35, 0.4)


## Limpia lo que dejó el cartel anterior (el ámbar de announce_major, un golpe
## de escala a medias). Cada cartel parte del aspecto de la escena: sin esto,
## un announce() dentro de la ventana de ~4 s de announce_major mata la
## animación que iba a limpiar, y todos los carteles siguientes de la partida
## quedan ámbar y un poco agrandados.
func _reset_announce_style() -> void:
	UiTheme.kill_meta_tween(_announce_label, &"ui_pop_tween")
	_announce_label.remove_theme_color_override("font_color")
	_announce_label.scale = Vector2.ONE


func _on_boss_damaged(_amount: float, current: float) -> void:
	_boss_value_tween = _tween_bar_value(_boss_bar, current, _boss_value_tween)


func _on_boss_hp_changed(current: float, max_hp: float) -> void:
	if not is_equal_approx(_boss_bar.max_value, max_hp):
		_boss_bar.max_value = max_hp
		_boss_bar.value = current
	else:
		_boss_value_tween = _tween_bar_value(_boss_bar, current, _boss_value_tween)


func _on_boss_health_died() -> void:
	_boss_bar.visible = false


## Respaldo para un jefe que sale del árbol sin morir (desmontaje de escena).
func _on_boss_gone() -> void:
	_untrack_boss()
	_boss_bar.visible = false


func _untrack_boss() -> void:
	if _boss_health != null and is_instance_valid(_boss_health):
		_boss_health.damaged.disconnect(_on_boss_damaged)
		_boss_health.hp_changed.disconnect(_on_boss_hp_changed)
		_boss_health.died.disconnect(_on_boss_health_died)
	if _tracked_boss != null and is_instance_valid(_tracked_boss):
		_tracked_boss.tree_exited.disconnect(_on_boss_gone)
	_boss_health = null
	_tracked_boss = null


## Estilos de UiTheme: barras en capas (fondo, relleno, línea de brillo y
## borde de avance), chips para nivel, bajas y puntos, números del reloj
## espaciados y la barra ámbar del jefe con marcas de cuarto bajo su nombre
## espaciado. Primero el contraste sobre el caos 3D: todo lleva fondo oscuro
## y contorno.
func _apply_styles() -> void:
	_hp_fill = UiTheme.style_bar(_hp_bar, HP_FULL_COLOR, 8)

	# La franja de XP sigue de borde a borde y cuadrada, pero gana la línea de
	# brillo y un borde de avance claro para leer el progreso de un vistazo.
	var xp_bg := UiTheme.flat(Color(0.04, 0.045, 0.07, 0.85), 0)
	xp_bg.border_width_bottom = 1
	xp_bg.border_color = Color(0.0, 0.0, 0.0, 0.6)
	_xp_bar.add_theme_stylebox_override("background", xp_bg)
	_xp_bar.add_theme_stylebox_override("fill", UiTheme.bar_fill(XP_COLOR, 0))

	var boss_fill := UiTheme.style_bar(_boss_bar, BOSS_BAR_COLOR, 7)
	UiTheme.recolor_fill(boss_fill, BOSS_BAR_COLOR)
	var boss_bg := _boss_bar.get_theme_stylebox("background") as StyleBoxFlat
	boss_bg.border_color = Color(0.35, 0.22, 0.06, 0.9)
	UiTheme.add_glow(boss_bg, BOSS_BAR_COLOR, 6, 0.25)
	_build_boss_ticks()
	_boss_name_label.add_theme_font_override("font", UiTheme.spaced_font(3))

	UiTheme.style_badge(_level_label, UiTheme.TEXT_BRIGHT)
	UiTheme.style_badge(_kills_label, UiTheme.TEXT_BRIGHT)
	UiTheme.style_badge(_points_label, UiTheme.ACCENT_AMBER)
	UiTheme.style_badge(_timer_label, UiTheme.TEXT_BRIGHT)
	_timer_label.add_theme_font_override("font", UiTheme.spaced_font(4))
	_streak_label.add_theme_font_override("font", UiTheme.spaced_font(3))
	_announce_label.add_theme_font_override("font", UiTheme.spaced_font(3))


## Marcas de cuarto sobre la barra del jefe: líneas oscuras al 25/50/75 % para
## que los umbrales de fase se lean como una vida por segmentos.
func _build_boss_ticks() -> void:
	for quarter in range(1, 4):
		var tick := ColorRect.new()
		tick.color = Color(0.0, 0.0, 0.0, 0.5)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.anchor_left = 0.25 * quarter
		tick.anchor_right = 0.25 * quarter
		tick.anchor_top = 0.0
		tick.anchor_bottom = 1.0
		tick.offset_left = -1.0
		tick.offset_right = 1.0
		tick.offset_top = 4.0
		tick.offset_bottom = -4.0
		_boss_bar.add_child(tick)
		_boss_bar.move_child(tick, 0)  # bajo el Label del nombre
