class_name GroundAlign
extends RefCounted
## Inclina lo que queda apoyado en el piso (charcos, ondas, discos de las
## armas) para que siga la pendiente del terreno en vez de quedar plano y
## medio enterrado en una ladera.

## Metros sobre y bajo el punto pedido que recorre la sonda de suelo.
const PROBE_UP: float = 2.0
const PROBE_DOWN: float = 4.0
## Capa de colisión del mundo (suelo, relieve, rocas).
const GROUND_MASK: int = 1


## Normal del suelo bajo `at` (capa del mundo, sin jugadores), o UP si no hay nada.
static func normal_at(tree: SceneTree, at: Vector3) -> Vector3:
	var hit := _probe(tree, at)
	if hit.is_empty():
		return Vector3.UP
	return (hit["normal"] as Vector3).normalized()


## Normal del plano que mejor se apoya en el suelo bajo un disco de `radius`
## centrado en `at`: mide la altura en cuatro puntos del borde, así un charco o
## un aura ancho no se entierra de un lado en una ladera curva. Si algún punto
## no tiene suelo, usa la normal del centro.
static func fit_normal(tree: SceneTree, at: Vector3, radius: float) -> Vector3:
	var heights: Array[float] = []
	for offset: Vector3 in [Vector3(radius, 0, 0), Vector3(-radius, 0, 0),
			Vector3(0, 0, radius), Vector3(0, 0, -radius)]:
		var hit := _probe(tree, at + offset)
		if hit.is_empty():
			return normal_at(tree, at)
		heights.append((hit["position"] as Vector3).y)
	var span := maxf(radius * 2.0, 0.001)
	return Vector3((heights[1] - heights[0]) / span, 1.0,
			(heights[3] - heights[2]) / span).normalized()


## Rayo hacia abajo en la capa del mundo, sin los jugadores (comparten la capa
## 1 con el mundo: una cabeza no es suelo).
static func _probe(tree: SceneTree, at: Vector3) -> Dictionary:
	var space := tree.root.world_3d.direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * PROBE_UP,
			at + Vector3.DOWN * PROBE_DOWN, GROUND_MASK)
	var excluded: Array[RID] = []
	for node: Node in tree.get_nodes_in_group(&"player"):
		var body := node as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	ray.exclude = excluded
	return space.intersect_ray(ray)


## Gira `node` para que su eje Y apunte a `normal` en el MUNDO (aunque su
## padre gire), conservando su escala.
static func align(node: Node3D, normal: Vector3) -> void:
	if node == null or normal.length_squared() < 0.0001:
		return
	var tilt := Basis(Quaternion(Vector3.UP, normal.normalized()))
	node.global_basis = tilt * Basis.from_scale(node.global_basis.get_scale())


## Atajo: inclina `node` según el suelo bajo su posición, con el plano que
## mejor apoya un disco de `radius` (0 = solo el punto del centro).
static func align_to_ground(node: Node3D, radius: float = 0.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var tree := node.get_tree()
	var at := node.global_position
	align(node, fit_normal(tree, at, radius) if radius > 0.0 else normal_at(tree, at))
