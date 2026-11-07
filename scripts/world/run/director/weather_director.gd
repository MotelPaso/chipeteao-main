class_name WeatherDirector
extends Node
## Clima de la partida: lunas, lluvias y desastres en UN solo canal
## (`active_weather` guarda como mucho una fila, así nunca se solapan).
## Es el nodo RunSystems.tscn > WorldDirector > Weather: sus números se
## editan en el Inspector de ese nodo, y el aspecto y el texto de cada
## clima en su fila de WEATHER_CATALOG.
## No tiene _physics_process propio: el WorldDirector llama a tick() y a
## maybe_roll() en su cadencia de eventos, y ese orden es parte del sorteo
## (el RNG de la partida es uno solo).
## En el código esto es WEATHER, nunca "event": EVENT_LIBRARY es la tabla
## de eventos de POI. Para el jugador la palabra sigue siendo «evento».

## Climas, una fila por clima: edita aquí el aviso, el tinte del cielo y
## los colores de cada uno. Campos:
##   id/group:      identificador y grupo: moon | rain | disaster.
##   display_name:  nombre que muestra el HUD.
##   weight:        peso del sorteo DENTRO de su grupo.
##   duration:      segundos, antes de weather_duration_overrides y, en
##                  lunas y lluvias, de RunState.sky_duration_multiplier
##                  (los pactos no alargan los desastres).
##   announce:      aviso en el HUD al empezar; %s = dato que pone el
##                  clima (el tsunami: de dónde viene la ola).
##   sun_color, sun_energy, ambient_color: tinte del cielo; sun_energy
##                  multiplica la energía original del sol. Sin sun_color
##                  el cielo no cambia.
##   fx_color:      color de los avisos en el suelo y las partículas.
##   altar_ok:      el altar de evento puede invocarlo.
##   start/tick/stop: métodos que se llaman con call(); tick y stop pueden
##                  ir vacíos. catalog_lint.gd revisa que existan.
##   follow_up:     la fila que empieza en cuanto esta termina, sin pausa
##                  (las lunas malas -> luna llena; las dos lluvias ->
##                  lluvia dorada, el premio por aguantar la mala).
##   follow_up_only: nunca sale por sorteo, solo como follow_up.
const WEATHER_CATALOG: Array[Dictionary] = [
	{
		"id": "blood_moon", "group": "moon", "display_name": "Luna de sangre",
		"weight": 1.0, "duration": 45.0,
		"announce": "LUNA DE SANGRE — ¡la horda enloquece!",
		"sun_color": Color(1.0, 0.25, 0.2), "sun_energy": 0.9,
		"ambient_color": Color(0.5, 0.1, 0.1), "altar_ok": true,
		"start": &"_weather_start_dark_moon", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "eclipse", "group": "moon", "display_name": "Eclipse",
		"weight": 1.0, "duration": 45.0,
		"announce": "ECLIPSE — las sombras entran por todos lados",
		"sun_color": Color(0.35, 0.3, 0.5), "sun_energy": 0.35,
		"ambient_color": Color(0.12, 0.1, 0.2), "altar_ok": true,
		"start": &"_weather_start_dark_moon", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "full_moon", "group": "moon", "display_name": "Luna llena",
		"weight": 1.0, "duration": 40.0,
		"announce": "LUNA LLENA — la fortuna y la sabiduría te sonríen",
		"sun_color": Color(0.85, 0.9, 1.0), "sun_energy": 1.3,
		"ambient_color": Color(0.6, 0.65, 0.9), "altar_ok": false,
		"start": &"_weather_start_full_moon", "tick": &"", "stop": &"",
		"follow_up_only": true,
	},
	{
		"id": "enemy_rain", "group": "rain", "display_name": "Lluvia de enemigos",
		"weight": 1.0, "duration": 35.0,
		"announce": "LLUVIA DE ENEMIGOS — ¡caen del cielo!",
		"sun_color": Color(0.6, 0.8, 1.0), "sun_energy": 0.8,
		"ambient_color": Color(0.35, 0.45, 0.6), "fx_color": Color(0.6, 0.85, 1.0),
		"altar_ok": true,
		"start": &"_weather_start_enemy_rain", "tick": &"_weather_tick_enemy_rain",
		"stop": &"", "follow_up": "golden_rain",
	},
	{
		# Sin stop: los charcos sobreviven a la lluvia a propósito; cada uno
		# caduca solo y el cambio de etapa recoge los que queden.
		"id": "radioactive_rain", "group": "rain", "display_name": "Lluvia radiactiva",
		"weight": 1.0, "duration": 40.0,
		"announce": "LLUVIA RADIACTIVA — el suelo se vuelve ácido",
		"sun_color": Color(0.5, 1.0, 0.4), "sun_energy": 0.85,
		"ambient_color": Color(0.2, 0.4, 0.15), "altar_ok": true,
		"start": &"_weather_start_radioactive_rain",
		"tick": &"_weather_tick_radioactive_rain", "stop": &"",
		"follow_up": "golden_rain",
	},
	{
		"id": "golden_rain", "group": "rain", "display_name": "Lluvia dorada",
		"weight": 1.0, "duration": 40.0,
		"announce": "LLUVIA DORADA — todo brilla y todo vale la mitad",
		"sun_color": Color(1.0, 0.85, 0.4), "sun_energy": 1.2,
		"ambient_color": Color(0.6, 0.5, 0.2), "altar_ok": false,
		"start": &"_weather_start_golden_rain", "tick": &"",
		"stop": &"_weather_stop_golden_rain", "follow_up_only": true,
	},
	{
		# Una sola ola: su tick la vierte en tres segundos y termina el
		# desastre él mismo. Puede volver a salir más tarde.
		"id": "enemy_tsunami", "group": "disaster", "display_name": "Tsunami",
		"weight": 1.0, "duration": 3.0,
		"announce": "¡TSUNAMI DE ENEMIGOS! %s", "altar_ok": true,
		"start": &"_weather_start_tsunami", "tick": &"_weather_tick_tsunami",
		"stop": &"",
	},
	{
		"id": "earthquake", "group": "disaster", "display_name": "Terremoto",
		"weight": 1.0, "duration": 25.0,
		"announce": "¡TERREMOTO! El suelo no se queda quieto",
		"fx_color": Color(0.6, 0.55, 0.45), "altar_ok": true,
		"start": &"_weather_start_earthquake", "tick": &"_weather_tick_earthquake",
		"stop": &"_weather_stop_earthquake",
	},
	{
		# fx_color es el aviso en el suelo; impact_color, la explosión;
		# scorch_color, la marca que deja.
		"id": "meteor_shower", "group": "disaster", "display_name": "Lluvia de meteoritos",
		"weight": 1.0, "duration": 30.0,
		"announce": "¡LLUVIA DE METEORITOS! Sal de los círculos",
		"sun_color": Color(1.0, 0.6, 0.35), "sun_energy": 0.95,
		"ambient_color": Color(0.4, 0.25, 0.15), "fx_color": Color(1.0, 0.55, 0.2),
		"impact_color": Color(1.0, 0.6, 0.25), "scorch_color": Color(0.35, 0.2, 0.15),
		"altar_ok": true,
		"start": &"_weather_start_meteors", "tick": &"_weather_tick_meteors",
		"stop": &"",
	},
]

## Grupos que un pacto demoníaco puede alargar (RunState.sky_duration_multiplier).
const STRETCHABLE_GROUPS: Array[String] = ["moon", "rain"]
## Tope de charcos de ácido vivos y distancia mínima entre ellos (metros).
## Pasado el tope se saltan; subir el tope no es la solución.
const MAX_LIVE_ACID_POOLS: int = 24
const ACID_POOL_SPACING: float = 3.0
## Tope de avisos de meteorito vivos, por lo mismo (el pool de discos es
## de 32 y lo usa todo el juego).
const MAX_LIVE_TELEGRAPHS: int = 16
## Enemigos que el tsunami vierte por frame de física: cuarenta en un solo
## frame dan un tirón visible.
const TSUNAMI_PER_FRAME: int = 6
## Etiqueta de las dos ventajas de la luna llena: una segunda luna dentro
## de la primera las reemplaza en vez de sumarlas (solo clear_timed_boons
## quita por etiqueta).
const FULL_MOON_TAG: String = "full_moon"

@export_group("Probabilidad y pausa")
## Probabilidad (0-1) de desastre en cada evento; se tira antes que la
## lluvia y la luna. Los pactos demoníacos la suben.
@export var disaster_chance: float = 0.08
## Probabilidad (0-1) de lluvia en cada evento; se tira después del desastre.
@export var rain_chance: float = 0.12
## Probabilidad (0-1) de luna en cada evento; se tira la última.
@export var sky_event_chance: float = 0.18
## Probabilidad extra de luna por cada altar demoníaco usado.
@export var sky_event_chance_per_demonic: float = 0.08
## Segundos sin clima tras terminar uno; vale para lunas, lluvias y desastres.
@export var sky_event_min_gap: float = 150.0
## Duraciones (segundos) que reemplazan las de WEATHER_CATALOG, por id de
## clima. Vale para todas las arenas: este nodo es uno por partida.
@export var weather_duration_overrides: Dictionary[String, float] = {}

@export_group("Luna llena")
## XP extra (porcentaje) que da la luna llena a todo el grupo.
@export var full_moon_xp_bonus: float = 50.0
## Suerte extra que da la luna llena a todo el grupo.
@export var full_moon_luck_bonus: float = 30.0

@export_group("Lluvia de enemigos")
## Segundos entre tandas.
@export var enemy_rain_interval: float = 1.5
## Enemigos mínimos y máximos por tanda.
@export var enemy_rain_min_drops: int = 3
@export var enemy_rain_max_drops: int = 6
## Distancia mínima y máxima (metros) de cada caída al jugador.
@export var enemy_rain_min_distance: float = 12.0
@export var enemy_rain_max_distance: float = 25.0
## Radio (metros) del aviso en el suelo de cada caída.
@export var enemy_rain_telegraph_radius: float = 1.4
## Segundos que dura ese aviso.
@export var enemy_rain_telegraph_time: float = 1.0

@export_group("Lluvia radiactiva")
## Segundos entre charcos de ácido.
@export var acid_pool_interval: float = 2.0
## Radio (metros) de cada charco.
@export var acid_pool_radius: float = 2.0
## Segundos que dura cada charco.
@export var acid_pool_lifetime: float = 6.0
## Distancia mínima y máxima (metros) de un charco al jugador.
@export var acid_pool_min_distance: float = 2.0
@export var acid_pool_spawn_range: float = 20.0
## Daño por segundo del ácido a un jugador dentro de un charco.
@export var acid_pool_damage_per_second: float = 4.0

@export_group("Lluvia dorada")
## Multiplicador de puntos mientras cae.
@export var golden_points_multiplier: float = 2.0
## Factor de precio mientras cae (0.5 = mitad de precio).
@export var golden_price_discount: float = 0.5

@export_group("Tsunami")
## Enemigos de la ola al empezar la etapa.
@export var tsunami_base: int = 40
## Enemigos extra de la ola por minuto de etapa.
@export var tsunami_per_minute: int = 4
## Distancia mínima y máxima (metros) de la ola al jugador.
@export var tsunami_arc_min: float = 40.0
@export var tsunami_arc_max: float = 60.0
## Medio ancho del arco del que viene la ola (radianes; 0.52 son unos 30
## grados a cada lado).
@export var tsunami_arc_spread: float = 0.52

@export_group("Terremoto")
## Segundos entre sacudidas de cámara.
@export var earthquake_shake_interval: float = 0.5
## Fuerza de cada sacudida de cámara.
@export var earthquake_shake_strength: float = 0.25
## Cuánto se desplaza el HUD (píxeles).
@export var earthquake_hud_amplitude: float = 14.0
## Vibraciones por segundo del HUD.
@export var earthquake_hud_hz: float = 20.0
## Segundos entre nubes de polvo sobre cada jugador.
@export var earthquake_dust_interval: float = 3.0

@export_group("Meteoritos")
## Segundos entre meteoritos.
@export var meteor_interval: float = 0.8
## Distancia mínima y máxima (metros) de un meteorito al jugador.
@export var meteor_min_distance: float = 3.0
@export var meteor_range: float = 20.0
## Radio (metros) de cada impacto.
@export var meteor_radius: float = 3.0
## Segundos de aviso en el suelo antes del impacto.
@export var meteor_telegraph: float = 1.2
## Daño de cada impacto a los jugadores.
@export var meteor_damage: float = 40.0
## Cuánto crece ese daño por minuto de partida (0.05 = +5 % por minuto).
@export var meteor_damage_per_minute: float = 0.05
## Multiplicador del daño del impacto a los enemigos.
@export var meteor_enemy_scale: float = 3.0
## Fuerza de la sacudida de cámara de cada impacto.
@export var meteor_impact_shake: float = 0.35
## Tamaño de la marca del impacto, relativo a meteor_radius.
@export var meteor_scorch_scale: float = 0.8
## Segundos que dura la marca del impacto.
@export var meteor_scorch_time: float = 0.5

## El clima activo, o vacío: {id, group, time_left}. El HUD, el altar de
## evento y el probe lo leen a través del WorldDirector.
var active_weather: Dictionary = {}
## Reparto de la etapa (máscara y muestreos); lo pone el WorldDirector.
var layout: StageLayout = null

## Datos propios del clima activo (start/tick/stop); se vacía al empezar
## uno, así ningún clima lee lo que dejó el anterior.
var _weather_state: Dictionary = {}
var _sky_gap_left: float = 0.0
var _sun: DirectionalLight3D = null
var _sun_color: Color = Color.WHITE
var _sun_energy: float = 1.0
var _environment: Environment = null
var _ambient_color: Color = Color.WHITE
var _ambient_energy: float = 1.0
## El ÚNICO tween que escribe el sol y el ambiente: dos a la vez escriben
## las mismas propiedades cada frame y gana el más largo.
var _sky_tween: Tween = null


## La partida puede terminar en medio de un clima: se detiene y el cielo
## vuelve en seco, para que el tinte no pase a la partida siguiente. Va
## aquí y no en el WorldDirector porque los hijos salen del árbol antes que
## el padre, y el stop() de un clima necesita el árbol.
func _exit_tree() -> void:
	end_stage()


## La fila de WEATHER_CATALOG con ese id, o vacío.
static func weather_row(id: String) -> Dictionary:
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.id) == id:
			return row
	return {}


## Inicio de etapa: olvida las luces de la arena anterior (si no, la etapa
## 2 teñiría el sol ya liberado de la etapa 1 y ningún cielo se vería) y
## vacía el canal, sin stop(): on_stage_ended ya detuvo el clima.
func begin_stage(stage_layout: StageLayout) -> void:
	layout = stage_layout
	_kill_sky_tween()
	_sun = null
	_environment = null
	_sun_color = Color.WHITE
	_sun_energy = 1.0
	_ambient_color = Color.WHITE
	_ambient_energy = 1.0
	active_weather = {}
	_weather_state = {}
	_sky_gap_left = 0.0


## Fin de etapa o de partida: detiene el clima sin encadenar el siguiente
## y devuelve el cielo al instante, antes de que la arena se libere.
func end_stage() -> void:
	stop_weather()
	_snap_sky_back()


## Detiene el clima activo sin encadenar el siguiente ni devolver el cielo
## (fin de partida: la pantalla final deja la arena tal cual).
func stop_weather() -> void:
	_stop_weather(false)


## Un frame de física del canal: descuenta la pausa y el clima activo.
func tick(delta: float) -> void:
	_sky_gap_left = maxf(_sky_gap_left - delta, 0.0)
	if active_weather.is_empty():
		return
	var row := weather_row(String(active_weather.id))
	var tick_method: StringName = row.get("tick", &"")
	if not tick_method.is_empty():
		call(tick_method, delta)
	# El tick puede terminar el clima él mismo (el tsunami, cuando vierte
	# su ola); entonces no queda nada que descontar.
	if active_weather.is_empty():
		return
	active_weather.time_left = float(active_weather.time_left) - delta
	if float(active_weather.time_left) > 0.0:
		return
	_stop_weather(true)


## La tirada de clima de cada evento: primero el grupo más raro, para que
## las lluvias y lunas no tapen a los desastres.
func maybe_roll() -> void:
	if not active_weather.is_empty() or _sky_gap_left > 0.0:
		return
	# Con probabilidad 0 un grupo NO tira dado: el RNG de la partida es uno
	# solo y un dado de más cambia todo lo que se sortea después.
	var disaster_odds := disaster_chance + RunState.disaster_chance_bonus
	if disaster_odds > 0.0 and randf() < disaster_odds:
		_start_weather(_roll_group("disaster"))
		return
	var rain_odds := rain_chance + RunState.event_chance_bonus
	if rain_odds > 0.0 and randf() < rain_odds:
		_start_weather(_roll_group("rain"))
		return
	# Los pactos demoníacos venden probabilidad de luna, además del extra
	# que suma cada altar demoníaco usado.
	var chance := sky_event_chance + RunState.event_chance_bonus \
			+ sky_event_chance_per_demonic * float(RunState.demonic_uses)
	if randf() >= chance:
		return
	_start_weather(_roll_group("moon"))


## FUERZA un clima (el probe, BONK_WEATHER_NOW, el altar de evento): detiene
## el que haya y empieza aunque no haya pasado la pausa. Si no hiciera
## nada, el altar parecería roto y fallaría la puerta CIELO_TRAS_AVANCE de
## verificar.sh.
func start_sky_event(kind: String) -> void:
	_start_weather(kind, true)


## La tirada del altar de evento: cualquier fila con altar_ok.
func random_altar_weather() -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if bool(row.get("altar_ok", true)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if not bool(row.get("altar_ok", true)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


## Un charco de ácido (EnemyBase lo pide al morir durante la lluvia
## radiactiva), si cabe bajo el tope y respeta la distancia. Si no, se
## salta en silencio: un aviso aquí haría fallar un soak por funcionar bien.
func spawn_acid_pool(at: Vector3) -> void:
	if not is_weather_active("radioactive_rain"):
		return
	var live := get_tree().get_nodes_in_group(&"acid_pools")
	if live.size() >= MAX_LIVE_ACID_POOLS:
		return
	var spacing_sq := ACID_POOL_SPACING * ACID_POOL_SPACING
	for node: Node in live:
		var pool := node as Node3D
		if pool != null and pool.global_position.distance_squared_to(at) < spacing_sq:
			return
	var fresh := Pools.acquire_scene(Pools.ACID_POOL_SCENE) as AcidPool
	if fresh == null:
		return
	fresh.play(at, acid_pool_radius, acid_pool_lifetime, acid_pool_damage_per_second)


## Verdadero mientras `id` sea el clima activo.
func is_weather_active(id: String) -> bool:
	return not active_weather.is_empty() and String(active_weather.id) == id


## --- canal ------------------------------------------------------------------

## Segundos que dura esta fila, con el reemplazo del Inspector y, solo en
## lunas y lluvias, el multiplicador de los pactos.
func _weather_duration(row: Dictionary) -> float:
	var seconds := float(weather_duration_overrides.get(String(row.id), row.duration))
	if STRETCHABLE_GROUPS.has(String(row.group)):
		seconds *= RunState.sky_duration_multiplier
	return seconds


## Un id al azar del grupo, por peso, sin las filas follow_up_only.
func _roll_group(group: String) -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) == group and not bool(row.get("follow_up_only", false)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) != group or bool(row.get("follow_up_only", false)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


func _start_weather(id: String, forced: bool = false) -> void:
	if id.is_empty():
		return
	var row := weather_row(id)
	if row.is_empty():
		push_warning("WorldDirector: unknown weather '%s'" % id)
		return
	if not active_weather.is_empty():
		if not forced:
			return
		# Forzado: el clima activo se detiene bien, con su stop(), que es lo
		# que suelta el tinte, la fuente de puntos y el desplazamiento del HUD.
		_stop_weather(false)
	_cache_lights()
	_weather_state = {}
	var seconds := _weather_duration(row)
	active_weather = {"id": id, "group": String(row.group), "time_left": seconds}
	call(row.start)
	_present(row)
	if String(row.group) == "disaster":
		# Línea aparte para que un soak distinga los desastres del resto.
		print("Disaster: %s" % id)
	print("Weather started: %s" % id)


## Lo que todo clima hace al empezar, después de su start(): tiñe el cielo
## (si la fila trae sun_color), muestra su aviso y, si es una luna, deja la
## línea "Sky event:".
func _present(row: Dictionary) -> void:
	if row.has("sun_color"):
		_tint_sky(row["sun_color"], float(row["sun_energy"]), row["ambient_color"])
	var text := String(row.get("announce", ""))
	if not text.is_empty():
		if _weather_state.has("announce_arg"):
			text = text % String(_weather_state["announce_arg"])
		_announce(text)
	if String(row.group) == "moon":
		_print_sky_event(String(row.id), float(active_weather.time_left))


## Termina el clima activo. `chain` es false al desmontar (cambio de etapa,
## salida de la partida): el follow_up no puede empezar en una arena que se va.
func _stop_weather(chain: bool) -> void:
	if active_weather.is_empty():
		return
	var id := String(active_weather.id)
	var row := weather_row(id)
	var stop: StringName = row.get("stop", &"")
	active_weather = {}
	if not stop.is_empty():
		call(stop)
	_weather_state = {}
	print("Weather ended: %s" % id)
	if not chain:
		return
	var follow_up := String(row.get("follow_up", ""))
	if not follow_up.is_empty():
		# Directo al siguiente, sin devolver el cielo: un tween de vuelta de
		# 2 s competiría con el de 1.5 s del siguiente y ganaría el más largo.
		_start_weather(follow_up)
		return
	_restore_sky()
	_sky_gap_left = sky_event_min_gap


## Las lunas imprimen esta línea TAL CUAL: la puerta CIELO_TRAS_AVANCE de
## verificar.sh la cuenta tras cada cambio de etapa para probar que se
## volvieron a buscar las luces del mapa nuevo.
func _print_sky_event(kind: String, seconds: float) -> void:
	print("Sky event: %s for %.0fs" % [kind, seconds])


## --- lunas ------------------------------------------------------------------

## Luna de sangre y eclipse: el spawner cambia la horda mientras dure
## (set_sky_event recibe el id del clima).
func _weather_start_dark_moon() -> void:
	var seconds := float(active_weather.time_left)
	get_tree().call_group("enemy_spawner", "set_sky_event", String(active_weather.id), seconds)


## Luna llena: ventajas de XP y suerte a todo el grupo, de pie o caído; la
## etiqueta hace que una luna forzada las reemplace en vez de sumarlas.
func _weather_start_full_moon() -> void:
	var seconds := float(active_weather.time_left)
	for body: Node3D in _all_raiders():
		var stats := PlayerStats.find_in(body)
		if stats != null:
			stats.clear_timed_boons(FULL_MOON_TAG)
			stats.add_timed_boon("xp_gain", full_moon_xp_bonus, seconds, FULL_MOON_TAG)
			stats.add_timed_boon("luck", full_moon_luck_bonus, seconds, FULL_MOON_TAG)


## --- lluvias ----------------------------------------------------------------

func _weather_start_enemy_rain() -> void:
	_weather_state["drop_left"] = 0.0


## Los enemigos "caen" como un aviso en el suelo más un destello, y después
## aparecen en el suelo. NO se sueltan desde arriba: un cuerpo cayendo es lo
## que el detector de cuerpos en el aire del harness atrapa, y ese detector
## no se amplía por decorado.
func _weather_tick_enemy_rain(delta: float) -> void:
	_weather_state["drop_left"] = float(_weather_state.get("drop_left", 0.0)) - delta
	if float(_weather_state["drop_left"]) > 0.0:
		return
	_weather_state["drop_left"] = enemy_rain_interval
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var color: Color = _active_row()["fx_color"]
	var wanted := randi_range(enemy_rain_min_drops, enemy_rain_max_drops)
	var points: Array[Vector3] = []
	for i in wanted:
		var point := layout.rain_point(anchor_body.global_position,
				enemy_rain_min_distance, enemy_rain_max_distance)
		if point == Vector3.INF:
			continue
		points.append(point)
		Telegraph.spawn_disc(self, point, enemy_rain_telegraph_radius,
				enemy_rain_telegraph_time, color)
		Juice.burst(point + Vector3.UP * 3.0, color, 6)
	if not points.is_empty():
		# Sin el cupo de horda (false): la lluvia es clima de 35 s, y con
		# ese cupo la arena se quedaba en su tope toda la ventana, un muro
		# que no deja pasar. El tsunami sí es una ola.
		get_tree().call_group("enemy_spawner", "spawn_at_points", points, false)


func _weather_start_radioactive_rain() -> void:
	_weather_state["pool_left"] = 0.0


func _weather_tick_radioactive_rain(delta: float) -> void:
	_weather_state["pool_left"] = float(_weather_state.get("pool_left", 0.0)) - delta
	if float(_weather_state["pool_left"]) > 0.0:
		return
	_weather_state["pool_left"] = acid_pool_interval
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var point := layout.rain_point(anchor_body.global_position, acid_pool_min_distance,
			acid_pool_spawn_range)
	if point != Vector3.INF:
		spawn_acid_pool(point)


## Lluvia dorada: x puntos y descuento para todo el grupo. A los dos grupos
## (de pie y caídos): un caído también gana los puntos que el grupo junta
## por él, y la fuente se le quita igual al terminar.
func _weather_start_golden_rain() -> void:
	for body: Node3D in _all_raiders():
		if body.has_method("set_points_source"):
			body.call("set_points_source", "golden_rain", golden_points_multiplier)
	RunState.price_discount = golden_price_discount


func _weather_stop_golden_rain() -> void:
	for body: Node3D in _all_raiders():
		if body.has_method("clear_points_source"):
			body.call("clear_points_source", "golden_rain")
	RunState.price_discount = 1.0


## --- desastres --------------------------------------------------------------

func _weather_start_tsunami() -> void:
	var anchor_body := Coop.random_player(get_tree())
	var origin := anchor_body.global_position if anchor_body != null else Vector3.ZERO
	var angle := randf() * TAU
	_weather_state["angle"] = angle
	_weather_state["origin"] = origin
	# Con el reloj de la ETAPA, no el de la partida, como las hordas: cada
	# mapa tiene su propio tramo, y con el reloj de la partida la ola de
	# una tercera etapa saldría enorme.
	var wanted := tsunami_base + tsunami_per_minute * int(RunState.stage_time / 60.0)
	_weather_state["left"] = wanted
	_weather_state["announce_arg"] = _compass_word(angle)


## Vierte la ola durante los tres segundos de la fila, por tandas de
## TSUNAMI_PER_FRAME; el tope de horda de spawn_at_points limita el total.
func _weather_tick_tsunami(_delta: float) -> void:
	var left := int(_weather_state.get("left", 0))
	if left <= 0:
		return
	var chunk := mini(left, TSUNAMI_PER_FRAME)
	var origin: Vector3 = _weather_state.get("origin", Vector3.ZERO)
	var angle := float(_weather_state.get("angle", 0.0))
	var points: Array[Vector3] = []
	for i in chunk:
		# Un arco de un solo lado: un tsunami es un muro que viene de un
		# lugar, no un anillo que se cierra (eso es una horda).
		var spread := angle + randf_range(-tsunami_arc_spread, tsunami_arc_spread)
		var pos := layout.ring_sample(origin, spread, tsunami_arc_min, tsunami_arc_max)
		if layout.walkable(pos):
			points.append(pos)
	if not points.is_empty():
		get_tree().call_group("enemy_spawner", "spawn_at_points", points, true)
	_weather_state["left"] = left - chunk


func _weather_start_earthquake() -> void:
	_weather_state["shake_left"] = 0.0
	_weather_state["dust_left"] = 0.0
	_weather_state["hud_time"] = 0.0


func _weather_tick_earthquake(delta: float) -> void:
	_weather_state["shake_left"] = float(_weather_state.get("shake_left", 0.0)) - delta
	if float(_weather_state["shake_left"]) <= 0.0:
		_weather_state["shake_left"] = earthquake_shake_interval
		Juice.shake(earthquake_shake_strength)
	_weather_state["dust_left"] = float(_weather_state.get("dust_left", 0.0)) - delta
	if float(_weather_state["dust_left"]) <= 0.0:
		_weather_state["dust_left"] = earthquake_dust_interval
		var dust: Color = _active_row()["fx_color"]
		for body: Node3D in _all_raiders():
			Juice.burst(body.global_position, dust, 8)
	# El HUD es un CanvasLayer: UN desplazamiento mueve todo lo que tiene
	# (barras, reloj, minimapas). El mapa de Tab está en otra capa y queda
	# quieto a propósito: un mapa que tiembla no se puede leer.
	var hud_time := float(_weather_state.get("hud_time", 0.0)) + delta
	_weather_state["hud_time"] = hud_time
	var phase := hud_time * earthquake_hud_hz * TAU
	get_tree().call_group("hud", "set_quake_offset", Vector2(
			sin(phase) * earthquake_hud_amplitude,
			cos(phase * 1.3) * earthquake_hud_amplitude))


func _weather_stop_earthquake() -> void:
	get_tree().call_group("hud", "set_quake_offset", Vector2.ZERO)


func _weather_start_meteors() -> void:
	_weather_state["meteor_left"] = 0.0
	_weather_state["pending"] = []


## Descuenta los avisos pendientes (los que llegan a 0 impactan) y, cada
## meteor_interval, marca un impacto nuevo cerca de un jugador al azar.
func _weather_tick_meteors(delta: float) -> void:
	var pending: Array = _weather_state.get("pending", [])
	for i in range(pending.size() - 1, -1, -1):
		var strike: Dictionary = pending[i]
		strike["left"] = float(strike["left"]) - delta
		if float(strike["left"]) > 0.0:
			pending[i] = strike
			continue
		pending.remove_at(i)
		_meteor_impact(strike["at"])
	_weather_state["pending"] = pending
	_weather_state["meteor_left"] = float(_weather_state.get("meteor_left", 0.0)) - delta
	if float(_weather_state["meteor_left"]) > 0.0:
		return
	_weather_state["meteor_left"] = meteor_interval
	if pending.size() >= MAX_LIVE_TELEGRAPHS:
		return
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var at := layout.rain_point(anchor_body.global_position, meteor_min_distance, meteor_range)
	if at == Vector3.INF:
		return
	Telegraph.spawn_disc(self, at, meteor_radius, meteor_telegraph,
			_active_row()["fx_color"])
	pending.append({"at": at, "left": meteor_telegraph})
	_weather_state["pending"] = pending


## Cae un meteorito. Daña a jugadores y enemigos (a estos más): quedarse
## quieto es el error.
func _meteor_impact(at: Vector3) -> void:
	var row := _active_row()
	Juice.burst(at + Vector3.UP * 0.5, row["impact_color"], 26)
	Juice.shake(meteor_impact_shake)
	Telegraph.spawn_disc(self, at, meteor_radius * meteor_scorch_scale, meteor_scorch_time,
			row["scorch_color"])
	var damage := meteor_damage * (1.0 + _minutes() * meteor_damage_per_minute)
	var radius_sq := meteor_radius * meteor_radius
	for body: Node3D in _all_raiders():
		if _flat_distance_sq(body.global_position, at) <= radius_sq:
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				health.take_damage(damage)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		if _flat_distance_sq(enemy.global_position, at) > radius_sq:
			continue
		var enemy_health := Health.find_in(enemy)
		if enemy_health != null and not enemy_health.is_dead:
			enemy_health.take_damage(damage * meteor_enemy_scale)


## --- cielo ------------------------------------------------------------------

## Guarda el sol y el ambiente de la arena actual y sus valores originales.
## No hace nada si ya los tiene (begin_stage los olvida en cada etapa).
func _cache_lights() -> void:
	if _sun != null:
		return
	# La ARENA, no current_scene: current_scene es la raíz de la partida y
	# sus luces son las de la arena que tenga debajo.
	var scene := layout.current_arena() if layout != null else null
	if scene == null:
		return
	for node: Node in scene.find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		_sun_color = _sun.light_color
		_sun_energy = _sun.light_energy
		break
	for node: Node in scene.find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		if world_environment == null or world_environment.environment == null:
			break
		# El Environment de la arena es un sub_resource COMPARTIDO por todas
		# las instancias de la escena: teñirlo pasaría a la partida
		# siguiente. Se trabaja sobre una copia propia de esta arena.
		_environment = world_environment.environment.duplicate()
		world_environment.environment = _environment
		_ambient_color = _environment.ambient_light_color
		_ambient_energy = _environment.ambient_light_energy
		break


## Lleva el sol y el ambiente a un tinte en 1.5 s. `sun_energy` multiplica
## la energía original del sol.
func _tint_sky(sun_color: Color, sun_energy: float, ambient: Color) -> void:
	_kill_sky_tween()
	_sky_tween = create_tween().set_parallel()
	if _sun != null:
		_sky_tween.tween_property(_sun, "light_color", sun_color, 1.5)
		_sky_tween.tween_property(_sun, "light_energy", _sun_energy * sun_energy, 1.5)
	if _environment != null:
		_sky_tween.tween_property(_environment, "ambient_light_color", ambient, 1.5)


## Devuelve el cielo original de la arena en 2 s.
func _restore_sky() -> void:
	_kill_sky_tween()
	_sky_tween = create_tween().set_parallel()
	if _sun != null:
		_sky_tween.tween_property(_sun, "light_color", _sun_color, 2.0)
		_sky_tween.tween_property(_sun, "light_energy", _sun_energy, 2.0)
	if _environment != null:
		_sky_tween.tween_property(_environment, "ambient_light_color", _ambient_color, 2.0)


## Devuelve la luz original de la arena AL INSTANTE (sin tween). Se usa
## cuando la arena se va: un tween sobre un sol liberado es un error.
func _snap_sky_back() -> void:
	_kill_sky_tween()
	if _sun != null and is_instance_valid(_sun):
		_sun.light_color = _sun_color
		_sun.light_energy = _sun_energy
	if _environment != null:
		_environment.ambient_light_color = _ambient_color
		_environment.ambient_light_energy = _ambient_energy


func _kill_sky_tween() -> void:
	if _sky_tween != null and _sky_tween.is_valid():
		_sky_tween.kill()
	_sky_tween = null


## --- utilidades -------------------------------------------------------------

## La fila de WEATHER_CATALOG del clima activo (los tick leen sus colores).
func _active_row() -> Dictionary:
	return weather_row(String(active_weather.get("id", "")))


## Todos los jugadores, de pie o caídos. Un efecto de grupo tiene que
## llegar a los dos: un cuerpo caído sale de "player" y entra en
## "downed_players".
func _all_raiders() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and is_instance_valid(body):
				bodies.append(body)
	return bodies


## Minutos de partida (el daño de los meteoritos crece con ellos).
func _minutes() -> float:
	return RunState.run_time / 60.0


## Distancia al cuadrado en el plano XZ (ignora la altura).
static func _flat_distance_sq(a: Vector3, b: Vector3) -> float:
	var span := a - b
	span.y = 0.0
	return span.length_squared()


## De dónde viene el tsunami, para el aviso: cuatro rumbos bastan para
## saber hacia dónde correr.
static func _compass_word(angle: float) -> String:
	var turns := fposmod(angle / TAU, 1.0)
	if turns < 0.125 or turns >= 0.875:
		return "desde el este"
	if turns < 0.375:
		return "desde el sur"
	if turns < 0.625:
		return "desde el oeste"
	return "desde el norte"


## Muestra un aviso centrado en el HUD (grupo "boss_ui").
func _announce(message: String) -> void:
	get_tree().call_group("boss_ui", "announce", message)
