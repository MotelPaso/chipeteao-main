class_name LobsterEntranceSight
extends RefCounted
## La VISTA LIBRE de la cinemática de la Langosta Azul (lo usa
## LobsterEntranceCamera): junta la decoración del mapa que podría tapar un
## plano, esconde la que cruza la vista mientras dura ese plano y cuenta lo
## que sigue estorbando. Nada del mapa puede taparle la cara a la langosta ni
## esconder a un raider en su propio rapto.
## Lo sólido y grande (el suelo, una meseta, una cobertura) no se esconde: de
## eso se ocupa quien arma los planos, y aquí solo se cuenta.

## Grupos de un mapa de etapa de los que cuelga su decoración.
const SCENERY_GROUPS: Array[StringName] = [&"arena_bounds", &"scatter_keepout"]
## Radio, en metros, con que se cuenta un raider o un enemigo que cruza la vista.
const BODY_RADIUS: float = 1.0

## Metros alrededor de cada línea de vista que tienen que quedar libres.
var clearance: float = 1.0
## La decoración de más de estos metros de radio nunca se esconde.
var hide_radius_limit: float = 9.0

var _tree: SceneTree = null
## Cada entrada es [malla, centro en el mundo, radio].
var _scenery: Array[Array] = []
## Lo que el plano en curso escondió, para devolverlo cuando termine.
var _hidden: Array[Node3D] = []


func _init(tree: SceneTree) -> void:
	_tree = tree


## Junta la decoración del mundo vivo: en un mapa de etapa, la que cuelga de
## sus grupos de decoración; en la arena de un jefe (`arena`), todas sus
## mallas menos las del propio jefe (`boss`). `keep` es un punto sobre el que
## no se esconde nada (los pies de a quien se filma).
func collect(arena: Node3D, keep: Vector3, boss: Node3D) -> void:
	_scenery.clear()
	var holders: Array[Node] = []
	if arena is BossArena:
		holders.append(arena)
	else:
		for group: StringName in SCENERY_GROUPS:
			holders.append_array(_tree.get_nodes_in_group(group))
	for holder: Node in holders:
		for node: Node in holder.find_children("*", "MeshInstance3D", true, false):
			var view := node as MeshInstance3D
			if view.mesh == null or (boss != null and boss.is_ancestor_of(view)):
				continue
			var box := view.get_aabb()
			var stretch := view.global_basis.get_scale()
			# El radio es la mitad de su lado más largo: para una copa, lo que tapa.
			var radius := maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.5 \
					* maxf(stretch.x, maxf(stretch.y, stretch.z))
			var center := view.global_transform * box.get_center()
			if radius <= hide_radius_limit and center.distance_to(keep) > radius:
				_scenery.append([view, center, radius])


## Esconde lo que cruza la vista entre algún punto de `eyes` y alguno de
## `targets`: decoración y enemigos congelados (menos `boss`).
func hide_crossing(eyes: Array[Vector3], targets: Array[Vector3], boss: Node3D) -> void:
	for entry: Array in _scenery:
		var view := entry[0] as MeshInstance3D
		if not is_instance_valid(view) or not view.visible:
			continue
		if crosses(entry[1], float(entry[2]), eyes, targets):
			view.visible = false
			_hidden.append(view)
	for node: Node in _tree.get_nodes_in_group(&"enemies"):
		var body := node as EnemyBase
		if body == null or body == boss or not body.visible:
			continue
		if crosses(body.aim_point(), BODY_RADIUS, eyes, targets):
			body.visible = false
			_hidden.append(body)


## Cuántas cosas siguen estorbando la vista entre `eyes` y `targets` después
## de esconder lo que se puede: raiders (`raiders`), coberturas de la arena
## (`covers`: sus contornos en el suelo) y decoración que quedó a la vista.
func blocking(eyes: Array[Vector3], targets: Array[Vector3], raiders: Array[Node3D],
		covers: Array[PackedVector2Array]) -> int:
	var count := 0
	for entry: Array in _scenery:
		var view := entry[0] as MeshInstance3D
		if is_instance_valid(view) and view.visible \
				and crosses(entry[1], float(entry[2]), eyes, targets):
			count += 1
	for raider: Node3D in raiders:
		if is_instance_valid(raider) and crosses(
				raider.global_position + Vector3.UP * BODY_RADIUS, BODY_RADIUS, eyes, targets):
			count += 1
	for outline: PackedVector2Array in covers:
		if _outline_crosses(outline, eyes, targets):
			count += 1
	return count


## Devuelve a la vista lo que el plano anterior escondió.
func show_hidden() -> void:
	for node: Node3D in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()


func hidden_count() -> int:
	return _hidden.size()


## Suelta todo: lo escondido vuelve y la decoración juntada se olvida.
func clear() -> void:
	show_hidden()
	_scenery.clear()


## True si una esfera de `radius` metros en `center` queda a menos de
## `clearance` de alguna línea entre un punto de `eyes` y uno de `targets`.
func crosses(center: Vector3, radius: float, eyes: Array[Vector3],
		targets: Array[Vector3]) -> bool:
	var reach := radius + clearance
	for eye: Vector3 in eyes:
		for target: Vector3 in targets:
			var line := target - eye
			var along := clampf((center - eye).dot(line) / maxf(line.length_squared(), 0.0001),
					0.0, 1.0)
			if center.distance_to(eye + line * along) < reach:
				return true
	return false


## True si alguna línea de vista pasa, en planta, por el contorno `outline` de
## una cobertura o a menos de `clearance` de él.
func _outline_crosses(outline: PackedVector2Array, eyes: Array[Vector3],
		targets: Array[Vector3]) -> bool:
	for eye: Vector3 in eyes:
		for target: Vector3 in targets:
			var from := Vector2(eye.x, eye.z)
			var to := Vector2(target.x, target.z)
			if Geometry2D.is_point_in_polygon(from, outline) \
					or Geometry2D.is_point_in_polygon(to, outline):
				return true
			for index: int in outline.size():
				var near := Geometry2D.get_closest_points_between_segments(from, to,
						outline[index], outline[(index + 1) % outline.size()])
				if near[0].distance_to(near[1]) < clearance:
					return true
	return false
