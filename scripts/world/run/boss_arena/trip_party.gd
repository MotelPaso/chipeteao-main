class_name TripParty
extends RefCounted
## El EQUIPO durante un viaje a la arena de un jefe (lo usa BossArenaHost):
## dónde estaba cada raider cuando se lo llevaron, cómo vuelve a ese lugar, y
## lo que cada raider tiene que soltar o volver a publicar cuando el mundo bajo
## sus pies cambia sin cambiar de etapa.
## Llega a los raiders SIEMPRE por sus grupos ("player" y "downed_players") y
## por nombre: no conoce a Player, así sirve igual con un cuerpo de prueba.

## Capa de colisión del mundo: el suelo bajo cada raider se busca en ella.
const WORLD_LAYER: int = 1
## Metros hacia abajo que se busca el suelo bajo un raider al partir.
const FLOOR_PROBE_DEPTH: float = 80.0
## Metros sobre los pies desde los que sale ese rayo.
const FLOOR_PROBE_LIFT: float = 0.5

var _tree: SceneTree = null
## Dónde estaba cada raider al partir, por id de instancia: {at, floor_y, flying}.
var _spots: Dictionary[int, Dictionary] = {}


func _init(tree: SceneTree) -> void:
	_tree = tree


## Los raiders, de pie y caídos.
func bodies() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in _tree.get_nodes_in_group(group):
			var body := node as Node3D
			if body != null:
				found.append(body)
	return found


## True si queda algún raider en pie y con vida. Una partida que termina con
## alguien vivo fue una extracción; sin nadie, una derrota. Se mira la vida y
## no solo el grupo: en una partida de uno, el caído sigue en "player".
func anyone_alive() -> bool:
	for node: Node in _tree.get_nodes_in_group(&"player"):
		var health := Health.find_in(node)
		if health != null and not health.is_dead:
			return true
	return false


## Anota dónde está cada raider y qué suelo tiene debajo: ahí vuelve. Se
## llama con el mapa todavía vivo, que es cuando el suelo se puede medir.
func remember() -> void:
	_spots.clear()
	for body: Node3D in bodies():
		_spots[body.get_instance_id()] = {
			"at": body.global_position,
			"floor_y": _floor_under(body),
			"flying": _is_flying(body),
		}


## Dónde quedó anotado `body`, o INF si no estaba cuando partieron (lo lee el harness).
func spot_of(body: Node3D) -> Vector3:
	var spot: Dictionary = _spots.get(body.get_instance_id(), {})
	return spot["at"] if not spot.is_empty() else Vector3.INF


func forget() -> void:
	_spots.clear()


## Devuelve a cada raider a donde lo tomaron, apoyado en el suelo que tenía
## debajo (o a su altura, si iba volando y sigue volando), y ancla ahí su
## rescate del vacío. Quien no estaba cuando partieron va junto al primero.
func place_back() -> void:
	var strays: Array[Node3D] = []
	for body: Node3D in bodies():
		var spot: Dictionary = _spots.get(body.get_instance_id(), {})
		if spot.is_empty():
			strays.append(body)
			continue
		var at: Vector3 = spot["at"]
		if not (bool(spot["flying"]) and _is_flying(body)):
			at.y = float(spot["floor_y"])
		_put(body, at)
	if strays.is_empty() or _spots.is_empty():
		return
	var first: Dictionary = _spots.values()[0]
	for body: Node3D in strays:
		_put(body, Vector3(first["at"].x, float(first["floor_y"]), first["at"].z))


## Las armas que dejan campos en el suelo (charcos) los sueltan: sus visuales
## cuelgan de la arena que se va y sus registros viajan con el raider. Es el
## mismo contrato por nombre de una caída (clear_weapon_fields).
func clear_weapon_fields() -> void:
	for body: Node3D in bodies():
		var mount := body.get_node_or_null(^"Weapons")
		if mount == null:
			continue
		for weapon: Node in mount.get_children():
			if weapon.has_method(&"clear_weapon_fields"):
				weapon.call(&"clear_weapon_fields")


## El mundo bajo cada raider cambió: sus power-ups vuelven a publicar su
## estado (el Tiempo detenido pasa al spawner de la arena viva).
func notify_world_changed() -> void:
	for body: Node3D in bodies():
		var powerups := PowerUps.find_in(body)
		if powerups != null:
			powerups.world_changed()


## Las gemas y los orbes vivos bajo `arena` van al equipo: se recogen ya, sin
## vuelo, cada uno para el raider en pie más cercano.
func collect_loot(arena: Node) -> void:
	if arena == null:
		return
	for group: StringName in [XpGem.LIVE_GROUP, HealthOrb.LIVE_GROUP]:
		for node: Node in _tree.get_nodes_in_group(group):
			var pickup := node as MagnetPickup
			if pickup == null or not arena.is_ancestor_of(pickup):
				continue
			var collector := Coop.nearest_player(_tree, pickup.global_position)
			if collector != null:
				pickup.collect(collector)


func _put(body: Node3D, at: Vector3) -> void:
	body.global_position = at
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	if body.has_method(&"anchor_here"):
		body.call(&"anchor_here")


## La altura del suelo bajo `body`: lo primero que hay en la capa del mundo
## (el terreno, un puente, una meseta), sin contar a los raiders.
func _floor_under(body: Node3D) -> float:
	var space := body.get_world_3d().direct_space_state if body.is_inside_tree() else null
	if space != null:
		var skip: Array[RID] = []
		for raider: Node3D in bodies():
			if raider is CollisionObject3D:
				skip.append((raider as CollisionObject3D).get_rid())
		var from := body.global_position + Vector3.UP * FLOOR_PROBE_LIFT
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				from, from + Vector3.DOWN * FLOOR_PROBE_DEPTH, WORLD_LAYER, skip))
		if not hit.is_empty():
			return (hit["position"] as Vector3).y
	var terrain := Terrain.find(_tree)
	if terrain != null:
		return terrain.height_at(body.global_position.x, body.global_position.z)
	return body.global_position.y


func _is_flying(body: Node) -> bool:
	var powerups := PowerUps.find_in(body)
	return powerups != null and powerups.has("flight")
