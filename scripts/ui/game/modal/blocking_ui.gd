class_name BlockingUi
extends RefCounted
## Contrato de pausa de las capas modales. Toda capa que pausa el árbol (el
## selector de cartas, el menú de pausa, la pantalla de fin, la tienda del
## vendedor, la ruleta) entra al grupo GROUP y expone is_blocking() -> bool:
## true mientras es dueña de la pausa. Antes de abrir sobre la partida se
## pregunta any_open(); antes de quitar una pausa propia, other_open().

## Grupo de las capas que pueden ser dueñas de la pausa del árbol.
const GROUP := &"ui_blocking"
## Grupo de las capas que se pueden cerrar desde código con dismiss() (el
## cambio de etapa y los harness lo llaman con call_group).
const CLOSABLE_GROUP := &"blocking_ui_closable"


## ¿Alguna capa del grupo es dueña de la pausa (o está por serlo)? Un miembro sin
## is_blocking() CUENTA como bloqueante y deja un aviso: si alguien olvida el
## contrato, la comprobación falla del lado SEGURO y nada se abre encima.
static func any_open(tree: SceneTree) -> bool:
	for node: Node in tree.get_nodes_in_group(GROUP):
		if not node.has_method(&"is_blocking"):
			push_warning("ui_blocking member without is_blocking(): %s" % node.name)
			return true
		if node.call(&"is_blocking") == true:
			return true
	return false


## ¿Algún miembro del grupo DISTINTO de `me` es dueño de la pausa ahora? Quien
## pregunta está por soltar su propia pausa: si otra capa la tiene, no la suelta.
## Aquí un miembro sin is_blocking() no cuenta.
static func other_open(tree: SceneTree, me: Node) -> bool:
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node == me or not node.has_method(&"is_blocking"):
			continue
		if node.call(&"is_blocking") == true:
			return true
	return false
