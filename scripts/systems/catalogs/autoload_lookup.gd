class_name AutoloadLookup
extends RefCounted
## Busca un autoload por nombre desde código estático. Las funciones estáticas
## no ven los nombres de autoload directamente y un harness `-s` no tiene
## autoloads, así que los catálogos los buscan por aquí y reciben null en vez
## de caerse.


## El nodo autoload `node_name` (&"SaveData", &"Sfx"...), o null si no existe.
static func find(node_name: StringName) -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null(NodePath(node_name))
