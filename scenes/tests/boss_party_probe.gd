class_name BossPartyProbe
extends RefCounted
## Lo que ArenaProbe observa del EQUIPO en un viaje a la arena de un jefe (la
## mitad de BossArenaProbe que mira a los raiders): que nadie pierda nada de
## lo que llevaba al partir y que cada uno vuelva a donde lo tomaron.
## Imprime:
##   Probe mini party:  at=arrived|fight|back … lo que lleva cada raider
##                      contra lo que llevaba al partir; en "fight", además,
##                      que cada power-up que corría siga con lo que le quedaba
##   Probe mini party lost: una línea por cosa perdida
##   Probe mini spots:  dónde quedó cada raider al volver

## Segundos que puede diferir lo que le queda a un power-up al empezar la pelea.
const POWERUP_TOLERANCE: float = 0.1
## Metros, en planta, que un raider puede quedar de donde lo tomaron.
const SPOT_TOLERANCE: float = 1.0
## Metros que puede quedar del suelo que pisaba (si no va volando).
const FLOOR_TOLERANCE: float = 0.15

var _tree: SceneTree = null
## Lo que llevaba cada raider al partir y dónde estaba, por id de instancia.
var _carry: Dictionary[int, Dictionary] = {}
var _spots: Dictionary[int, Dictionary] = {}
var _level_before: int = 0
var _fight_checked: bool = false


func _init(tree: SceneTree) -> void:
	_tree = tree


## El viaje empieza: anota lo que lleva cada raider y dónde está.
func remember() -> void:
	_carry.clear()
	_spots.clear()
	_fight_checked = false
	_level_before = RunState.level
	for body: Node3D in _party():
		var id := body.get_instance_id()
		_carry[id] = _carry_of(body)
		_spots[id] = {"at": body.global_position, "floor_y": _floor_under(body),
				"flying": _is_flying(body)}


# --- el equipo --------------------------------------------------------------------

func _party() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in _tree.get_nodes_in_group(group):
			if node is Node3D:
				bodies.append(node as Node3D)
	return bodies


## Lo que lleva un raider: armas, tomos, objetos, puntos, mascota y power-ups.
func _carry_of(body: Node) -> Dictionary:
	var weapons := 0
	var mount := body.get_node_or_null(^"Weapons")
	if mount != null:
		for child: Node in mount.get_children():
			if child is WeaponBase:
				weapons += 1
	var stats := PlayerStats.find_in(body)
	var bag := ItemBag.find_in(body)
	var powerups := PowerUps.find_in(body)
	var running: Dictionary[String, float] = {}
	if powerups != null:
		for row: Dictionary in powerups.active():
			running[String(row["id"])] = float(row["time_left"])
	var purse: Variant = body.get("points")
	var pet: Variant = body.get("pet_id")
	return {
		"weapons": weapons,
		"tomes": stats.distinct_tome_count() if stats != null else 0,
		"items": bag.carried_ids().size() if bag != null else 0,
		"points": int(purse) if purse != null else 0,
		"pet": String(pet) if pet != null else "",
		"powerups": running,
	}


## Compara lo que lleva cada raider con lo que llevaba al partir: nada baja.
## En "fight" además cada power-up que corría sigue corriendo con lo que le quedaba.
func print_party(at: String) -> void:
	var lost: Array[String] = []
	var powerups := "n/a"
	for body: Node3D in _party():
		var was: Dictionary = _carry.get(body.get_instance_id(), {})
		if was.is_empty():
			continue
		var now := _carry_of(body)
		var slot := int(body.get("player_index"))
		for key: String in ["weapons", "tomes", "items", "points"]:
			if int(now[key]) < int(was[key]):
				lost.append("p%d %s %d -> %d" % [slot, key, was[key], now[key]])
		if String(was["pet"]) != "" and String(now["pet"]) != String(was["pet"]):
			lost.append("p%d pet %s -> %s" % [slot, was["pet"], now["pet"]])
		if at != "fight":
			continue
		var before: Dictionary = was["powerups"]
		var after: Dictionary = now["powerups"]
		for id: Variant in before:
			if powerups == "n/a":
				powerups = "kept"
			if not after.has(id) or absf(float(after[id]) - float(before[id])) > POWERUP_TOLERANCE:
				powerups = "changed"
				lost.append("p%d power-up %s %.2fs -> %s" % [slot, id, before[id],
						("%.2fs" % float(after[id])) if after.has(id) else "gone"])
	if RunState.level < _level_before:
		lost.append("level %d -> %d" % [_level_before, RunState.level])
	print("Probe mini party: at=%s raiders=%d lost=%d powerups=%s" % [
			at, _party().size(), lost.size(), powerups])
	for line: String in lost:
		print("Probe mini party lost: %s" % line)


## El primer frame de la pelea: los power-ups que corrían al partir siguen igual.
func watch_fight_start(_host: BossArenaHost) -> void:
	if _fight_checked or _host == null or not _host.is_away():
		return
	var boss := _host.boss()
	if boss == null or not boss.has_method(&"fight_state"):
		return
	var state := String(boss.call(&"fight_state"))
	if state == "arrival" or state == "":
		return
	_fight_checked = true
	print_party("fight")


## Dónde quedó cada raider al volver: cerca de donde lo tomaron, sobre el
## suelo que pisaba (si no vuela) y con su rescate del vacío anclado ahí.
func print_spots() -> void:
	var moved_max := 0.0
	var off_floor := 0
	var unanchored := 0
	var bodies := _party()
	for body: Node3D in bodies:
		var was: Dictionary = _spots.get(body.get_instance_id(), {})
		if was.is_empty():
			continue
		var from: Vector3 = was["at"]
		var here := body.global_position
		moved_max = maxf(moved_max, Vector2(here.x - from.x, here.z - from.z).length())
		if not _is_flying(body) and absf(here.y - float(was["floor_y"])) > FLOOR_TOLERANCE:
			off_floor += 1
		var anchor: Variant = body.get("_spawn_position")
		if anchor is Vector3 and (anchor as Vector3).distance_to(here) > FLOOR_TOLERANCE:
			unanchored += 1
	print("Probe mini spots: raiders=%d moved_max=%.2fm within=%s off_floor=%d unanchored=%d" % [
			bodies.size(), moved_max, moved_max <= SPOT_TOLERANCE, off_floor, unanchored])


## La altura del suelo bajo `body` (lo primero en la capa del mundo, sin raiders).
func _floor_under(body: Node3D) -> float:
	var skip: Array[RID] = []
	for raider: Node3D in _party():
		if raider is CollisionObject3D:
			skip.append((raider as CollisionObject3D).get_rid())
	var from := body.global_position + Vector3.UP * 0.5
	var hit := body.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 80.0, 1, skip))
	return (hit["position"] as Vector3).y if not hit.is_empty() else body.global_position.y


func _is_flying(body: Node) -> bool:
	var powerups := PowerUps.find_in(body)
	return powerups != null and powerups.has("flight")
