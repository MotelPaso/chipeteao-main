class_name SuspendedStage
extends RefCounted
## La ARENA DE LA ETAPA mientras el equipo pelea en la arena de un jefe (lo
## usa BossArenaHost): la saca del árbol, la guarda entera y la vuelve a
## colgar como estaba.
##
## Fuera del árbol la arena no procesa, no choca, no se dibuja, no suena y no
## responde a ningún grupo. Lo que es de la etapa pero vive en RunSystems se
## duerme a mano, sin reiniciarlo: el WorldDirector (eventos, clima, portal
## de salida, balizas), la niebla, y el minimapa y el mapa de Tab.
## Dos cosas que el motor no devuelve solo al volver a colgarla:
##   - un nodo que vuelve a entrar al árbol no corre _ready otra vez, así que
##     lo que un script arranca ahí no se repite (a propósito: nada se
##     reconstruye). Lo que se arma en _enter_tree lleva su propia guarda
##     (scatter.gd).
##   - los sonidos: uno con autoplay vuelve a sonar al entrar y uno detenido
##     a mano no. Aquí se anota cuáles sonaban y se deja cada uno igual.

## Daño con que muere otro jefe que siga vivo al partir, en veces su vida máxima.
const RIVAL_DAMAGE_FACTOR: float = 10.0

## Los reproductores de sonido de la arena y si sonaban al salir: [nodo, bool].
var _sounds: Array[Array] = []
var _arena: Node3D = null


## La arena guardada, o null si no hay ninguna.
func arena() -> Node3D:
	return _arena if is_instance_valid(_arena) else null


## Saca `stage` del árbol y la guarda. `root` deja de tener arena viva.
func suspend(root: RunRoot, stage: Node3D) -> void:
	var tree := root.get_tree()
	tree.call_group("world_director", "suspend_stage")
	tree.call_group("fog", "set_away", true)
	tree.call_group("hud", "set_maps_away", true)
	_sounds = _sounds_under(stage)
	_free_weapon_effects(stage)
	root.arena_host().remove_child(stage)
	root.set_live_arena(null)
	_arena = stage


## Vuelve a colgar la arena guardada como la viva y despierta lo suyo.
## Devuelve la arena (null si no había ninguna).
func restore(root: RunRoot) -> Node3D:
	var stage := arena()
	_arena = null
	if stage == null:
		return null
	var tree := root.get_tree()
	# Antes del add_child, como RunRoot._load_stage: lo que entra al árbol ya
	# pregunta por arena_root().
	root.set_live_arena(stage)
	root.arena_host().add_child(stage)
	for entry: Array in _sounds:
		var player: Variant = entry[0]
		if not is_instance_valid(player):
			continue
		var playing := bool((player as Node).get("playing"))
		if bool(entry[1]) and not playing:
			(player as Node).call(&"play")
		elif not bool(entry[1]) and playing:
			(player as Node).call(&"stop")
	_sounds.clear()
	tree.call_group("world_director", "resume_stage")
	tree.call_group("fog", "set_away", false)
	tree.call_group("hud", "set_maps_away", false)
	# La flecha de objetivo del HUD estuvo apuntando al portal de la arena del
	# jefe: si la etapa ya tenía abierto su portal de salida, vuelve a él.
	for node: Node in descendants(stage):
		var way_out := node as ExitPortal
		if way_out != null and way_out.available:
			tree.call_group("boss_ui", "track_objective", way_out)
	return stage


## Libera la arena guardada (la partida se va): no cuelga de nadie, así que
## nadie más lo haría. Primero devuelve a sus pools lo que tenía vivo.
func discard() -> void:
	var stage := arena()
	_arena = null
	_sounds.clear()
	if stage == null or stage.is_inside_tree():
		return
	Pools.release_live_under(stage)
	stage.free()


## Termina YA la caída de cada enemigo que está muriendo en `stage`, que
## todavía está en el árbol: su cuerpo se libera al final de este frame, como
## al terminar su caída. Un cuerpo a medio caer no puede quedarse en un mapa
## que sale del árbol: su caída se detendría con él.
static func finish_dying(stage: Node) -> void:
	if stage == null:
		return
	for node: Node in descendants(stage):
		var body := node as EnemyBase
		if body == null or body.is_queued_for_deletion():
			continue
		var health := Health.find_in(body)
		if health != null and health.is_dead:
			body.queue_free()


## Saca de la arena guardada a la horda normal que quedó en ella (sin pagar
## nada) y las saetas que venían en vuelo. Los siervos poseídos y los jefes
## se quedan. Devuelve cuántos enemigos se llevó.
func sweep_horde() -> int:
	var stage := arena()
	if stage == null:
		return 0
	var horde: Array[EnemyBase] = []
	var bolts: Array[Node3D] = []
	for node: Node in descendants(stage):
		if node.is_queued_for_deletion():
			continue
		if node.is_in_group(&"enemy_projectiles") and node is Node3D:
			bolts.append(node as Node3D)
			continue
		var body := node as EnemyBase
		if body == null or body is BossBase or body.is_in_group(&"possessed"):
			continue
		# También los que el viaje sorprendió cayendo: ya salieron del grupo
		# "enemies" y su caída quedó detenida con el mapa.
		horde.append(body)
	for bolt: Node3D in bolts:
		Pools.release(bolt)
	for body: EnemyBase in horde:
		body.get_parent().remove_child(body)
		body.free()
	return horde.size()


## Otro jefe que siga vivo en el mapa muere ahora, con su pago de siempre,
## antes de que el equipo se vaya: el jefe del viaje pelea solo. El jefe de
## etapa y uno de varias vidas se salvan (el golpe les quitaría una vida
## entera). Se llama con el mapa todavía vivo. Devuelve cuántos mató.
static func slay_rival_bosses(tree: SceneTree) -> int:
	var slain := 0
	for node: Node in tree.get_nodes_in_group(&"boss"):
		var rival := node as BossBase
		if rival == null or rival.is_in_group(BossSchedule.STAGE_BOSS_GROUP):
			continue
		var health := Health.find_in(rival)
		if health == null or health.is_dead or health is GuardedHealth:
			continue
		health.take_damage(health.max_hp * RIVAL_DAMAGE_FACTOR)
		if health.is_dead:
			slain += 1
	return slain


## Todos los nodos bajo `root`. Sirve fuera del árbol, donde los grupos no
## responden (también lo usa el harness para contar lo que quedó guardado).
static func descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			found.append(child)
			pending.append(child)
	return found


## Libera los efectos de un solo uso que las armas del equipo dejaron en el
## aire (un frasco en vuelo, un rayo, un haz): mallas sin script ni dueño
## colgadas directo de la arena (WeaponBase.spawn_fx_mesh). El arma que los
## anima viaja con su raider y los seguiría moviendo aquí, fuera del árbol;
## liberados, los suelta sola, igual que cuando un cambio de etapa se lleva
## la arena. Nada del mapa cumple esa regla: lo suyo tiene script o dueño.
func _free_weapon_effects(stage: Node3D) -> void:
	for child: Node in stage.get_children():
		if child is MeshInstance3D and child.owner == null and child.get_script() == null:
			child.free()


## Cada reproductor de sonido bajo `root` con si estaba sonando: [nodo, bool].
func _sounds_under(root: Node) -> Array[Array]:
	var sounds: Array[Array] = []
	for node: Node in descendants(root):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			sounds.append([node, bool(node.get("playing"))])
	return sounds
