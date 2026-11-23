class_name WeatherDirector
extends Node
## Clima de la partida: lunas, lluvias y desastres, con UN canal por grupo
## (moon, rain, disaster): pueden coincidir una luna, una lluvia y un
## desastre, pero nunca dos del mismo grupo. Cada canal guarda su fila y sus
## datos en _channels; mientras corre el start/tick/stop de un clima,
## active_weather y _weather_state apuntan a los de SU canal.
## Es el nodo RunSystems.tscn > WorldDirector > Weather: sus números se
## editan en el Inspector de ese nodo, y el aspecto y el texto de cada
## clima en su fila de WeatherCatalog (weather_catalog.gd). El tinte del
## cielo lo hace SkyTint (sky_tint.gd).
## No tiene _physics_process propio: el WorldDirector llama a tick() cada
## frame y, en cada pulso por minuto, a start_random() y roll_extra(); ese
## orden es parte del sorteo (el RNG de la partida es uno solo).
## En el código esto es WEATHER, nunca "event": EVENT_LIBRARY es la tabla
## de eventos de POI. Para el jugador la palabra sigue siendo «evento».

## Alias de WeatherCatalog.WEATHER_CATALOG: catalog_lint.gd lo lee por
## este script.
const WEATHER_CATALOG: Array[Dictionary] = WeatherCatalog.WEATHER_CATALOG
## Tope de charcos de ácido vivos y distancia mínima entre ellos (metros).
## Pasado el tope se saltan; subir el tope no es la solución.
const MAX_LIVE_ACID_POOLS: int = 24
const ACID_POOL_SPACING: float = 3.0
## Tope de avisos de meteorito vivos, por lo mismo (el pool de discos es
## de 32 y lo usa todo el juego).
const MAX_LIVE_TELEGRAPHS: int = 16
## Etiqueta de las dos ventajas de la luna llena: una segunda luna dentro
## de la primera las reemplaza en vez de sumarlas (solo clear_timed_boons
## quita por etiqueta).
const FULL_MOON_TAG: String = "full_moon"
## Climas que solo traen enemigos (ids de WeatherCatalog): no empiezan
## mientras el jefe de etapa pelea solo (EnemySpawner.is_holding).
const ENEMY_WEATHERS: Array[String] = ["enemy_rain", "enemy_tsunami"]

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
## Duraciones (segundos) que reemplazan las de WeatherCatalog, por id de
## clima. Vale para todas las arenas: este nodo es uno por partida.
@export var weather_duration_overrides: Dictionary[String, float] = {}

@export_group("Luna llena")
## XP extra (porcentaje) que da la luna llena a todo el grupo.
@export var full_moon_xp_bonus: float = 50.0
## Suerte extra (porcentaje: multiplica la suerte que ya tiene cada uno; 30 =
## suerte ×1,3) que da la luna llena a todo el grupo. Sin suerte no suma nada.
@export var full_moon_luck_percent: float = 30.0
## Suerte extra en puntos que da la luna llena, ANTES del porcentaje de arriba.
@export var full_moon_luck_bonus: float = 30.0
## Niveles que alcanza a dar la lluvia de XP de la luna llena (ya descontados
## los bonos de XP, así son los niveles que se ven; 2.5 = entre 2 y 3).
@export var full_moon_xp_rain_levels: float = 2.5
## Tope de gemas de la lluvia de XP (al principio salen menos y cada una vale 1).
@export var full_moon_xp_rain_gems: int = 30
## Segundos, desde que empieza la luna, en los que cae la lluvia de XP.
@export var full_moon_xp_rain_seconds: float = 20.0
## Distancia mínima (metros) de cada gema al jugador.
@export var full_moon_xp_rain_min_distance: float = 3.0
## Distancia máxima (metros) de cada gema al jugador.
@export var full_moon_xp_rain_max_distance: float = 12.0
## Altura (metros) del destello sobre cada gema que cae.
@export var full_moon_xp_rain_burst_height: float = 3.0
## Partículas del destello de cada gema.
@export var full_moon_xp_rain_burst_count: int = 5

@export_group("Lluvia de enemigos")
## Segundos entre tandas.
@export var enemy_rain_interval: float = 1.5
## Enemigos mínimos por tanda.
@export var enemy_rain_min_drops: int = 2
## Enemigos máximos por tanda.
@export var enemy_rain_max_drops: int = 5
## Distancia mínima (metros) de cada caída al jugador.
@export var enemy_rain_min_distance: float = 18.0
## Distancia máxima (metros) de cada caída al jugador.
@export var enemy_rain_max_distance: float = 32.0
## Radio (metros) del aviso en el suelo de cada caída.
@export var enemy_rain_telegraph_radius: float = 1.4
## Segundos que dura ese aviso.
@export var enemy_rain_telegraph_time: float = 1.0
## Altura (metros) del destello sobre cada aviso de caída.
@export var enemy_rain_burst_height: float = 3.0
## Partículas de ese destello.
@export var enemy_rain_burst_count: int = 6

@export_group("Lluvia radiactiva")
## Segundos entre charcos de ácido.
@export var acid_pool_interval: float = 1.4
## Radio (metros) de cada charco.
@export var acid_pool_radius: float = 2.0
## Segundos que dura cada charco.
@export var acid_pool_lifetime: float = 6.0
## Distancia mínima (metros) de un charco al jugador.
@export var acid_pool_min_distance: float = 2.0
## Distancia MÁXIMA (metros) de un charco al jugador.
@export var acid_pool_spawn_range: float = 20.0
## Daño por segundo del ácido a un jugador dentro de un charco.
@export var acid_pool_damage_per_second: float = 6.0

@export_group("Lluvia dorada")
## Multiplicador de puntos mientras cae.
@export var golden_points_multiplier: float = 2.0
## Factor de precio mientras cae (0.5 = mitad de precio).
@export var golden_price_discount: float = 0.5

@export_group("Tsunami")
## Enemigos de la ola al empezar la etapa.
@export var tsunami_base: int = 55
## Enemigos extra de la ola por minuto de etapa.
@export var tsunami_per_minute: int = 6
## Distancia (metros) del jugador a la que nace la ola.
@export var tsunami_start_distance: float = 40.0
## Metros que sigue la ola después de arrollar al jugador, antes de soltar a los enemigos.
@export var tsunami_pass_distance: float = 14.0
## Cuánto puede girar la ola por segundo para perseguir al jugador, en radianes (1.2 son unos 70 grados).
@export var tsunami_turn_speed: float = 1.2
## Metros máximos que recorre la ola si nunca alcanza al jugador.
@export var tsunami_max_travel: float = 130.0
## Velocidad de la ola, en m/s (el jugador corre a unos 8).
@export var tsunami_speed: float = 13.0
## Ancho de la ola, en metros.
@export var tsunami_width: float = 46.0
## Filas de enemigos de la ola, de adelante hacia atrás.
@export var tsunami_rows: int = 4
## Metros entre una fila y la siguiente.
@export var tsunami_row_gap: float = 1.8
## Altura (metros) del dibujo de la fila de adelante: la base de la ola.
@export var tsunami_crest_low: float = 0.3
## Altura (metros) del dibujo de la fila de atrás: la cresta.
@export var tsunami_crest_high: float = 4.5
## Cuánto sube y baja cada enemigo sobre la ola, en metros.
@export var tsunami_bob: float = 0.5
## Rapidez de ese vaivén (radianes por segundo).
@export var tsunami_bob_speed: float = 7.0
## Empujón horizontal de la ola al jugador que arrolla, en m/s, en el sentido en que va la ola (no hace daño).
@export var tsunami_push_speed: float = 24.0
## Impulso hacia arriba de la ola al jugador, en m/s (el salto normal es 8.7).
@export var tsunami_push_lift: float = 13.0
## Sacudida de cámara al ser alcanzado por la ola (0-1).
@export var tsunami_hit_shake: float = 0.4
## Segundos entre chispas de espuma sobre la ola.
@export var tsunami_foam_interval: float = 0.08
## Chispas por cada salpicón de espuma.
@export var tsunami_foam_count: int = 10

@export_group("Terremoto")
## Segundos entre sacudidas de cámara.
@export var earthquake_shake_interval: float = 0.5
## Fuerza de cada sacudida de cámara (trauma, 0-1).
@export var earthquake_shake_strength: float = 0.25
## Cuánto se desplaza el HUD (píxeles).
@export var earthquake_hud_amplitude: float = 14.0
## Vibraciones por segundo del HUD.
@export var earthquake_hud_hz: float = 20.0
## Segundos entre nubes de polvo sobre cada jugador.
@export var earthquake_dust_interval: float = 3.0
## Partículas de cada nube de polvo.
@export var earthquake_dust_count: int = 8

@export_group("Meteoritos")
## Segundos entre meteoritos.
@export var meteor_interval: float = 0.6
## Distancia mínima (metros) de un meteorito al jugador.
@export var meteor_min_distance: float = 0.0
## Distancia MÁXIMA (metros) de un meteorito al jugador.
@export var meteor_range: float = 20.0
## Radio (metros) de cada impacto.
@export var meteor_radius: float = 3.0
## Segundos de aviso en el suelo antes del impacto.
@export var meteor_telegraph: float = 1.2
## Daño de cada impacto a los jugadores.
@export var meteor_damage: float = 50.0
## Cuánto crece ese daño por minuto de partida (0.05 = +5 % por minuto).
@export var meteor_damage_per_minute: float = 0.05
## Multiplicador del daño del impacto a los enemigos.
@export var meteor_enemy_scale: float = 3.0
## Fuerza de la sacudida de cámara de cada impacto (trauma, 0-1).
@export var meteor_impact_shake: float = 0.35
## Partículas de la explosión de cada impacto.
@export var meteor_impact_burst_count: int = 26
## Empujón horizontal al jugador que golpea un meteorito, en m/s, hacia afuera del impacto.
@export var meteor_push_speed: float = 11.0
## Impulso hacia arriba del golpe de meteorito, en m/s (el salto normal es 8.7).
@export var meteor_push_lift: float = 9.0
## Tamaño de la marca del impacto, relativo a meteor_radius.
@export var meteor_scorch_scale: float = 0.8
## Segundos que dura la marca del impacto.
@export var meteor_scorch_time: float = 0.5

## El clima activo más reciente, o vacío: {id, group, time_left}. El probe
## lo lee a través del WorldDirector. Mientras
## corre el código de un clima apunta al de SU canal.
var active_weather: Dictionary = {}
## Todos los climas vivos a la vez, uno por canal (luna, lluvia, desastre),
## cada uno {id, group, time_left}. El chip del HUD los muestra todos.
var active_weathers: Array[Dictionary]:
	get:
		var all: Array[Dictionary] = []
		for channel: Dictionary in _channels.values():
			all.append(channel.weather)
		return all
## Canales vivos: grupo -> {"weather": {...}, "state": {...}}.
var _channels: Dictionary = {}
## Reparto de la etapa (máscara y muestreos); lo pone el WorldDirector.
var layout: StageLayout = null

## Datos propios del clima activo (start/tick/stop); se vacía al empezar
## uno, así ningún clima lee lo que dejó el anterior.
var _weather_state: Dictionary = {}
var _sky: SkyTint = null


func _init() -> void:
	_sky = SkyTint.new(self)


## La partida puede terminar en medio de un clima: se detiene y el cielo
## vuelve en seco, para que el tinte no pase a la partida siguiente. Va
## aquí y no en el WorldDirector porque los hijos salen del árbol antes que
## el padre, y el stop() de un clima necesita el árbol.
func _exit_tree() -> void:
	end_stage()


## La fila de WeatherCatalog con ese id, o vacío (weather_badge.gd y el
## WorldDirector la leen por aquí).
static func weather_row(id: String) -> Dictionary:
	return WeatherCatalog.by_id(id)


## Inicio de etapa: olvida las luces de la arena anterior (si no, la etapa
## 2 teñiría el sol ya liberado de la etapa 1 y ningún cielo se vería) y
## vacía el canal, sin stop(): on_stage_ended ya detuvo el clima.
func begin_stage(stage_layout: StageLayout) -> void:
	layout = stage_layout
	_sky.forget()
	active_weather = {}
	_weather_state = {}
	_channels = {}


## Fin de etapa o de partida: detiene el clima sin encadenar el siguiente
## y devuelve el cielo al instante, antes de que la arena se libere.
func end_stage() -> void:
	stop_weather()
	_sky.snap_back()


## Detiene el clima activo sin encadenar el siguiente ni devolver el cielo
## (fin de partida: la pantalla final deja la arena tal cual).
func stop_weather() -> void:
	for group: String in _channels.keys():
		_use(group)
		_stop_weather(false)
		_store(group)
	_publish()


## Un frame de física del canal: descuenta la pausa y el clima activo.
func tick(delta: float) -> void:
	for group: String in _channels.keys():
		_use(group)
		_tick_channel(delta)
		_store(group)
	_publish()


## Un frame del clima del canal en uso.
func _tick_channel(delta: float) -> void:
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


## La tirada extra de cada pulso, aparte del clima asegurado: cada grupo
## (desastre, lluvia, luna) tira su probabilidad por separado y, si sale y
## su canal está libre, empieza.
func roll_extra() -> void:
	_try_group("disaster", disaster_chance + RunState.disaster_chance_bonus)
	_try_group("rain", rain_chance + RunState.event_chance_bonus)
	# Los pactos demoníacos venden probabilidad de luna, además del extra
	# que suma cada altar demoníaco usado.
	_try_group("moon", sky_event_chance + RunState.event_chance_bonus
			+ sky_event_chance_per_demonic * float(RunState.demonic_uses))


## Con probabilidad 0 o el canal ocupado no se tira dado: el RNG de la
## partida es uno solo y un dado de más cambia todo lo que se sortea después.
func _try_group(group: String, odds: float) -> void:
	if odds <= 0.0 or _channels.has(group) or randf() >= odds:
		return
	_start_weather(WeatherCatalog.roll_group(group))
	_publish()


## FUERZA un clima (el pulso por minuto con los tres canales llenos, la
## ruleta, el bloque de la suerte, el probe, BONK_WEATHER_NOW): detiene el
## de su grupo y empieza aunque no haya pasado la pausa (la puerta
## CIELO_TRAS_AVANCE de verificar.sh lo prueba).
func start_sky_event(kind: String) -> void:
	_start_weather(kind, true)
	_publish()


## Empieza un clima cualquiera (luna, lluvia o desastre) si no hay otro
## corriendo; lo pide el pulso por minuto del WorldDirector. Devuelve el id
## que empezó, o "" si el canal estaba ocupado.
func start_random() -> String:
	if _channels.size() >= 3:
		return ""
	# Se reintenta si sale un grupo ocupado; con los tres llenos no hay sitio.
	for attempt in 8:
		var id := WeatherCatalog.roll_any()
		if id.is_empty():
			return ""
		if _channels.has(String(weather_row(id).group)):
			continue
		_start_weather(id)
		_publish()
		return id if is_weather_active(id) else ""
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


## La arena cambió de cielo a mitad de etapa (HellTransformation): desde
## ahora el tinte de cada clima vuelve a ESTE sol y ambiente. Devuelve el
## Environment propio de la arena, que es el que hay que escribir.
func rebase_sky(sun_color: Color, sun_energy: float, ambient_color: Color,
		ambient_energy: float) -> Environment:
	# cache() primero: si ningún clima corrió en esta etapa, todavía no hay
	# copia propia del Environment ni sol guardado.
	_sky.cache(layout)
	_sky.rebase(sun_color, sun_energy, ambient_color, ambient_energy)
	return _sky.environment()


## El cielo «original» de la arena ahora, sin el tinte del clima que esté en
## curso (ver SkyTint.base()): lo pide quien va a cambiarlo por un rato.
func sky_base() -> Dictionary:
	_sky.cache(layout)
	return _sky.base()


## Verdadero mientras `id` sea el clima activo.
func is_weather_active(id: String) -> bool:
	for channel: Dictionary in _channels.values():
		if String(channel.weather.get("id", "")) == id:
			return true
	return false


## Apunta active_weather y _weather_state al canal de `group` (vacíos si no
## hay clima en ese grupo).
func _use(group: String) -> void:
	var channel: Dictionary = _channels.get(group, {})
	active_weather = channel.get("weather", {})
	_weather_state = channel.get("state", {})


## Guarda en `group` lo que dejó el código del clima (o lo borra si terminó).
func _store(group: String) -> void:
	if active_weather.is_empty():
		_channels.erase(group)
	else:
		_channels[group] = {"weather": active_weather, "state": _weather_state}


## Deja active_weather en el clima vivo más reciente, para los lectores.
func _publish() -> void:
	active_weather = {}
	_weather_state = {}
	for channel: Dictionary in _channels.values():
		active_weather = channel.weather
		_weather_state = channel.state


## --- canal ------------------------------------------------------------------

## Segundos que dura esta fila, con el reemplazo del Inspector y, solo en
## lunas y lluvias, el multiplicador de los pactos.
func _weather_duration(row: Dictionary) -> float:
	var seconds := float(weather_duration_overrides.get(String(row.id), row.duration))
	if WeatherCatalog.STRETCHABLE_GROUPS.has(String(row.group)):
		seconds *= RunState.sky_duration_multiplier
	return seconds


func _start_weather(id: String, forced: bool = false) -> void:
	if id.is_empty():
		return
	if not forced and ENEMY_WEATHERS.has(id) and EnemySpawner.is_holding(get_tree()):
		# El jefe de etapa pelea solo: un clima que solo trae enemigos no
		# empieza (anunciaría una ola que el spawner no va a sacar).
		return
	var row := weather_row(id)
	if row.is_empty():
		push_warning("WorldDirector: unknown weather '%s'" % id)
		return
	var group := String(row.group)
	_use(group)
	if not active_weather.is_empty():
		if not forced:
			return
		# Forzado: el clima de ese grupo se detiene bien, con su stop(), que es
		# lo que suelta el tinte, la fuente de puntos y el desplazamiento del HUD.
		_stop_weather(false)
	_sky.cache(layout)
	_weather_state = {}
	var seconds := _weather_duration(row)
	active_weather = {"id": id, "group": group, "time_left": seconds}
	call(row.start)
	_present(row)
	# Queda apuntando a su canal: quien llamó (tick, roll_extra, las
	# funciones públicas) publica al final.
	_store(group)
	if String(row.group) == "disaster":
		# Línea aparte para que un soak distinga los desastres del resto.
		print("Disaster: %s" % id)
	print("Weather started: %s" % id)


## Lo que todo clima hace al empezar, después de su start(): tiñe el cielo
## (si la fila trae sun_color), muestra su aviso y, si es una luna, deja la
## línea "Sky event:".
func _present(row: Dictionary) -> void:
	if row.has("sun_color"):
		_sky.tint(row["sun_color"], float(row["sun_energy"]), row["ambient_color"])
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
	_restore_sky_after(String(row.group))


## Al terminar el clima de `group`: si otro canal tiñe el cielo, el cielo
## vuelve a su tinte; si no, vuelve al del mapa.
func _restore_sky_after(group: String) -> void:
	for other: String in _channels.keys():
		if other == group:
			continue
		var row := weather_row(String(_channels[other].weather.get("id", "")))
		if row.has("sun_color"):
			_sky.tint(row["sun_color"], float(row["sun_energy"]), row["ambient_color"])
			return
	_sky.restore()


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


## Luna llena: ventajas de XP y suerte (puntos y %) a todo el grupo, de pie o
## caído, y una lluvia de XP; la etiqueta hace que una luna forzada reemplace
## las ventajas en vez de sumarlas.
func _weather_start_full_moon() -> void:
	var seconds := float(active_weather.time_left)
	for body: Node3D in _all_raiders():
		var stats := PlayerStats.find_in(body)
		if stats != null:
			stats.clear_timed_boons(FULL_MOON_TAG)
			stats.add_timed_boon("xp_gain", full_moon_xp_bonus, seconds, FULL_MOON_TAG)
			stats.add_timed_boon("luck", full_moon_luck_bonus, seconds, FULL_MOON_TAG)
			stats.add_timed_boon("luck_percent", full_moon_luck_percent, seconds, FULL_MOON_TAG)
	# El plan va después de las ventajas: descuenta el bono de XP de la luna.
	var rain := XpRain.plan(full_moon_xp_rain_levels, full_moon_xp_rain_gems,
			full_moon_xp_rain_seconds, _all_raiders())
	_weather_state["xp_gems_left"] = int(rain.gems)
	_weather_state["xp_gem_value"] = int(rain.value)
	_weather_state["xp_gem_every"] = float(rain.every)
	_weather_state["xp_drop_left"] = 0.0


## Suelta las gemas de la lluvia de XP de a una, repartidas en
## full_moon_xp_rain_seconds.
func _weather_tick_full_moon(delta: float) -> void:
	var left := int(_weather_state.get("xp_gems_left", 0))
	var wait := float(_weather_state.get("xp_drop_left", 0.0)) - delta
	var color: Color = _active_row()["fx_color"]
	while left > 0 and wait <= 0.0:
		wait += float(_weather_state["xp_gem_every"])
		left -= 1
		XpRain.drop_gem(get_tree(), layout, int(_weather_state["xp_gem_value"]),
				full_moon_xp_rain_min_distance, full_moon_xp_rain_max_distance, color,
				full_moon_xp_rain_burst_height, full_moon_xp_rain_burst_count)
	_weather_state["xp_gems_left"] = left
	_weather_state["xp_drop_left"] = wait


## --- lluvias ----------------------------------------------------------------

func _weather_start_enemy_rain() -> void:
	_weather_state["drop_left"] = 0.0


## Los enemigos caen del cielo sobre un aviso en el suelo: el cuerpo nace
## en el suelo y solo su dibujo cae (EnemyBase.drop_from_sky), así ningún
## cuerpo queda en el aire para el detector del harness.
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
		Juice.burst(point + Vector3.UP * enemy_rain_burst_height, color,
				enemy_rain_burst_count)
	if not points.is_empty():
		# Sin el cupo de horda (false): la lluvia es clima de 40 s, y con
		# ese cupo la arena se quedaba en su tope toda la ventana, un muro
		# que no deja pasar. El tsunami sí es una ola.
		get_tree().call_group("enemy_spawner", "spawn_at_points", points, false, true)


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
	var wave := TsunamiWave.new(self, layout)
	wave.start(anchor_body, angle, wanted, _active_row()["fx_color"])
	_weather_state["wave"] = wave
	_weather_state["announce_arg"] = WeatherCatalog.compass_word(angle)


## La ola avanza hasta soltar a sus enemigos; la duración de la fila le alcanza.
func _weather_tick_tsunami(delta: float) -> void:
	var wave := _weather_state.get("wave") as TsunamiWave
	if wave != null:
		wave.tick(delta)


## Si el desastre se corta antes, la ola suelta a los que lleva.
func _weather_stop_tsunami() -> void:
	var wave := _weather_state.get("wave") as TsunamiWave
	if wave != null:
		wave.release_all()


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
			Juice.burst(body.global_position, dust, earthquake_dust_count)
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
## meteor_interval, marca un impacto nuevo cerca de un jugador al azar y
## suelta su meteorito (MeteorFall).
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
	# La roca cae del cielo durante el aviso y toca el suelo al impactar.
	MeteorFall.spawn(self, at, meteor_telegraph)
	pending.append({"at": at, "left": meteor_telegraph})
	_weather_state["pending"] = pending


## Cae un meteorito. Daña a jugadores y enemigos (a estos más): quedarse
## quieto es el error.
func _meteor_impact(at: Vector3) -> void:
	var row := _active_row()
	Juice.burst(at + Vector3.UP * 0.5, row["impact_color"], meteor_impact_burst_count)
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
				_launch_raider(body, at)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		if _flat_distance_sq(enemy.global_position, at) > radius_sq:
			continue
		var enemy_health := Health.find_in(enemy)
		if enemy_health != null and not enemy_health.is_dead:
			enemy_health.take_damage(damage * meteor_enemy_scale)


## Lanza por el aire al raider que golpeó el meteorito, hacia afuera del impacto.
func _launch_raider(body: Node3D, at: Vector3) -> void:
	var knockback := body.get_node_or_null(^"Knockback") as PlayerKnockback
	if knockback != null:
		knockback.launch_from(at, meteor_push_speed, meteor_push_lift)


## --- utilidades -------------------------------------------------------------

## La fila de WeatherCatalog del clima activo (los tick leen sus colores).
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


## Muestra un aviso centrado en el HUD (grupo "boss_ui").
func _announce(message: String) -> void:
	get_tree().call_group("boss_ui", "announce", message)
