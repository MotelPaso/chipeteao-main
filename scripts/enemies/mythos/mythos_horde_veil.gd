class_name MythosHordeVeil
extends RefCounted
## Durante la cinemática de Mythos la horda sigue ahí, congelada, y cualquier
## cuerpo parado delante de la cámara tapa al jefe. Esto la saca de la vista a
## medida que la onda del golpe la alcanza (sweep) y la devuelve al terminar
## la calma (lift), cuando Mythos la quema de verdad. Solo toca `visible`:
## ningún cuerpo cambia de vida ni deja la partida.

## Los cuerpos que ocultó, para devolverlos.
var _hidden: Array[Node3D] = []


## Oculta a los enemigos visibles a menos de `radius` metros de `center`,
## salvo `keep` (el jefe).
func sweep(tree: SceneTree, center: Vector3, radius: float, keep: Node) -> void:
	for node: Node in tree.get_nodes_in_group(&"enemies"):
		var body := node as Node3D
		if body == null or body == keep or not body.visible:
			continue
		var offset := body.global_position - center
		offset.y = 0.0
		if offset.length_squared() <= radius * radius:
			body.visible = false
			_hidden.append(body)


## Devuelve a la vista todo lo que ocultó. Se puede llamar siempre.
func lift() -> void:
	for body: Node3D in _hidden:
		if is_instance_valid(body):
			body.visible = true
	_hidden.clear()
