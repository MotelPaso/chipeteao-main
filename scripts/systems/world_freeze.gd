class_name WorldFreeze
extends RefCounted
## Congela el MUNDO de una partida sin pausar el árbol: la arena entera
## (enemigos, proyectiles, todo lo del pool, interactuables), cada raider con
## sus armas y su mascota, el director de eventos y clima, y el reloj de la
## partida. Lo usa la cinemática de un jefe.
##
## No es get_tree().paused a propósito:
##   - el menú de pausa no se abre sobre una pausa ajena, y durante la
##     cinemática tiene que seguir disponible (y congelarla a ella también);
##   - el harness de soak cuelga la partida de un nodo que procesa siempre,
##     así que ahí una pausa no detiene nada.
## process_mode DISABLED funciona igual en los dos casos. Lo que deba seguir
## vivo dentro de lo congelado (el jefe, su cinemática) va en `keep_running`
## y queda en PAUSABLE: sigue corriendo, y el menú de pausa sí lo detiene.
##
## Un cuerpo desactivado SALE de la física (disable_mode por defecto), así
## que durante el congelado el suelo no sostiene a nadie: lo que siga vivo
## no debe moverse con física.

## Grupos cuyos nodos se desactivan, en este orden.
const FROZEN_GROUPS: Array[StringName] = [
	&"arena_root", &"player", &"downed_players", &"world_director",
]

## Nodos tocados y el process_mode que tenía cada uno (por id de instancia).
var _nodes: Array[Node] = []
var _modes: Dictionary[int, int] = {}
var _frozen: bool = false


func is_frozen() -> bool:
	return _frozen


## Congela el mundo. `keep_running` son los nodos que siguen vivos aunque
## cuelguen de algo congelado.
func freeze(tree: SceneTree, keep_running: Array[Node]) -> void:
	if _frozen or tree == null:
		return
	_frozen = true
	# Primero los que siguen vivos: un nodo que pasara por DISABLED aunque
	# fuera un frame saldría de la física y volvería a entrar.
	for node: Node in keep_running:
		if is_instance_valid(node):
			_set_mode(node, Node.PROCESS_MODE_PAUSABLE)
	for group: StringName in FROZEN_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			_set_mode(node, Node.PROCESS_MODE_DISABLED)
	# El reloj de la partida (RunState) no cuelga de nada de lo anterior.
	RunState.set_physics_process(false)


## Devuelve cada nodo a como estaba y vuelve a poner el reloj en marcha. Se
## puede llamar siempre; los nodos que ya no existen se saltan.
func thaw() -> void:
	if not _frozen:
		return
	_frozen = false
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.process_mode = _modes[node.get_instance_id()] as Node.ProcessMode
	_nodes.clear()
	_modes.clear()
	RunState.set_physics_process(true)


func _set_mode(node: Node, mode: Node.ProcessMode) -> void:
	var id := node.get_instance_id()
	if not _modes.has(id):
		_modes[id] = node.process_mode
		_nodes.append(node)
	node.process_mode = mode
