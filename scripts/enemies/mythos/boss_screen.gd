extends RefCounted
## La pantalla durante la cinemática de un jefe (MythosCinematic y
## LobsterEntrance): esconde el HUD y la pantalla dividida y pone la cámara
## de la cinemática; al soltarla devuelve todo como estaba.
##
## Dos cinemáticas pueden solaparse (un jefe que llega en plena entrada de
## otro), así que la cuenta es de todas juntas: el HUD y la pantalla dividida
## vuelven recién con la última que suelta, y la cámara de antes pasa de una
## a otra. La que está en pantalla, al soltar, deja la de la cinemática que
## sigue (o la del raider si ya no queda ninguna); la que suelta debajo de
## otra le pasa a esa su cámara de antes.
## Sin class_name: se usa con preload, como AttackFloor.

const SPLIT_SCREEN_GROUP := &"split_screen"

## Las cinemáticas que tienen la pantalla, en el orden en que la tomaron, y
## la cámara que había en pantalla antes de cada una (sin tipo: una cámara
## liberada no entra en un arreglo tipado).
static var _holders: Array = []
static var _previous: Array = []


## `holder` toma la pantalla y pone `camera`.
static func take(holder: Node, camera: Camera3D) -> void:
	_drop_stale()
	if _holders.is_empty():
		_show_world_ui(holder.get_tree(), false)
	_holders.append(holder)
	_previous.append(holder.get_viewport().get_camera_3d())
	camera.make_current()


## `holder` suelta la pantalla; `camera` es la suya. Se puede llamar siempre.
static func release(holder: Node, camera: Camera3D) -> void:
	var index := _holders.find(holder)
	if index < 0:
		return
	camera.clear_current(false)
	_drop(index, holder.get_tree() if holder.is_inside_tree() else null)


## Saca a la cinemática número `index` de la cuenta. Si estaba en pantalla,
## vuelve la cámara que había antes de ella; si otra la tomó después, esa se
## queda con su cámara de antes. Con la última, vuelven el HUD y la pantalla
## dividida (si hay árbol: al cerrar la partida no queda nada que mostrar).
static func _drop(index: int, tree: SceneTree) -> void:
	var previous: Variant = _previous[index]
	var on_screen := index == _holders.size() - 1
	_holders.remove_at(index)
	_previous.remove_at(index)
	if not on_screen:
		_previous[index] = previous
		return
	# clear_current(false) en la cinemática: sin esto Godot le pasa el turno a
	# cualquier cámara del viewport, y no a la que había antes.
	if is_instance_valid(previous) and (previous as Camera3D).is_inside_tree():
		(previous as Camera3D).make_current()
	if _holders.is_empty() and tree != null:
		_show_world_ui(tree, true)


## Las cinemáticas liberadas sin soltar la pantalla salen de la cuenta: si no,
## el HUD no volvería nunca.
static func _drop_stale() -> void:
	for index in range(_holders.size() - 1, -1, -1):
		if not is_instance_valid(_holders[index]):
			_drop(index, Engine.get_main_loop() as SceneTree)


static func _show_world_ui(tree: SceneTree, shown: bool) -> void:
	tree.call_group(&"hud", "set_cinematic", not shown)
	for node: Node in tree.get_nodes_in_group(SPLIT_SCREEN_GROUP):
		var split := node as CanvasItem
		if split != null:
			split.visible = shown
