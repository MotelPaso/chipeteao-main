class_name MiniBossProbe
extends RefCounted
## Lo que ArenaProbe observa del MINIJEFE de una arena (hoy, la Langosta Azul
## del Bosque Hueco). Mira al cuerpo del grupo "mini_boss" (lo mete
## BossSchedule) y nunca al del grupo "stage_boss": ese es de StageBossProbe.
## Solo OBSERVA: no toca la partida y no tiene variables de entorno propias.
## BONK_MINI_BOSS_AT la lee BossSchedule, y los interruptores de
## stage_boss_switches.gd (saltar, pausar, extraer, derribar, cambiar de
## etapa) actúan igual sobre la entrada de un minijefe, porque buscan el grupo
## "boss_cinematic".
## Imprime:
##   Probe mini calm:    vidas y cuerpos al empezar y al terminar la entrada:
##                       con el mundo congelado nada cambia ni aparece. La
##                       vida del propio minijefe no cuenta (su plan de vida
##                       se aplica justo al empezar la pelea)
##   Probe mini stage:   HUD, pantalla dividida, cámara, canción y mundo, dos
##                       frames después de la entrada y un rato después de morir
##   Probe mini fight:   al morir, cuánto duró la pelea según el reloj del probe
##   Probe mini states:  al salir, segundos en cada estado
##   Probe mini damage:  al salir, daño de cada arma por estado
##   Probe mini hits on raiders: al salir, golpes del minijefe por slot
##   Probe mini hazards: lo que dejó vivo AFTERMATH_DELAY segundos después de
##                       morir, y cuántas veces su Health emitió `died`
## Con BONK_SHOT_DIR pide además las fotos de la entrada: el último frame de
## juego antes del corte, el primero del corte, uno en cada golpe, el cartel y
## la pelea.

## Grupo del minijefe vivo (BossSchedule.MINI_BOSS_GROUP).
const GROUP := &"mini_boss"
## Grupos de lo que sus ataques dejan en la arena mientras está vivo.
const HAZARD_GROUPS: Array[StringName] = [&"shock_rings", &"telegraph_lanes", &"splash_bursts"]
## Frames tras el evento antes de imprimir "Probe mini stage:", para que el
## desmontaje de la entrada ya haya corrido.
const STAGE_REPORT_FRAMES: int = 2
## Segundos tras su muerte hasta contar lo que dejó vivo.
const AFTERMATH_DELAY: float = 5.0
## Una foto pedida en un frame de física sale del frame SIGUIENTE: la cámara
## vacía su cola antes de que este probe corra. Pedirla con dos frames de
## adelanto captura justo el primer frame que cumple la condición.
const SHOT_LEAD: float = 2.0 / 60.0
## Segundos de cartel en pantalla antes de fotografiarlo.
const TITLE_SHOT_DELAY: float = 0.9
## Segundos de pelea tras los que se toma cada foto de la pelea.
const FIGHT_SHOT_AT: Array[float] = [3.0, 9.0]

var _tree: SceneTree = null
var _camera: ShotCamera = null
var _bound: bool = false
var _state: StringName = &""
var _now: float = 0.0
var _frames: int = 0
var _arrival_from_frame: int = 0
var _fight_from: float = -1.0
var _stage_reports: Array[Dictionary] = []
var _calm_health: Dictionary[int, float] = {}
var _calm_counts: Array[int] = []
## Segundos del probe en cada estado y daño de cada arma por estado.
var _state_seconds: Dictionary[String, float] = {}
var _weapon_damage: Dictionary[String, Dictionary] = {}
var _raider_hits: Dictionary[int, int] = {}
## Fotos ya pedidas en esta entrada o pelea, por nombre.
var _shots_done: Dictionary[String, bool] = {}
## El último estado en que se lo vio pelear: el golpe que lo mata llega con
## el estado ya en "dead" y se anota en este.
var _last_fight_detail: String = ""
## Veces que su Health emitió `died` (tiene que ser una) y a quién se le cuenta.
var _died_signals: int = 0
var _watched_health: Health = null


func _init(host: Node, camera: ShotCamera) -> void:
	_tree = host.get_tree()
	_camera = camera


## Un frame de física del probe. `frames` son los que lleva el probe.
func tick(delta: float, frames: int) -> void:
	_frames = frames
	_now = float(frames) / 60.0
	_bind_once()
	var boss := _mini_boss()
	var state := _state_of(boss)
	if state != _state:
		_on_state_changed(_state, state, boss)
		_state = state
	if not state.is_empty():
		var key := String(_detail_of(boss, state))
		_state_seconds[key] = float(_state_seconds.get(key, 0.0)) + delta
		if state != &"dead" and state != &"arrival":
			_last_fight_detail = key
	if state == &"arrival":
		_tick_entrance_shots()
	elif _fight_from >= 0.0:
		_tick_fight_shots()
	_tick_stage_reports()


## Cambio de etapa: el minijefe y su entrada se fueron con la arena.
func on_stage_changed() -> void:
	_state = &""
	_fight_from = -1.0
	_shots_done.clear()


## Resumen al salir: segundos por estado, daño por arma y golpes por slot.
func summary() -> void:
	if _state_seconds.is_empty():
		return
	var line := "Probe mini states:"
	for key: String in _state_seconds:
		line += " %s=%.1fs" % [key, _state_seconds[key]]
	print(line)
	for weapon_id: String in _weapon_damage:
		var row := _weapon_damage[weapon_id]
		for key: String in row:
			var cell: Dictionary = row[key]
			print("Probe mini damage: weapon=%s state=%s damage=%.0f hits=%d" % [
					weapon_id, key, float(cell["damage"]), int(cell["hits"])])
	var hits := "Probe mini hits on raiders:"
	for slot: int in _raider_hits:
		hits += " p%d=%d" % [slot, _raider_hits[slot]]
	print(hits)


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


func _mini_boss() -> Node3D:
	var boss := _tree.get_first_node_in_group(GROUP) as Node3D
	return boss if boss != null and is_instance_valid(boss) and boss.is_inside_tree() else null


func _state_of(boss: Node3D) -> StringName:
	if boss == null or not boss.has_method(&"fight_state"):
		return &""
	return boss.call(&"fight_state")


## El estado con el nombre del ataque en curso en lugar de "move".
func _detail_of(boss: Node3D, state: StringName) -> StringName:
	if state == &"move" and boss != null and boss.has_method(&"move_name"):
		var move: StringName = boss.call(&"move_name")
		if not move.is_empty():
			return move
	return state


func _on_state_changed(from: StringName, to: StringName, boss: Node3D) -> void:
	if from == &"" and boss != null:
		_watch_death(boss)
	if to == &"arrival":
		_arrival_from_frame = _frames
		_shots_done.clear()
		_calm_health = _health_snapshot(boss)
		_calm_counts = _live_counts()
	elif from == &"arrival" and to == &"":
		print("Probe mini calm: aborted after %d frames (mini boss gone)" % (
				_frames - _arrival_from_frame))
	elif from == &"arrival":
		_report_calm(_frames - _arrival_from_frame, boss)
		_fight_from = _now
		_stage_reports.append({"left": STAGE_REPORT_FRAMES, "reason": "entrance_end"})
	if to == &"dead" and _fight_from >= 0.0:
		print("Probe mini fight: took=%.1fs at %.1fs" % [_now - _fight_from, _now])
		_stage_reports.append({"left": int(AFTERMATH_DELAY * 60.0), "reason": "aftermath"})
		_camera.request_in(1.0, "mini_death_%.0fs" % _now)
	if to == &"dead" or to == &"":
		_fight_from = -1.0


func _on_weapon_damage(weapon: WeaponBase, target: Node3D, amount: float) -> void:
	if target == null or not target.is_in_group(GROUP):
		return
	var weapon_id := WeaponCatalog.id_for_node(String(weapon.name))
	if weapon_id.is_empty():
		weapon_id = String(weapon.name)
	var key := String(_detail_of(target, _state_of(target)))
	if key == "dead" and not _last_fight_detail.is_empty():
		key = _last_fight_detail
	if not _weapon_damage.has(weapon_id):
		_weapon_damage[weapon_id] = {}
	var row := _weapon_damage[weapon_id]
	if not row.has(key):
		row[key] = {"damage": 0.0, "hits": 0}
	var cell: Dictionary = row[key]
	cell["damage"] = float(cell["damage"]) + amount
	cell["hits"] = int(cell["hits"]) + 1


## Cuenta las veces que la vida de este minijefe emite `died`.
func _watch_death(boss: Node3D) -> void:
	var health := Health.find_in(boss)
	if health == null or health == _watched_health:
		return
	_watched_health = health
	_died_signals = 0
	health.died.connect(func() -> void: _died_signals += 1)


func _on_raider_hit(attacker: Node3D, slot: int) -> void:
	if attacker != null and is_instance_valid(attacker) and attacker.is_in_group(GROUP):
		_raider_hits[slot] = int(_raider_hits.get(slot, 0)) + 1


# --- la entrada: nada cambia con el mundo congelado ------------------------------

## Vida de cada cuerpo con Health de la partida, por id de instancia, menos la
## del propio minijefe.
func _health_snapshot(boss: Node3D) -> Dictionary[int, float]:
	var out: Dictionary[int, float] = {}
	for group: StringName in [&"player", &"downed_players", &"enemies", &"boss", &"possessed"]:
		for node: Node in _tree.get_nodes_in_group(group):
			if node == boss:
				continue
			var health := Health.find_in(node)
			if health != null:
				out[health.get_instance_id()] = health.current_hp
	return out


## Cuerpos y proyectiles vivos: enemigos, saetas enemigas y disparos.
func _live_counts() -> Array[int]:
	return [_tree.get_node_count_in_group(&"enemies"),
			_tree.get_node_count_in_group(&"enemy_projectiles"),
			_tree.get_node_count_in_group(&"player_shots")]


func _report_calm(frames: int, boss: Node3D) -> void:
	var after := _health_snapshot(boss)
	var changed := 0
	for id: int in _calm_health:
		if not after.has(id) or not is_equal_approx(after[id], _calm_health[id]):
			changed += 1
	var born := 0
	for id: int in after:
		if not _calm_health.has(id):
			born += 1
	var counts := _live_counts()
	print(("Probe mini calm: frames=%d seconds=%.2f healths=%d changed=%d born=%d"
			+ " enemies=%d->%d bolts=%d->%d shots=%d->%d") % [
			frames, float(frames) / 60.0, _calm_health.size(), changed, born,
			_calm_counts[0], counts[0], _calm_counts[1], counts[1],
			_calm_counts[2], counts[2]])


# --- reportes --------------------------------------------------------------------

func _tick_stage_reports() -> void:
	for index: int in range(_stage_reports.size() - 1, -1, -1):
		var report := _stage_reports[index]
		report["left"] = int(report["left"]) - 1
		if int(report["left"]) <= 0:
			_stage_reports.remove_at(index)
			_print_stage(String(report["reason"]))


## Cómo quedó la pantalla: lo que la entrada toca y tiene que devolver.
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
	print(("Probe mini stage: reason=%s hud_visible=%s split_visible=%s cinematic_camera=%s"
			+ " song_playing=%s world_frozen=%s clock_running=%s") % [
			reason, hud, split, cinematic_camera, _song_playing(), _world_frozen(),
			RunState.is_physics_processing()])
	if reason == "aftermath":
		_print_hazards()


func _song_playing() -> bool:
	for node: Node in _tree.get_nodes_in_group(&"boss_music"):
		var player := node as AudioStreamPlayer
		# has_stream_playback y no `playing`: con el árbol en pausa `playing`
		# lee false aunque la canción siga ahí, esperando.
		if player != null and player.has_stream_playback():
			return true
	return false


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


## Lo que el minijefe dejó en la arena: sus efectos vivos y su propio cuerpo.
func _print_hazards() -> void:
	var line := "Probe mini hazards: reason=aftermath"
	var total := 0
	for group: StringName in HAZARD_GROUPS:
		var count := _tree.get_node_count_in_group(group)
		total += count
		line += " %s=%d" % [group, count]
	print("%s total=%d body=%s song_playing=%s died_signals=%d" % [
			line, total, _mini_boss() != null, _song_playing(), _died_signals])


# --- fotos (solo con BONK_SHOT_DIR) -------------------------------------------------

func _cinematic() -> Node:
	for node: Node in _tree.get_nodes_in_group(&"boss_cinematic"):
		if node.has_method(&"is_calm_active") and bool(node.call(&"is_calm_active")):
			return node
	return null


## Las fotos de la entrada: alrededor del corte, en cada golpe y con el cartel.
func _tick_entrance_shots() -> void:
	if not _camera.enabled():
		return
	var cinematic := _cinematic()
	if cinematic == null or not cinematic.has_method(&"shot_times"):
		return
	var elapsed := float(cinematic.call(&"calm_elapsed"))
	var times: PackedFloat32Array = cinematic.call(&"shot_times")
	if times.is_empty():
		return
	# El último frame de juego, el primero del corte y el que le sigue.
	_shoot_at(elapsed + SHOT_LEAD + 1.0 / 60.0, times[0], "mini_cut_0_last_gameplay")
	_shoot_at(elapsed + SHOT_LEAD, times[0], "mini_cut_1_first")
	_shoot_at(elapsed + SHOT_LEAD - 1.0 / 60.0, times[0], "mini_cut_2_next")
	for index: int in range(1, times.size()):
		_shoot_at(elapsed + SHOT_LEAD, times[index], "mini_hit_%d" % index)
		_shoot_at(elapsed + SHOT_LEAD, times[index] + 0.5, "mini_hit_%d_later" % index)
	if cinematic.has_method(&"title_seconds"):
		_shoot_at(elapsed + SHOT_LEAD, float(cinematic.call(&"title_seconds")) + TITLE_SHOT_DELAY,
				"mini_title")


func _tick_fight_shots() -> void:
	if not _camera.enabled():
		return
	for index: int in FIGHT_SHOT_AT.size():
		_shoot_at(_now - _fight_from, FIGHT_SHOT_AT[index], "mini_fight_%d" % index)


## Pide la foto `stem` la primera vez que `clock` alcanza `due`.
func _shoot_at(clock: float, due: float, stem: String) -> void:
	if clock < due or _shots_done.has(stem):
		return
	_shots_done[stem] = true
	_camera.request(stem)
