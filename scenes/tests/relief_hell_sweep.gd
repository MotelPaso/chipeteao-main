class_name ReliefHellSweep
extends RefCounted
## El barrido `hell` de una arena con relieve por zonas (ReliefSweeps lo corre
## cuando el bosque de afuera avisa que terminó): las mallas que el infierno
## de Mythos dejaría sin quemar, por tipo, en una línea `Relief sweep: hell`.
## `unburnt` es lo que quedaría verde en un bosque en llamas: tiene que dar 0.

## Muestras con nombre cuando el resto no da cero.
const DETAIL_LIMIT: int = ReliefPlacement.DETAIL_LIMIT


## Las mallas que HellDressing no quemaría, por tipo: bajo un Interactable
## (no arden a propósito), bajo el Backdrop con un StandardMaterial3D (las
## tiñe HellSky; con otro material quedarían verdes y cuentan como resto), las
## de un cuerpo vivo, las de algo que salió del pool (un dardo en vuelo, una
## gema: Pools los cuelga de la arena), los efectos de un solo uso y el
## resto, que es lo que quedaría verde en el infierno. La geometría que no es
## un MeshInstance3D bajo el Backdrop o el bosque de afuera (una MultiMesh,
## partículas) tampoco se quema ni se tiñe: cuenta como resto.
static func run(tree: SceneTree, arena: Node3D, terrain: Terrain) -> void:
	var burning: Dictionary[int, bool] = {}
	for child: Node in terrain.find_children("*", "MeshInstance3D", true, false):
		var view := child as MeshInstance3D
		var material := view.material_override as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.resource_path == WorldDigest.GROUND_SHADER_PATH:
			burning[view.get_instance_id()] = true
	for group: StringName in WorldDigest.PROP_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			if not arena.is_ancestor_of(node) or node is Interactable:
				continue
			for child: Node in node.find_children("*", "MeshInstance3D", true, false):
				if WorldDigest._prop_burns(child as MeshInstance3D):
					burning[child.get_instance_id()] = true
	var backdrop := terrain.get_node_or_null(terrain.backdrop_path)
	var counts := {"interactable": 0, "backdrop": 0, "body": 0, "pooled": 0, "fx": 0, "other": 0}
	var skipped := 0
	var notes: Array[String] = []
	for child: Node in arena.find_children("*", "MeshInstance3D", true, false):
		if burning.has(child.get_instance_id()):
			continue
		skipped += 1
		var kind := _hell_kind(arena, child, backdrop)
		counts[kind] = int(counts[kind]) + 1
		if kind == "other" and notes.size() < DETAIL_LIMIT:
			notes.append(String(arena.get_path_to(child)))
	for root: Node in _outside_roots(tree, arena, backdrop):
		for child: Node in root.find_children("*", "GeometryInstance3D", true, false):
			if child is MeshInstance3D:
				continue
			skipped += 1
			counts["other"] = int(counts["other"]) + 1
			if notes.size() < DETAIL_LIMIT:
				notes.append("%s (%s)" % [arena.get_path_to(child), child.get_class()])
	print(("Relief sweep: hell skipped=%d interactable=%d backdrop=%d bodies=%d pooled=%d"
			+ " fx=%d unburnt=%d") % [skipped, counts["interactable"], counts["backdrop"],
			counts["body"], counts["pooled"], counts["fx"], counts["other"]])
	for note: String in notes:
		print("Relief sweep detail: hell unburnt %s" % note)


## Lo que la arena tiene afuera del muro y no arde por sí solo: el Backdrop
## y el bosque de afuera (grupo forest_edge).
static func _outside_roots(tree: SceneTree, arena: Node3D, backdrop: Node) -> Array[Node]:
	var roots: Array[Node] = []
	if backdrop != null:
		roots.append(backdrop)
	for node: Node in tree.get_nodes_in_group(&"forest_edge"):
		if arena.is_ancestor_of(node):
			roots.append(node)
	return roots


## El tipo de una malla que no arde (ver run): "other" si es parte del
## mapa y quedaría verde en el infierno.
static func _hell_kind(arena: Node3D, mesh: Node, backdrop: Node) -> String:
	# Un efecto de un solo uso (WeaponBase.spawn_fx_mesh, el anillo de nivel de
	# Juice) es una malla sin nombre ni dueño colgada directo de la arena: dura
	# un instante y no es parte del mapa.
	if mesh.get_parent() == arena and mesh.owner == null \
			and String(mesh.name).begins_with("@"):
		return "fx"
	# Desde la malla misma: un destello del pool ES un MeshInstance3D y lleva
	# la marca del pool en él, no en un padre.
	var up: Node = mesh
	while up != null and up != arena:
		if up is Interactable:
			return "interactable"
		# Bajo el Backdrop solo HellSky tiñe un StandardMaterial3D puesto como
		# override; con otro material la malla quedaría verde.
		if up == backdrop:
			return "backdrop" if (mesh as MeshInstance3D).material_override is StandardMaterial3D \
					else "other"
		# Un cuerpo vivo (la horda que ya apareció) no es parte del mapa.
		if up is CharacterBody3D:
			return "body"
		# Tampoco lo que NodePool creó: lleva su marca desde que nace.
		if up.has_meta(NodePool.META_OWNER):
			return "pooled"
		up = up.get_parent()
	return "other"
