class_name BossExitProbe
extends RefCounted
## Lo que ArenaProbe observa de la SALIDA de la arena de un jefe (la mitad de
## BossArenaProbe que mira el final del viaje): dónde quedó el botín, dónde se
## abrió el portal, cuánto estuvo abierto y qué quedó vivo después.
## Solo observa, salvo BONK_PORTAL_IGNORE=1: con ella el recorrido del probe
## no toma el portal, para que se cierre solo (la otra forma de volver).
## Imprime:
##   Probe mini loot:      al abrirse el portal, el botín que hay en la arena
##                         y cuánto cayó donde no se puede pisar (off_sand)
##   Probe mini portal:    al abrirse: si está en un lugar colocable, a cuánto
##                         de coberturas y borde, si la flecha del HUD le
##                         apunta y lo que dice su cuenta
##   Probe mini portal closed: al irse la arena: por qué se salió (portal,
##                         timeout o abandoned, si el viaje no vuelve), los
##                         segundos de JUEGO que estuvo abierto, lo que marcaba
##                         su cuenta y cuántos raiders iban caídos
##   Probe mini return loot: gemas y orbes que quedaron sin repartir (0) y
##                         cofres sin abrir que se perdieron con la arena
##   Probe mini leftovers: tras la vuelta, lo que queda vivo del viaje (0)

const IGNORE_ENV: String = "BONK_PORTAL_IGNORE"
## Grupos del botín que se reparte al volver.
const PICKUP_GROUPS: Array[StringName] = [&"gems", &"health_orbs"]
## Frames tras la vuelta antes de contar lo que quedó vivo.
const LEFTOVER_FRAMES: int = 3

var _tree: SceneTree = null
var _ignore: bool = false
## El portal visto, el segundo de etapa en que se abrió y lo que marcaba.
var _portal: BossArenaPortal = null
var _opened_at: float = 0.0
var _opened_left: float = 0.0
var _leftovers_at: int = -1


func _init(tree: SceneTree) -> void:
	_tree = tree
	_ignore = OS.get_environment(IGNORE_ENV) == "1"


## True si el recorrido del probe no debe tocar `spot`.
func ignores(spot: Node) -> bool:
	return _ignore and spot is BossArenaPortal


## Un frame de física del probe.
func tick(frames: int) -> void:
	if _portal == null or not is_instance_valid(_portal):
		_portal = _tree.get_first_node_in_group(BossArenaPortal.GROUP) as BossArenaPortal
		if _portal != null:
			_on_portal_opened()
	if _leftovers_at >= 0 and frames >= _leftovers_at:
		_leftovers_at = -1
		_print_leftovers()


## La arena del jefe está por liberarse (todavía está en el árbol).
func on_arena_leaving(arena: Node3D) -> void:
	var left: Array[int] = []
	for group: StringName in PICKUP_GROUPS:
		var count := 0
		for node: Node in _tree.get_nodes_in_group(group):
			if arena.is_ancestor_of(node) and (node as Node3D).visible:
				count += 1
		left.append(count)
	var chests := 0
	for node: Node in SuspendedStage.descendants(arena):
		if node is Chest and (node as Interactable).available:
			chests += 1
	print("Probe mini return loot: gems_left=%d orbs_left=%d chests_lost=%d" % [left[0], left[1],
			chests])
	if _portal != null and is_instance_valid(_portal):
		var marked := _portal.seconds_left()
		var host := BossArenaHost.find(_tree)
		var reason := "abandoned"
		if host != null and host.phase_name() == &"returning":
			reason = "timeout" if marked <= 0.0 else "portal"
		print(("Probe mini portal closed: reason=%s open_for=%.1fs countdown=%.1fs of %.0fs"
				+ " downed=%d") % [reason, RunState.stage_time - _opened_at, marked, _opened_left,
				_tree.get_node_count_in_group(&"downed_players")])
	_portal = null


## El mapa de la etapa volvió: en unos frames se cuenta lo que quedó del viaje.
func on_stage_restored(frames: int) -> void:
	_leftovers_at = frames + LEFTOVER_FRAMES


# --- privados ---------------------------------------------------------------------

func _on_portal_opened() -> void:
	_opened_at = RunState.stage_time
	_opened_left = _portal.seconds_left()
	var bounds := _tree.get_first_node_in_group(&"arena_bounds") as BossField
	var arena := RunRoot.stage_parent(_tree)
	_print_loot(arena, bounds)
	var at := Vector2(_portal.global_position.x, _portal.global_position.z)
	# La flecha de objetivo del HUD (BossArrow) guarda a qué apunta.
	var arrow := false
	for node: Node in _tree.root.find_children("*", "BossArrow", true, false):
		if node.get("_objective") == _portal:
			arrow = true
	print(("Probe mini portal: can_place=%s cover_gap=%.1f rim_gap=%.1f arrow=%s closes_in=%.1fs"
			+ " prompt=%s") % [bounds != null and bounds.can_place(at),
			bounds.cover_distance(at) if bounds != null else -1.0,
			bounds.clearing_radius - at.length() if bounds != null else -1.0, arrow,
			_opened_left, _portal.available])


## El botín que hay en la arena y cuánto quedó donde no se puede pisar.
func _print_loot(arena: Node, bounds: BossField) -> void:
	var counts := {"chests": 0, "gems": 0, "orbs": 0, "pickups": 0}
	var off_sand := 0
	var spots: Array[Vector3] = []
	for node: Node in SuspendedStage.descendants(arena):
		var kind := ""
		if node is Chest:
			kind = "chests"
		elif node.is_in_group(&"gems"):
			kind = "gems"
		elif node.is_in_group(&"health_orbs"):
			kind = "orbs"
		elif node.is_in_group(&"powerup_pickups"):
			kind = "pickups"
		if kind.is_empty() or not (node as Node3D).visible:
			continue
		counts[kind] = int(counts[kind]) + 1
		spots.append((node as Node3D).global_position)
	for spot: Vector3 in spots:
		if bounds != null and not bounds.is_walkable(Vector2(spot.x, spot.z)):
			off_sand += 1
	print("Probe mini loot: chests=%d gems=%d orbs=%d pickups=%d off_sand=%d" % [counts.chests,
			counts.gems, counts.orbs, counts.pickups, off_sand])


func _print_leftovers() -> void:
	var boss_arenas := 0
	for node: Node in _tree.get_nodes_in_group(&"arena_root"):
		if node is BossArena:
			boss_arenas += 1
	print("Probe mini leftovers: boss_arenas=%d cinematics=%d portals=%d tides=%d covers=%d" % [
			boss_arenas, _tree.get_node_count_in_group(&"boss_cinematic"),
			_tree.get_node_count_in_group(BossArenaPortal.GROUP),
			_tree.get_node_count_in_group(&"lobster_tide"),
			_tree.get_node_count_in_group(BossField.COVER_GROUP)])
