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
## Lo que pase por exempt() (está en EXEMPT_GROUP) sigue vivo en todo
## congelado, aunque nadie lo nombre.
##
## Dos congelados pueden SOLAPARSE (dos jefes que llegan a la vez), en
## cualquier orden. Por eso las cuentas son de todas las instancias juntas:
## cada nodo guarda el process_mode que tenía antes del primer congelado que
## lo tocó, sigue congelado (o vivo) mientras algún congelado en curso lo
## pida, y el mundo y el reloj vuelven recién cuando termina el último.
##
## Un cuerpo desactivado SALE de la física (disable_mode por defecto), así
## que durante el congelado el suelo no sostiene a nadie: lo que siga vivo
## no debe moverse con física.

## Grupos cuyos nodos se desactivan, en este orden.
const FROZEN_GROUPS: Array[StringName] = [
	&"arena_root", &"player", &"downed_players", &"world_director",
]
## Grupo de lo que sigue vivo en cualquier congelado sin estar en
## keep_running (ver exempt()).
const EXEMPT_GROUP: StringName = &"world_freeze_exempt"

## Los congelados en curso, de todas las instancias, en el orden en que empezaron.
static var _active: Array[WorldFreeze] = []
## process_mode de cada nodo tocado, de antes del primer congelado en curso
## que lo tocó (por id de instancia).
static var _original_modes: Dictionary[int, int] = {}

## Lo que este congelado mantiene vivo y lo que desactiva (por id de instancia).
var _kept: Dictionary[int, Node] = {}
var _held: Dictionary[int, Node] = {}
var _frozen: bool = false


func is_frozen() -> bool:
	return _frozen


## Congela el mundo. `keep_running` son los nodos que siguen vivos aunque
## cuelguen de algo congelado.
func freeze(tree: SceneTree, keep_running: Array[Node]) -> void:
	if _frozen or tree == null:
		return
	_frozen = true
	_drop_stale()
	_active.append(self)
	# Primero los que siguen vivos: un nodo que pasara por DISABLED aunque
	# fuera un frame saldría de la física y volvería a entrar.
	var kept: Array = keep_running.duplicate()
	kept.append_array(tree.get_nodes_in_group(EXEMPT_GROUP))
	for entry: Variant in kept:
		if is_instance_valid(entry):
			_kept[(entry as Node).get_instance_id()] = entry
			_apply(entry as Node)
	for group: StringName in FROZEN_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			_held[node.get_instance_id()] = node
			_apply(node)
	# El reloj de la partida (RunState) no cuelga de nada de lo anterior.
	RunState.set_physics_process(false)


## Termina este congelado: cada nodo que tocó vuelve a como estaba, salvo lo
## que otro congelado en curso todavía pide. Con el último vuelve también el
## reloj. Se puede llamar siempre; los nodos que ya no existen se saltan.
func thaw() -> void:
	if not _frozen:
		return
	_frozen = false
	_active.erase(self)
	var touched: Array = _kept.values() + _held.values()
	_kept.clear()
	_held.clear()
	for entry: Variant in touched:
		if is_instance_valid(entry):
			_apply(entry as Node)
	if _active.is_empty():
		_original_modes.clear()
		RunState.set_physics_process(true)


## Saca de la cuenta los congelados en curso que ya no tocan ningún nodo vivo
## (una partida que se liberó sin descongelar): sin esto el reloj de la
## partida siguiente no volvería nunca, porque la cuenta nunca quedaría vacía.
static func _drop_stale() -> void:
	for freeze: WorldFreeze in _active.duplicate():
		if not freeze._touches_live_node():
			_active.erase(freeze)
	if _active.is_empty():
		_original_modes.clear()


func _touches_live_node() -> bool:
	for node: Variant in _held.values() + _kept.values():
		if is_instance_valid(node):
			return true
	return false


## Deja a `node` vivo en todo congelado: en los que ya están en curso y en
## los que vengan. Lo usa un jefe que empieza a morir: su caída no queda a
## medias si otro jefe congela el mundo.
static func exempt(node: Node) -> void:
	node.add_to_group(EXEMPT_GROUP)
	if _active.is_empty():
		return
	for freeze: WorldFreeze in _active:
		freeze._kept[node.get_instance_id()] = node
	_apply(node)


## Deja a `node` como lo piden los congelados en curso: vivo (PAUSABLE) si
## alguno lo mantiene, desactivado si alguno lo congela y, si ya ninguno lo
## toca, con el process_mode que tenía antes del primero.
static func _apply(node: Node) -> void:
	var id := node.get_instance_id()
	if not _original_modes.has(id):
		_original_modes[id] = node.process_mode
	var kept := false
	var held := false
	for freeze: WorldFreeze in _active:
		kept = kept or freeze._kept.has(id)
		held = held or freeze._held.has(id)
	if kept:
		node.process_mode = Node.PROCESS_MODE_PAUSABLE
	elif held:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		node.process_mode = _original_modes[id] as Node.ProcessMode
		_original_modes.erase(id)
