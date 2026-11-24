class_name BossArenaProbe
extends RefCounted
## Lo que ArenaProbe observa de un VIAJE a la arena de un jefe
## (BossArenaHost): que mientras el equipo está fuera haya un solo mundo, que
## el mapa de la etapa vuelva tal como salió, y que el equipo no pierda nada.
## Se engancha a las señales del anfitrión; no toca la partida, salvo con
## BONK_TRIP_TAMPER=1 (la corrida de control: mueve un cofre del mapa
## suspendido y revela una celda de niebla, para probar que la comparación
## sabe fallar).
## Imprime:
##   Probe mini world:  where=away|back … cuántos nodos responden a cada grupo
##                      de mundo, cuántos WorldEnvironment hay y cuál es la
##                      arena viva; fuera, además, cuántos marcadores del mapa
##                      de la etapa ve el mapa de Tab
##   Probe mini trip:   snapshot equal=… diffs=… sky=… enemies_left=…  el mapa
##                      de la etapa en el último frame antes de salir contra el
##                      mapa recién vuelto, antes de su primer tick de física
##   Probe mini trip diff: una línea por diferencia
## Lo del equipo (Probe mini party / spots) lo lleva BossPartyProbe y lo de la
## salida (botín, portal, lo que queda después) BossExitProbe.
##   Probe mini tamper: lo que cambió la corrida de control

const TAMPER_ENV: String = "BONK_TRIP_TAMPER"
## Frames tras el evento antes de imprimir "Probe mini world:".
const WORLD_REPORT_FRAMES: int = 90
## Frames fuera antes de que la corrida de control toque el mapa suspendido.
const TAMPER_AFTER_FRAMES: int = 30
## Metros que la corrida de control mueve un cofre.
const TAMPER_SHIFT: float = 2.0
## Tolerancia de posición de la comparación, en metros.
const POSITION_TOLERANCE: float = 0.01
## Grupos de mundo que tienen que responder UNA sola vez.
const WORLD_GROUPS: Array[StringName] = [&"arena_root", &"arena_bounds", &"terrain",
		&"enemy_spawner"]
## Grupos cuyos nodos del mapa de la etapa se comparan por cantidad y posición.
const STAGE_GROUPS: Array[StringName] = [&"scatter_keepout", &"altars", &"map_markers",
		&"vendors", &"pet_boxes", &"lucky_blocks", &"springs", &"acid_pools", &"gems",
		&"health_orbs", &"powerup_pickups", &"possessed"]

var _tree: SceneTree = null
var _host: BossArenaHost = null
var _frames: int = 0
var _tamper: bool = false
var _tamper_at_frame: int = -1
## Reportes "Probe mini world:" pendientes: {at_frame, where}.
var _world_reports: Array[Dictionary] = []
## El mapa de la etapa justo antes de salir, y su cielo de antes del presagio.
var _before: Dictionary = {}
var _sky_before: Dictionary = {}
var _trips: int = 0
## La mitad que mira al equipo: lo que lleva y dónde vuelve.
var _party: BossPartyProbe = null
## La mitad que mira la salida: el botín, el portal y lo que queda después.
var _exit: BossExitProbe = null


func _init(host_node: Node) -> void:
	_tree = host_node.get_tree()
	_tamper = OS.get_environment(TAMPER_ENV) == "1"
	_exit = BossExitProbe.new(_tree)
	_party = BossPartyProbe.new(_tree)


## True mientras el equipo está en la arena de un jefe: el harness no le
## pregunta al relieve del mapa por un mundo que no es el suyo.
func away() -> bool:
	return _host != null and is_instance_valid(_host) and _host.is_away()


## True si el recorrido del probe no debe tocar `spot` (BONK_PORTAL_IGNORE).
func ignores(spot: Node) -> bool:
	return _exit.ignores(spot)


## Un frame de física del probe.
func tick(frames: int) -> void:
	_frames = frames
	_bind_once()
	for index: int in range(_world_reports.size() - 1, -1, -1):
		var report := _world_reports[index]
		# La línea de afuera se toma ya en la pelea: durante la cinemática los
		# mapas se esconden por ella, no por el viaje.
		if frames < int(report["at_frame"]) \
				or (String(report["where"]) == "away" and _cinematic_playing()):
			continue
		_print_world(String(report["where"]))
		_world_reports.remove_at(index)
	if _tamper_at_frame >= 0 and frames >= _tamper_at_frame:
		_tamper_at_frame = -1
		_tamper_stage()
	_party.watch_fight_start(_host)
	_exit.tick(frames)


func summary() -> void:
	if _trips > 0:
		print("Probe mini trips: %d" % _trips)


# --- señales del anfitrión -----------------------------------------------------

func _bind_once() -> void:
	if _host != null:
		return
	_host = BossArenaHost.find(_tree)
	if _host == null:
		return
	_host.omen_beginning.connect(_on_omen_beginning)
	_host.trip_began.connect(_on_trip_began)
	_host.stage_suspending.connect(_on_stage_suspending)
	_host.arena_entered.connect(_on_arena_entered)
	_host.arena_leaving.connect(_exit.on_arena_leaving)
	_host.stage_restored.connect(_on_stage_restored)


## El cielo del mapa justo antes de que el presagio lo toque.
func _on_omen_beginning() -> void:
	_sky_before = _sky_of(RunRoot.stage_parent(_tree))


func _on_trip_began() -> void:
	if _sky_before.is_empty():
		_sky_before = _sky_of(RunRoot.stage_parent(_tree))
	_party.remember()


func _on_stage_suspending(arena: Node3D) -> void:
	_before = _snapshot(arena)


func _on_arena_entered(_arena: Node3D) -> void:
	_trips += 1
	_world_reports.append({"at_frame": _frames + WORLD_REPORT_FRAMES, "where": "away"})
	_party.print_party("arrived")
	if _tamper:
		_tamper_at_frame = _frames + TAMPER_AFTER_FRAMES


## El mapa de la etapa acaba de volver al árbol: todavía no corrió ningún tick.
func _on_stage_restored(arena: Node3D) -> void:
	var after := _snapshot(arena)
	var diffs := _compare(_before, after)
	var enemies := 0
	for group: StringName in [&"enemies", &"boss"]:
		for node: Node in _tree.get_nodes_in_group(group):
			if arena.is_ancestor_of(node) and not node.is_in_group(&"possessed"):
				enemies += 1
	var sky_after := _sky_of(arena)
	var sky_diffs := _compare_sky(_sky_before, sky_after)
	print("Probe mini trip: snapshot equal=%s diffs=%d sky=%s enemies_left=%d weather=%s->%s" % [
			diffs.is_empty(), diffs.size(), "equal" if sky_diffs.is_empty() else "changed",
			enemies, _weather_name(_sky_before), _weather_name(sky_after)])
	for line: String in diffs + sky_diffs:
		print("Probe mini trip diff: %s" % line)
	_party.print_party("back")
	_party.print_spots()
	_world_reports.append({"at_frame": _frames + WORLD_REPORT_FRAMES, "where": "back"})
	_exit.on_stage_restored(_frames)
	_before = {}
	_sky_before = {}


func _weather_name(sky: Dictionary) -> String:
	var id := String(sky.get("weather", ""))
	return id if not id.is_empty() else "none"


# --- un solo mundo ---------------------------------------------------------------

func _print_world(where: String) -> void:
	var line := "Probe mini world: where=%s" % where
	for group: StringName in WORLD_GROUPS:
		line += " %s=%d" % [group, _tree.get_node_count_in_group(group)]
	var live := RunRoot.stage_parent(_tree)
	line += " world_environments=%d live=%s" % [
			_tree.root.find_children("*", "WorldEnvironment", true, false).size(),
			String(live.get("map_id")) if live != null else "none"]
	if where == "away":
		line += " %s" % _map_fields()
	print(line)


## True mientras una cinemática de jefe tiene la pantalla.
func _cinematic_playing() -> bool:
	for node: Node in _tree.get_nodes_in_group(&"boss_cinematic"):
		if node.has_method(&"is_calm_active") and bool(node.call(&"is_calm_active")):
			return true
	return false


## Lo que ven los mapas con el equipo fuera: cuántos marcadores hay en el
## árbol, cuántos son del mapa suspendido (tiene que ser cero), cuántos
## cuenta el mapa de Tab y si el minimapa y el mapa de Tab están a la vista.
func _map_fields() -> String:
	var stage := _host.suspended_arena() if _host != null else null
	var markers := _tree.get_nodes_in_group(&"map_markers")
	var from_stage := 0
	for node: Node in markers:
		if stage != null and stage.is_ancestor_of(node):
			from_stage += 1
	var overlay_markers := -1
	var maps_shown := 0
	for node: Node in _tree.get_nodes_in_group(&"map_overlay"):
		if node.has_method(&"marker_count"):
			overlay_markers = int(node.call(&"marker_count"))
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
			maps_shown += 1
	for node: Node in _tree.root.find_children("*", "Minimap", true, false):
		if (node as CanvasItem).is_visible_in_tree():
			maps_shown += 1
	return "map_markers=%d stage_markers=%d overlay_markers=%d maps_shown=%d" % [
			markers.size(), from_stage, overlay_markers, maps_shown]


# --- la foto del mapa de la etapa -------------------------------------------------

## Todo lo que el viaje no puede cambiar del mapa `arena`, leído de sus nodos vivos.
func _snapshot(arena: Node3D) -> Dictionary:
	var shot := {}
	shot["digest"] = "\n".join(WorldDigest.world_rows(arena)).sha256_text().left(16)
	for group: StringName in STAGE_GROUPS:
		var spots: Dictionary[int, Vector3] = {}
		for node: Node in _tree.get_nodes_in_group(group):
			var body := node as Node3D
			# Los jefes y los raiders tienen marcador de mapa, pero no son del mapa.
			if body == null or not arena.is_ancestor_of(body) or body is BossBase:
				continue
			spots[body.get_instance_id()] = body.global_position
		shot[String(group)] = spots
	var chests: Dictionary[int, Vector3] = {}
	for node: Node in arena.find_children("*", "Area3D", true, false):
		if node is Chest and not node.is_queued_for_deletion():
			chests[node.get_instance_id()] = (node as Chest).global_position
	shot["chests"] = chests
	var fog := FogOfWar.find(_tree)
	if fog != null:
		shot["fog_fraction"] = fog.explored_fraction()
		shot["fog_pixels"] = fog.pixels()
		shot["fog_image"] = hash(fog.image.get_data())
	var director := _tree.get_first_node_in_group(&"world_director")
	if director != null and director.has_method(&"stage_clock"):
		var clock: Dictionary = director.call(&"stage_clock")
		for key: String in clock:
			shot[key] = clock[key]
	shot["stage_index"] = RunState.stage_index
	shot["lap"] = RunState.lap
	shot["stage_boss_dead"] = RunState.stage_boss_dead
	shot["stage_cleared"] = RunState.stage_cleared
	return shot


## Las diferencias entre dos fotos, una línea cada una (vacío = iguales).
func _compare(before: Dictionary, after: Dictionary) -> Array[String]:
	var diffs: Array[String] = []
	if before.is_empty():
		diffs.append("no snapshot from before the trip")
		return diffs
	for key: Variant in before:
		var was: Variant = before[key]
		var now: Variant = after.get(key)
		if was is Dictionary:
			diffs.append_array(_compare_spots(String(key), was, now if now is Dictionary else {}))
		elif was is float:
			if now == null or not is_equal_approx(float(was), float(now)):
				diffs.append("%s %s -> %s" % [key, was, now])
		elif was != now:
			diffs.append("%s %s -> %s" % [key, was, now])
	return diffs


func _compare_spots(what: String, before: Dictionary, after: Dictionary) -> Array[String]:
	var diffs: Array[String] = []
	if before.size() != after.size():
		diffs.append("%s count %d -> %d" % [what, before.size(), after.size()])
	for id: Variant in before:
		if not after.has(id):
			diffs.append("%s lost one at %v" % [what, before[id]])
			continue
		var moved := (before[id] as Vector3).distance_to(after[id] as Vector3)
		if moved > POSITION_TOLERANCE:
			diffs.append("%s moved %.2fm from %v to %v" % [what, moved, before[id], after[id]])
	for id: Variant in after:
		if not before.has(id):
			diffs.append("%s gained one at %v" % [what, after[id]])
	return diffs


## El cielo de `arena` (vacío sin arena): lo que se ve (sol, ambiente, niebla
## y colores del cielo), el cielo «original» que guarda el clima (base_*, sin
## el tinte del clima en curso) y qué clima corre.
func _sky_of(arena: Node) -> Dictionary:
	var sky := {}
	if arena == null:
		return sky
	for node: Node in arena.find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		sky["sun_color"] = sun.light_color
		sky["sun_energy"] = sun.light_energy
		break
	for node: Node in arena.find_children("*", "WorldEnvironment", true, false):
		var environment := (node as WorldEnvironment).environment
		if environment != null:
			sky["ambient_color"] = environment.ambient_light_color
			sky["ambient_energy"] = environment.ambient_light_energy
			sky["fog_color"] = environment.fog_light_color
			sky["fog_density"] = environment.fog_density
			var material := environment.sky.sky_material as ProceduralSkyMaterial \
					if environment.sky != null else null
			if material != null:
				sky["sky_top"] = material.sky_top_color
				sky["sky_horizon"] = material.sky_horizon_color
		break
	var director := _tree.get_first_node_in_group(&"world_director")
	if director != null and director.has_method(&"sky_base"):
		var base: Dictionary = director.call(&"sky_base")
		for key: Variant in base:
			sky["base_%s" % key] = base[key]
		sky["weather"] = String((director.call(&"stage_clock") as Dictionary)["weather_id"])
	return sky


## Qué del cielo no volvió a como estaba antes del presagio. El clima tiñe el
## sol y el ambiente por su cuenta y puede empezar o terminar en el camino
## (el harness mismo fuerza una luna a los 5 s de cada etapa), así que lo que
## se compara es el cielo «original» sin clima, más la niebla y los colores
## del cielo, que el clima no toca. Sin clima al volver, además, lo que se ve
## tiene que ser ese cielo original.
func _compare_sky(before: Dictionary, after: Dictionary) -> Array[String]:
	var diffs: Array[String] = []
	for key: String in ["base_sun_color", "base_sun_energy", "base_ambient_color",
			"base_ambient_energy", "fog_color", "fog_density", "sky_top", "sky_horizon"]:
		if not _same(before.get(key), after.get(key)):
			diffs.append("sky %s %s -> %s" % [key, before.get(key), after.get(key)])
	if String(after.get("weather", "")).is_empty():
		for key: String in ["sun_color", "sun_energy", "ambient_color", "ambient_energy"]:
			if not _same(after.get(key), after.get("base_%s" % key)):
				diffs.append("sky %s shows %s with no weather, base is %s" % [
						key, after.get(key), after.get("base_%s" % key)])
	return diffs


func _same(a: Variant, b: Variant) -> bool:
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b as Color)
	if a is float and b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


# --- la corrida de control ---------------------------------------------------------

## BONK_TRIP_TAMPER: con el equipo fuera, mueve un cofre del mapa suspendido
## y revela una celda de niebla. La comparación de la vuelta tiene que decirlo.
func _tamper_stage() -> void:
	var stage := _host.suspended_arena() if _host != null else null
	if stage == null:
		return
	var moved := "no chest"
	for node: Node in stage.find_children("*", "Area3D", true, false):
		if node is Chest:
			(node as Chest).position.x += TAMPER_SHIFT
			moved = "chest by %.1fm" % TAMPER_SHIFT
			break
	var revealed := "nothing"
	var fog := FogOfWar.find(_tree)
	if fog != null:
		var half := fog.half_extent()
		var step := 10.0
		var x := -half + step
		while x < half and revealed == "nothing":
			var z := -half + step
			while z < half:
				if not fog.is_explored(Vector2(x, z)):
					fog.reveal_at(Vector2(x, z))
					revealed = "fog at (%.0f, %.0f)" % [x, z]
					break
				z += step
			x += step
	print("Probe mini tamper: moved %s, revealed %s" % [moved, revealed])
