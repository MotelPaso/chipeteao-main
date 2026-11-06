class_name NodePool
extends Node
## Pool de instancias reusables para UNA PackedScene cuya raíz extiende
## Node3D. Contrato (chico a propósito): los scripts en pool implementan
## pool_reset(), que se llama en cada acquire DESPUÉS de (re)colgar el nodo,
## para restaurar el estado de recién creado (contadores, golpes, tweens).
## Los nodos guardados viven FUERA del árbol — sin proceso ni física, y
## sobreviven a los cambios de escena —, mientras los que están en vuelo son
## hijos de la escena actual y mueren con ella; el camino diferido de
## liberación cubre esa carrera. Lo crea y configura el autoload Pools; no
## va suelto en escenas de juego.
##
## release()/acquire() son estrictamente simétricos: lo que release() apaga
## primero lo ANOTA en el nodo, y acquire() devuelve ese mismo valor. El pool
## nunca inventa estado (no fuerza el proceso de nodos que no lo usan) y
## nunca deja un Area3D guardado escuchando.

const META_OWNER: StringName = &"_node_pool_owner"
## Foto por nodo de lo que apagó release(); que exista la primera le dice a
## acquire() que el nodo ya estuvo guardado.
const META_PROCESS: StringName = &"_node_pool_process"
const META_PHYSICS_PROCESS: StringName = &"_node_pool_physics_process"
const META_MONITORING: StringName = &"_node_pool_monitoring"
const META_MONITORABLE: StringName = &"_node_pool_monitorable"

## Escena que instancia este pool; su raíz debe ser un Node3D.
@export var scene: PackedScene
## Instancias creadas por adelantado para que los primeros spawns no tironeen.
@export var preload_count: int = 0
## Tope suave: pasada esta cantidad de guardados, lo que se libera se borra
## en vez de guardarse, y así se acota la memoria tras un pico.
@export var max_free: int = 64

## Instancias creadas en total (solo sube): la medida de recambio; en
## régimen deja de crecer porque todo spawn sale de los guardados.
var total_created: int = 0
## Máximo de nodos guardados a la vez (marca tras un pico).
var peak_parked: int = 0

var _parked: Array[Node3D] = []
## Ids liberados en este frame pero aún no descolgados (ver release()).
var _pending_release: Dictionary[int, bool] = {}
## Instancias que están AFUERA en el mundo (adquiridas y no guardadas). Un
## cambio de etapa tiene que recuperarlas: si un dardo en vuelo muriera con
## la escena, el pool lo seguiría contando como creado sin guardarlo nunca.
var _live: Dictionary[int, Node3D] = {}


func _ready() -> void:
	for i: int in preload_count:
		var node := _create_instance()
		if node == null:
			break
		_parked.append(node)
	peak_parked = _parked.size()


func _notification(what: int) -> void:
	# Los guardados viven fuera del árbol y nada los libera solo; se liberan
	# cuando se destruye el pool (al cerrar la app) para salir limpio.
	if what == NOTIFICATION_PREDELETE:
		for node: Node3D in _parked:
			if is_instance_valid(node):
				node.free()
		_parked.clear()


## Entrega una instancia bajo `parent` (reusa una guardada si hay; si no, el
## pool crece), reactivada y con pool_reset().
func acquire(parent: Node) -> Node3D:
	if parent == null:
		return null
	var node: Node3D
	if _parked.is_empty():
		node = _create_instance()
		if node == null:
			return null
	else:
		node = _parked.pop_back()
	parent.add_child(node)
	# Devuelve exactamente lo que anotó release(); el estado del script es
	# trabajo de pool_reset. Un nodo nunca guardado conserva lo que derivó al
	# entrar al árbol, así los FX sin _process no entran a la lista de proceso.
	node.visible = true
	if node.has_meta(META_PROCESS):
		node.set_process(node.get_meta(META_PROCESS))
		node.set_physics_process(node.get_meta(META_PHYSICS_PROCESS))
	var area := node as Area3D
	if area != null and node.has_meta(META_MONITORING):
		# Diferido como en release(): ambos lados se aplican en orden de
		# llamada, así un release/acquire en el mismo frame termina escuchando.
		area.set_deferred(&"monitoring", node.get_meta(META_MONITORING))
		area.set_deferred(&"monitorable", node.get_meta(META_MONITORABLE))
	if node.has_method(&"pool_reset"):
		node.call(&"pool_reset")
	_live[node.get_instance_id()] = node
	return node


## Devuelve un nodo al pool. Seguro ante doble liberación (repetir no hace
## nada) y desde callbacks de física: el nodo queda inerte de inmediato, pero
## se descuelga diferido porque remove_child durante el despacho de señales
## de un Area3D no está permitido.
func release(node: Node3D) -> void:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	var id := node.get_instance_id()
	# Ya pendiente, o ya guardado (los guardados no tienen padre).
	if _pending_release.has(id) or node.get_parent() == null:
		return
	_pending_release[id] = true
	node.visible = false
	node.set_meta(META_PROCESS, node.is_processing())
	node.set_meta(META_PHYSICS_PROCESS, node.is_physics_processing())
	node.set_physics_process(false)
	node.set_process(false)
	var area := node as Area3D
	if area != null:
		# Un Area3D liberado deja de detectar ya, no al descolgarse. Diferido
		# porque monitoring no se puede tocar durante un despacho de señales.
		node.set_meta(META_MONITORING, area.monitoring)
		node.set_meta(META_MONITORABLE, area.monitorable)
		area.set_deferred(&"monitoring", false)
		area.set_deferred(&"monitorable", false)
	_finish_release.call_deferred(node, id)


## Recupera ya (sin salto diferido) cada instancia que sigue en el mundo: un
## cambio de etapa libera la arena de la que cuelgan, y lo que quedara ahí
## se borraría a espaldas del pool. Se puede llamar siempre; sin nada afuera
## no hace nada.
func release_all_live() -> void:
	for id: int in _live.keys():
		var node: Node3D = _live[id]
		_live.erase(id)
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		# Ya hay una liberación en curso; su _finish_release diferido lo
		# guardará. Tocarlo aquí lo guardaría dos veces.
		if _pending_release.has(id):
			continue
		var parent := node.get_parent()
		if parent == null:
			continue
		node.visible = false
		node.set_meta(META_PROCESS, node.is_processing())
		node.set_meta(META_PHYSICS_PROCESS, node.is_physics_processing())
		node.set_physics_process(false)
		node.set_process(false)
		var area := node as Area3D
		if area != null:
			node.set_meta(META_MONITORING, area.monitoring)
			node.set_meta(META_MONITORABLE, area.monitorable)
			area.monitoring = false
			area.monitorable = false
		parent.remove_child(node)
		if _parked.size() >= max_free:
			node.queue_free()
			continue
		_parked.append(node)
		peak_parked = maxi(peak_parked, _parked.size())


## Contadores para la sonda de rendimiento y los soaks.
func stats() -> Dictionary[String, int]:
	return {
		"created": total_created,
		"parked": _parked.size(),
		"pending": _pending_release.size(),
		"peak_parked": peak_parked,
	}


func parked_count() -> int:
	return _parked.size()


func _finish_release(node: Node3D, id: int) -> void:
	_pending_release.erase(id)
	_live.erase(id)
	# La escena del nodo puede haberse desarmado entre release() y esta
	# llamada diferida (salir al menú con tiros en vuelo); murió con ella.
	if not is_instance_valid(node):
		return
	# Ya guardado (un cambio de etapa lo recuperó entre el release y esta
	# llamada): guardarlo dos veces pondría la misma instancia dos veces en
	# _parked y se la entregaría a dos llamadores a la vez.
	var parent := node.get_parent()
	if parent == null:
		return
	parent.remove_child(node)
	if _parked.size() >= max_free:
		# queue_free y no free: Pools.release cede el nodo, pero un llamador
		# que aún tiene la referencia en este frame no debe quedarse con un
		# puntero colgando a mitad de las llamadas diferidas.
		node.queue_free()
		return
	_parked.append(node)
	peak_parked = maxi(peak_parked, _parked.size())


func _create_instance() -> Node3D:
	if scene == null:
		push_error("NodePool '%s': no scene assigned." % name)
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		push_warning("NodePool '%s': scene root is not a Node3D." % name)
		return null
	node.set_meta(META_OWNER, self)
	total_created += 1
	return node
