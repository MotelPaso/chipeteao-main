class_name StageBossProbe
extends RefCounted
## Lo que ArenaProbe hace alrededor del JEFE DE ETAPA (hoy, Mythos). Vive en
## su propio archivo para no engordar arena_probe.gd, que solo lo crea y lo
## avanza. Tiene dos mitades:
##
## 1. OBSERVA, siempre y sin tocar nada: mira al cuerpo del grupo "stage_boss"
##    y su fight_state(). Ningún soak anterior llega al minuto 11, así que en
##    ellos solo imprime "Probe stage:" en cada cambio de etapa. Con un jefe
##    de etapa a la vista imprime:
##      Probe calm:        vida de cada cuerpo y cantidad de enemigos y
##                         proyectiles al empezar y al terminar la calma
##      Probe stage:       HUD, pantalla dividida, cámara de cinemática,
##                         canción y mundo congelado, tras la calma, en cada
##                         cambio de etapa y al terminar la partida
##      Probe boss hit:    el primer golpe de cada arma con el jefe en vuelo
##      Probe boss damage: al salir, el daño de cada arma al jefe por estado
##      Probe boss hits on raiders: golpes del jefe por slot
##      Probe sky:         sol y ambiente de la arena en momentos fijos y
##                         después de cada clima
##      Probe hazards:     zonas de fuego vivas un rato después de morir
##    Las cuentas de cuerpos (Probe calm, Probe hazards y Probe alone) las
##    lleva StageBossCensus.
##
## 2. ACTÚA solo con variables de entorno nuevas. Los interruptores que tocan
##    la partida (BONK_CINEMATIC_SKIP, BONK_PAUSE_AT, BONK_EXTRACT_AT,
##    BONK_WIPE_AT, BONK_WEATHER_AT) viven en stage_boss_switches.gd, que los
##    explica. Aquí queda BONK_VIEW_SHOTS=1: con BONK_SHOT_DIR, fotos desde
##    puntos fijos antes, en la calma, en la pelea y después (ViewShots).
##    BONK_STAGE_BOSS_AT y BONK_STAGE_GOAL las lee el juego (BossSchedule y
##    RunManager).

const VIEW_SHOTS_ENV := "BONK_VIEW_SHOTS"
## La lee RunManager; aquí solo se consulta si está puesta.
const STAGE_GOAL_ENV := "BONK_STAGE_GOAL"

## Segundos tras el fin de un clima antes de leer el cielo: la vuelta del
## tinte tarda 2 s (SkyTint.RESTORE_SECONDS).
const SKY_REPORT_DELAY: float = 3.0
## Frames tras el evento antes de imprimir "Probe stage:", para que el
## desmontaje de la cinemática (que escucha la misma señal) ya haya corrido.
const STAGE_REPORT_FRAMES: int = 2
## Zonas de fuego ardiendo a partir de las cuales se toma la foto de pelea,
## y segundos de pelea tras los que se toma igual.
const FIGHT_SHOT_ZONES: int = 3
const FIGHT_SHOT_FALLBACK: float = 30.0
## Segundos tras la muerte del jefe hasta la foto del mapa que queda.
const AFTERMATH_SHOT_DELAY: float = 9.0
## Avance de la calma (0-1) en que se toma la foto del cartel con el nombre
## del jefe: aparece después de la mitad, cuando ya pasó la foto de la calma.
const TITLE_SHOT_PROGRESS: float = 0.82
## Segundos antes de la llegada del jefe en que se toma la foto de «antes».
const BEFORE_SHOT_LEAD: float = 6.0

var _host: Node = null
var _tree: SceneTree = null
var _camera: ShotCamera = null
var _views: ViewShots = null
var _switches: StageBossSwitches = null
var _census: StageBossCensus = null

var _bound: bool = false
var _state: StringName = &""
var _now: float = 0.0
var _frames: int = 0
var _calm_from_frame: int = 0
var _calm_shot: bool = false
var _title_shot: bool = false
var _fight_from: float = -1.0
var _fight_shot: bool = false
var _before_shot: bool = false
## Reportes pendientes: {left (frames o segundos), reason o tag}.
var _stage_reports: Array[Dictionary] = []
var _sky_reports: Array[Dictionary] = []
var _weather_seen: String = ""
## Daño al jefe por arma: id -> {flight, other, hits}.
var _weapon_damage: Dictionary[String, Dictionary] = {}
var _raider_hits: Dictionary[int, int] = {}


func _init(host: Node, camera: ShotCamera) -> void:
	_host = host
	_tree = host.get_tree()
	_camera = camera
	_switches = StageBossSwitches.new(host)
	_census = StageBossCensus.new(host.get_tree())
	_views = ViewShots.new(host, OS.get_environment(ShotCamera.SHOT_DIR_ENV).strip_edges(),
			OS.get_environment(VIEW_SHOTS_ENV) == "1")
	if _switches.owns_weather_timing():
		_sky_reports.append({"left": 5.0, "tag": "start"})


## True si BONK_WEATHER_AT decide cuándo se fuerza el clima: ArenaProbe
## deja entonces de forzarlo a los 30 s.
func owns_weather_timing() -> bool:
	return _switches.owns_weather_timing()


## True si BONK_STAGE_GOAL acorta la puerta de etapa: la partida cruza de
## mapa y la niebla se reinicia, igual que con BONK_STAGE_FAST, así que la
## fracción explorada al salir no dice nada del recorrido.
func shortens_stage_gate() -> bool:
	return OS.get_environment(STAGE_GOAL_ENV).is_valid_float()


## Un frame de física del probe. `frames` son los que lleva el probe.
func tick(delta: float, frames: int) -> void:
	_frames = frames
	_now = float(frames) / 60.0
	_bind_once()
	_watch_boss()
	_switches.tick(delta, _now, _state)
	_census.tick(_now, _state)
	_tick_sky(delta)
	_tick_stage_reports()


## Cambio de etapa: el jefe y su cinemática se fueron con la arena.
func on_stage_changed() -> void:
	_state = &""
	_fight_from = -1.0
	_calm_shot = false
	_title_shot = false
	_fight_shot = false
	_before_shot = false
	_weather_seen = ""
	_stage_reports.append({"left": STAGE_REPORT_FRAMES, "reason": "stage_change"})
	# La etapa recién construida, desde los puntos fijos (con BONK_VIEW_SHOTS).
	_views.shoot("arrival_stage%d_lap%d" % [RunState.stage_index + 1, RunState.lap + 1])


## Fin de la partida: el estado de la pantalla, unos frames después.
func on_run_ended() -> void:
	_stage_reports.append({"left": STAGE_REPORT_FRAMES, "reason": "run_ended"})


## Resumen al salir: el daño de cada arma al jefe y los golpes del jefe.
func summary() -> void:
	for weapon_id: String in _weapon_damage:
		var row := _weapon_damage[weapon_id]
		print("Probe boss damage: weapon=%s flight=%.0f other=%.0f hits=%d" % [
				weapon_id, float(row["flight"]), float(row["other"]), int(row["hits"])])
	if not _raider_hits.is_empty():
		var line := "Probe boss hits on raiders:"
		for slot: int in _raider_hits:
			line += " p%d=%d" % [slot, _raider_hits[slot]]
		print(line)


# --- observación ---------------------------------------------------------------

## Se engancha una vez al medidor de la party y a la vida de cada raider.
func _bind_once() -> void:
	if _bound:
		return
	var power := PartyPower.find(_tree)
	if power == null:
		return
	_bound = true
	power.weapon_damage_dealt.connect(_on_weapon_damage)
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in _tree.get_nodes_in_group(group):
			var health := Health.find_in(node)
			if health != null:
				var slot := int(node.get("player_index"))
				_raider_hits[slot] = 0
				health.damaged_by.connect(_on_raider_hit.bind(slot))


func _stage_boss() -> Node3D:
	var boss := _tree.get_first_node_in_group(BossSchedule.STAGE_BOSS_GROUP) as Node3D
	return boss if boss != null and is_instance_valid(boss) and boss.is_inside_tree() else null


func _watch_boss() -> void:
	_tick_before_shot()
	var boss := _stage_boss()
	var state: StringName = &""
	if boss != null and boss.has_method(&"fight_state"):
		state = boss.call(&"fight_state")
	if state != _state:
		_on_state_changed(_state, state)
		_state = state
	if _state == &"arrival":
		_tick_calm_shot()
	elif _state == &"flight" or _state == &"move":
		_tick_fight_shot()


func _on_state_changed(from: StringName, to: StringName) -> void:
	if to == &"arrival":
		_calm_from_frame = _frames
		_census.begin_calm()
	elif from == &"arrival" and to == &"":
		# El jefe se fue en plena calma (cambio de etapa forzado): no hay
		# pelea que empiece ni vidas que comparar con las de otra arena.
		print("Probe calm: aborted after %d frames (stage boss gone)" % (
				_frames - _calm_from_frame))
	elif from == &"arrival":
		_census.report_calm(_frames - _calm_from_frame)
		_fight_from = _now
		_stage_reports.append({"left": STAGE_REPORT_FRAMES, "reason": "calm_end"})
		_sky_reports.append({"left": 5.0, "tag": "fight"})
		_camera.request_in(2.0, "boss_fight_start_%.0fs" % _now)
	if to == &"dead":
		_sky_reports.append({"left": AFTERMATH_SHOT_DELAY, "tag": "aftermath"})
		_stage_reports.append({"left": int(AFTERMATH_SHOT_DELAY * 60.0), "reason": "aftermath"})
		_camera.request_in(AFTERMATH_SHOT_DELAY, "boss_aftermath_%.0fs" % _now)
		_shoot_views_in(AFTERMATH_SHOT_DELAY, "charred")


func _on_weapon_damage(weapon: WeaponBase, target: Node3D, amount: float) -> void:
	if target == null or not target.is_in_group(BossSchedule.STAGE_BOSS_GROUP):
		return
	var weapon_id := WeaponCatalog.id_for_node(String(weapon.name))
	if weapon_id.is_empty():
		weapon_id = String(weapon.name)
	var state := "n/a"
	if target.has_method(&"fight_state"):
		state = String(target.call(&"fight_state"))
	if not _weapon_damage.has(weapon_id):
		_weapon_damage[weapon_id] = {"flight": 0.0, "other": 0.0, "hits": 0}
	var row := _weapon_damage[weapon_id]
	var in_flight := state == "flight"
	if in_flight and is_zero_approx(float(row["flight"])):
		print("Probe boss hit: weapon=%s state=flight amount=%.1f at %.1fs" % [
				weapon_id, amount, _now])
	row["flight" if in_flight else "other"] = float(row["flight" if in_flight else "other"]) \
			+ amount
	row["hits"] = int(row["hits"]) + 1


func _on_raider_hit(attacker: Node3D, slot: int) -> void:
	if attacker != null and is_instance_valid(attacker) \
			and attacker.is_in_group(BossSchedule.STAGE_BOSS_GROUP):
		_raider_hits[slot] = int(_raider_hits.get(slot, 0)) + 1


# --- reportes ------------------------------------------------------------------

func _tick_stage_reports() -> void:
	for index: int in range(_stage_reports.size() - 1, -1, -1):
		var report := _stage_reports[index]
		report["left"] = int(report["left"]) - 1
		if int(report["left"]) <= 0:
			_stage_reports.remove_at(index)
			_print_stage(String(report["reason"]))


## Cómo quedó la pantalla: lo que la cinemática toca y tiene que devolver.
func _print_stage(reason: String) -> void:
	var hud := "n/a"
	for node: Node in _tree.get_nodes_in_group(&"hud"):
		hud = str(bool(node.get("visible")))
	var split := "n/a"
	for node: Node in _tree.get_nodes_in_group(&"split_screen"):
		split = str(bool(node.get("visible")))
	var cinematic_camera := false
	for node: Node in _tree.get_nodes_in_group(&"cinematic_camera"):
		var camera := node as Camera3D
		if camera != null and camera.current:
			cinematic_camera = true
	var song := false
	for node: Node in _tree.get_nodes_in_group(&"boss_music"):
		var player := node as AudioStreamPlayer
		# has_stream_playback y no `playing`: con el árbol en pausa `playing`
		# lee false aunque la canción siga ahí, esperando.
		if player != null and player.has_stream_playback():
			song = true
	print(("Probe stage: reason=%s hud_visible=%s split_visible=%s cinematic_camera=%s"
			+ " song_playing=%s root_camera=%s world_frozen=%s clock_running=%s") % [
			reason, hud, split, cinematic_camera, song, _root_camera(), _world_frozen(),
			RunState.is_physics_processing()])
	if reason == "aftermath":
		_census.print_hazards(reason)


## Qué cámara 3D tiene activa el viewport raíz: "none" (lo normal en co-op,
## donde cada raider pinta en su propio SubViewport), "cinematic", "raider"
## (lo normal en solitario) u "other".
func _root_camera() -> String:
	var camera := _tree.root.get_camera_3d()
	if camera == null:
		return "none"
	if camera.is_in_group(&"cinematic_camera"):
		return "cinematic"
	var node: Node = camera
	while node != null:
		if node.is_in_group(&"player") or node.is_in_group(&"downed_players"):
			return "raider"
		node = node.get_parent()
	return "other"


## True si la arena o algún raider siguen desactivados.
func _world_frozen() -> bool:
	var arena := RunRoot.stage_parent(_tree)
	if arena != null and arena.process_mode == Node.PROCESS_MODE_DISABLED:
		return true
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in _tree.get_nodes_in_group(group):
			if node.process_mode == Node.PROCESS_MODE_DISABLED:
				return true
	return false


## Sol y ambiente de la arena viva, y la foto de ese momento.
func _print_sky(tag: String) -> void:
	var arena := RunRoot.stage_parent(_tree)
	if arena == null:
		return
	var sun: DirectionalLight3D = null
	for node: Node in arena.find_children("*", "DirectionalLight3D", true, false):
		sun = node as DirectionalLight3D
		break
	var environment: Environment = null
	for node: Node in arena.find_children("*", "WorldEnvironment", true, false):
		environment = (node as WorldEnvironment).environment
		break
	if sun == null or environment == null:
		return
	var look := "none"
	for node: Node in _tree.get_nodes_in_group(&"stage_transformation"):
		if node.has_method(&"state_name"):
			look = String(node.call(&"state_name"))
	var ambient := environment.ambient_light_color
	print(("Probe sky: tag=%s look=%s sun=(%.2f,%.2f,%.2f) sun_energy=%.2f"
			+ " ambient=(%.2f,%.2f,%.2f) ambient_energy=%.2f at %.1fs") % [
			tag, look, sun.light_color.r, sun.light_color.g, sun.light_color.b,
			sun.light_energy, ambient.r, ambient.g, ambient.b,
			environment.ambient_light_energy, _now])
	var stem := "sky_%s_%.0fs" % [tag.replace(":", "_"), _now]
	_camera.request(stem)
	# Con BONK_VIEW_SHOTS, además desde los puntos fijos y sin HUD: la foto
	# normal puede caer con el mapa de Tab abierto o con un ataque delante.
	_views.shoot(stem)


## Lee el cielo SKY_REPORT_DELAY después de que cada clima termina del todo,
## y en los momentos que otros reportes dejaron pendientes.
func _tick_sky(delta: float) -> void:
	var director := _tree.get_first_node_in_group(&"world_director")
	var live: Variant = director.get("active_weather") if director != null else null
	var weather := live as Dictionary if live is Dictionary else {}
	var now_id := String(weather.get("id", "")) if not weather.is_empty() else ""
	if now_id.is_empty() and not _weather_seen.is_empty():
		_sky_reports.append({"left": SKY_REPORT_DELAY, "tag": "after:%s" % _weather_seen})
	_weather_seen = now_id
	for index: int in range(_sky_reports.size() - 1, -1, -1):
		var report := _sky_reports[index]
		report["left"] = float(report["left"]) - delta
		if float(report["left"]) <= 0.0:
			_sky_reports.remove_at(index)
			_print_sky(String(report["tag"]))


# --- fotos ---------------------------------------------------------------------

## «Antes»: unos segundos antes de que llegue el jefe de etapa.
func _tick_before_shot() -> void:
	if _before_shot or RunState.stage_index != 0:
		return
	var forced := OS.get_environment(BossSchedule.STAGE_BOSS_AT_ENV)
	var due := forced.to_float() if forced.is_valid_float() else -1.0
	if due < 0.0:
		var spawner := _tree.get_first_node_in_group(&"enemy_spawner")
		if spawner == null or spawner.get("stage_boss_scene") == null:
			return
		due = float(spawner.get("elder_spawn_minute")) * 60.0
	if RunState.stage_time < due - BEFORE_SHOT_LEAD:
		return
	_before_shot = true
	_camera.request("boss_before_%.0fs" % _now)
	_views.shoot("before")


## Mitad de la calma: la cinemática a medio camino. Más adelante, otra foto
## con el cartel del nombre ya en pantalla.
func _tick_calm_shot() -> void:
	if _calm_shot and _title_shot:
		return
	var progress := -1.0
	for node: Node in _tree.get_nodes_in_group(&"boss_cinematic"):
		if node.has_method(&"calm_progress"):
			progress = float(node.call(&"calm_progress"))
	if not _calm_shot and progress >= 0.5:
		_calm_shot = true
		_camera.request("boss_calm_%.0fs" % _now)
		_views.shoot("calm")
	if not _title_shot and progress >= TITLE_SHOT_PROGRESS:
		_title_shot = true
		_camera.request("boss_title_%.0fs" % _now)


## Pelea: con zonas de fuego ardiendo a la vista (o a los 30 s, lo que pase antes).
func _tick_fight_shot() -> void:
	if _fight_shot or _fight_from < 0.0:
		return
	var burning := 0
	for node: Node in _tree.get_nodes_in_group(FireZone.GROUP):
		var zone := node as FireZone
		if zone != null and zone.is_burning():
			burning += 1
	if burning < FIGHT_SHOT_ZONES and _now - _fight_from < FIGHT_SHOT_FALLBACK:
		return
	_fight_shot = true
	_camera.request("boss_fight_%.0fs" % _now)
	_views.shoot("hell")


func _shoot_views_in(delay: float, moment: String) -> void:
	if not _views.enabled():
		return
	await _tree.create_timer(delay, true, true).timeout
	_views.shoot(moment)
