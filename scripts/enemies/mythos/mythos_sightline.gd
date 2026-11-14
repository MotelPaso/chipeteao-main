class_name MythosSightline
extends RefCounted
## Cuánto estorba la escenografía entre una cámara de cinemática y lo que
## filma. Mide un PASILLO, no un rayo: la copa de un árbol tapa la vista
## aunque su tronco quede al costado de la línea de mira. El pasillo es una
## caja a la altura de los troncos; lo usan las cámaras de las dos
## cinemáticas de Mythos para elegir de qué lado filmar y dónde pararse.
## Hay que medir ANTES de congelar el mundo: congelada, la escenografía sale
## de la física y nada la toca.

## Metros sobre el suelo del centro de la caja y su alto.
const CORRIDOR_HEIGHT: float = 2.6
const CORRIDOR_THICKNESS: float = 1.4
## Cuánto estorba cada cosa que pisa el pasillo: lo mínimo (lejos), lo que
## suma si está pegada a la cámara y lo que cuenta una loma del terreno.
const CROWD_FAR: float = 0.25
const CROWD_NEAR: float = 1.0
const CROWD_TERRAIN: float = 0.5
## Lo que cuenta un portal, un altar o un manantial: no chocan con nada,
## pero su columna de luz tapa igual. Son los nodos del grupo "map_markers".
const CROWD_MARKER: float = 0.8
const MARKER_GROUP := &"map_markers"
## Metros más allá de lo filmado en los que una de esas columnas todavía se
## cuenta: justo detrás del jefe también le pisa la silueta.
const MARKER_PAST: float = 8.0


## Estorbo del pasillo de `reach` metros de largo y `width` de ancho que
## sale de `eye` hacia `view` (a ras de suelo), sobre el suelo `ground`.
## Cada tronco, roca o meseta de las capas `mask` suma más cuanto más cerca
## de la cámara está; 0 es un pasillo libre.
static func crowd(space: PhysicsDirectSpaceState3D, eye: Vector3, view: Vector3,
		ground: float, reach: float, width: float, mask: int) -> float:
	var box := BoxShape3D.new()
	box.size = Vector3(width, CORRIDOR_THICKNESS, reach)
	var center := eye + view * (reach * 0.5)
	center.y = ground + CORRIDOR_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = mask
	query.transform = Transform3D(Basis.looking_at(view, Vector3.UP), center)
	var total := 0.0
	var seen: Dictionary[int, bool] = {}
	for hit: Dictionary in space.intersect_shape(query, 32):
		var body := hit.get("collider") as Node3D
		# Un cuerpo con varias formas (el terreno, una formación) cuenta una vez.
		if body == null or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		if body is Terrain:
			total += CROWD_TERRAIN
			continue
		var offset := body.global_position - eye
		offset.y = 0.0
		var near := 1.0 - clampf(offset.length() / maxf(reach, 0.01), 0.0, 1.0)
		total += CROWD_FAR + CROWD_NEAR * near * near
	return total


## Estorbo entre `eye` y `target`: el pasillo que va de uno al otro, más los
## portales, altares y manantiales de `tree` que queden dentro.
static func crowd_between(tree: SceneTree, space: PhysicsDirectSpaceState3D, eye: Vector3,
		target: Vector3, ground: float, width: float, mask: int) -> float:
	var view := target - eye
	view.y = 0.0
	var reach := view.length()
	if reach < 0.5:
		return 0.0
	var forward := view / reach
	var total := crowd(space, eye, forward, ground, reach, width, mask)
	for node: Node in tree.get_nodes_in_group(MARKER_GROUP):
		var marker := node as Node3D
		if marker == null or not marker.is_visible_in_tree():
			continue
		var offset := marker.global_position - eye
		offset.y = 0.0
		var along := offset.dot(forward)
		if along > 0.0 and along < reach + MARKER_PAST \
				and (offset - forward * along).length() < width * 0.5:
			total += CROWD_MARKER
	return total
