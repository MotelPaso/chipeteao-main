class_name RunRoot
extends Node3D
## Raíz persistente de una partida. Todo lo que debe SOBREVIVIR a un cambio
## de mapa vive aquí: el bloque de partida (RunSystems: Player, RunManager,
## WorldDirector, HUD, cartas, pantalla de fin, menú de pausa) y nada más.
## El bioma del momento se instancia bajo ArenaHost y se tira cuando el
## equipo sale por el portal: una partida es una secuencia de ETAPAS.
##
## Qué cruza una etapa: los raiders mismos y por tanto su nivel, armas,
## tomos, objetos, mascotas, puntos, bendiciones de altar y temporales, la
## dificultad de la partida y la inflación de cofres y ruleta; nada se copia
## porque nada se recrea. Qué se reinicia: el mapa y todo lo que cuelga de
## él (cofres, altares, portales, ruletas, balizas, enemigos, props), el
## reloj de etapa y el calendario de jefes.
##
## El orden de etapas es el de MapCatalog.MAP_LIBRARY, volviendo al primer
## mapa con lap + 1. RunState lleva los contadores; este nodo hace el cambio.
##
## Se llega por el grupo "run_root", nunca por ruta: arena_root() es el
## padre de todo spawn de etapa, así nada de la etapa N sobrevive a la N.

## Nodo bajo el que se instancia la arena de la etapa.
const ARENA_HOST_NAME: String = "ArenaHost"
## Cuadros de espera tras liberar los objetos de la etapa, para que el motor
## los recupere de verdad antes de que el barrido los cuente.
const SWAP_SETTLE_FRAMES: int = 1
## Grupos de objetos de etapa que el cambio libera antes del barrido, en
## este orden. Cada uno tiene su campo en la línea `Stage sweep:` salvo
## lucky_blocks: ese formato es fijo (tools/verificar.sh compara la línea
## entera), así que un grupo nuevo se libera aquí sin tocar la línea.
const STAGE_PROP_GROUPS: Array[StringName] = [&"altars", XpGem.LIVE_GROUP,
		HealthOrb.LIVE_GROUP, &"powerup_pickups", &"pet_boxes", &"vendors", &"possessed",
		&"lucky_blocks"]

@onready var _arena_host: Node3D = get_node(ARENA_HOST_NAME)

## La arena de la etapa actual. Se guarda porque Pools y cada spawn del
## mundo la piden todo el tiempo; se refresca en cada cambio.
var _arena: Node3D = null
## True desde que empieza un cambio hasta que la nueva etapa está viva: un
## segundo raider que pulsa el portal durante el fundido no inicia otro.
var _swapping: bool = false


func _enter_tree() -> void:
	add_to_group("run_root")


func _ready() -> void:
	# RunSystems (un hijo) ya llamó a RunState.reset() en su _enter_tree, así
	# los contadores de etapa están limpios; esto solo decide en QUÉ etapa
	# empieza la partida. El juego normal y la diaria empiezan en el bosque;
	# el harness apunta BONK_ARENA a un bioma, que pasa a ser
	# GameConfig.start_map_id.
	RunState.stage_index = MapCatalog.index_of(GameConfig.start_map_id)
	RunState.lap = 0
	_load_stage()


## La arena viva, o null entre etapas. EL acceso para colgar cosas de la
## etapa (Pools, cofres soltados, FX): current_scene es la raíz de la
## partida y no cambia, así que todo lo de la etapa pregunta aquí.
func arena_root() -> Node3D:
	if _arena != null and not is_instance_valid(_arena):
		_arena = null
	return _arena


## Alias público con el nombre que se lee mejor en el resto del código.
func current_arena() -> Node3D:
	return arena_root()


## EL padre de todo lo que se genera EN EL MUNDO desde cualquier parte del
## código (FX de pool, cofres soltados, púas del jefe, proyectiles, la UI
## bloqueante de la ruleta). Estático y recibe el árbol para que scripts sin
## autoload propio lleguen en una línea. No usar current_scene: es la raíz
## persistente, y colgar ahí llevaría los dardos, cofres y charcos de la
## etapa 1 a la 2. Fuera de una partida (menús) cae a current_scene, y como
## último recurso a la raíz del árbol.
static func stage_parent(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var root := tree.get_first_node_in_group("run_root")
	if root != null and root.has_method("arena_root"):
		var arena: Variant = root.call("arena_root")
		if arena is Node3D and is_instance_valid(arena):
			return arena
	return tree.current_scene if tree.current_scene != null else tree.root


## Si un cambio de etapa puede EMPEZAR ahora. Síncrono a propósito: quien
## se gasta para tomar el portal tiene que saberlo ANTES, y advance_stage es
## una corrutina cuya respuesta llega recién tras todo el cambio, cuando el
## portal ya se liberó con su arena.
func can_advance_stage() -> bool:
	return not _swapping and RunState.run_active and not ScreenFade.is_busy()


## Público (portal de salida, por el grupo "run_root"): desarma la etapa
## actual y construye la siguiente tras un fundido. No hace nada si ya hay
## un cambio en curso.
func advance_stage() -> void:
	# Una partida que ya terminó no construye otra etapa: el cierre ya leyó
	# stages_cleared_total, laps_completed y visited_map_ids, y un cambio
	# posterior movería los tres a espaldas del registro y correría los
	# objetos de la etapa siguiente bajo la pantalla de fin.
	if _swapping or not RunState.run_active:
		return
	_swapping = true
	# Con await, este método también es corrutina: quien lo llama lo dispara
	# y se olvida (el portal lo hace), y la bandera es lo que vuelve inútil
	# una segunda pulsación durante el fundido.
	if not await ScreenFade.transition_async(_swap_stage):
		# Ya había un fundido (una partida terminando, un menú saliendo): la
		# etapa sigue y el portal se puede volver a pulsar.
		_swapping = false


## Construye la etapa a la que apunta RunState.stage_index: instancia,
## publica el id del mapa, coloca al equipo y lo anuncia. El _ready de la
## arena maneja el acuerdo director/scatter (ver arena.gd).
func _load_stage() -> void:
	var row := MapCatalog.MAP_LIBRARY[RunState.stage_index % MapCatalog.MAP_LIBRARY.size()]
	var map_id := String(row.id)
	var packed := load(String(row.scene_path)) as PackedScene
	if packed == null:
		push_error("RunRoot: cannot load arena '%s'" % row.scene_path)
		return
	var arena := packed.instantiate() as Node3D
	if arena == null:
		push_error("RunRoot: arena root of '%s' is not a Node3D" % row.scene_path)
		return
	# Se guarda ANTES del add_child: el _enter_tree del scatter y el _ready
	# de la arena corren dentro del add_child, y ambos vuelven a
	# arena_root() (directo o por Pools).
	_arena = arena
	GameConfig.selected_map_id = map_id
	if not RunState.visited_map_ids.has(map_id):
		RunState.visited_map_ids.append(map_id)
	_arena_host.add_child(arena)
	_place_party()
	RunState.stage_changed.emit(RunState.stage_index, map_id)


## Pone a cada raider (de pie o derribado) en el punto de aparición de la
## etapa. Lo delega en el bloque de partida, dueño del anillo de co-op.
func _place_party() -> void:
	var origin := Vector3.ZERO
	var arena := _arena as Arena
	if arena != null:
		origin = arena.spawn_origin()
	get_tree().call_group("run_systems", "place_party", origin)


## El cambio en sí, que ScreenFade espera entre el fundido de entrada y el
## de salida. Cada paso va en este orden a propósito; ver cada función.
func _swap_stage() -> void:
	var from_index := RunState.stage_index
	var from_id := String(MapCatalog.MAP_LIBRARY[from_index % MapCatalog.MAP_LIBRARY.size()].id)
	var was_paused := _freeze_world()
	# Lo que lleva el equipo, leído de los nodos vivos (la otra mitad del par
	# se imprime al final).
	_print_carry()
	_tear_down_stage()
	# Deja que el motor asiente las liberaciones antes de contarlas.
	for i in SWAP_SETTLE_FRAMES:
		await get_tree().process_frame
	_print_sweep()
	_free_arena()
	var next_index := _advance_counters(from_index)
	_load_stage()
	_announce_stage(from_index, next_index)
	_print_carry()
	if not was_paused and not _other_blocking_ui_open():
		get_tree().paused = false
	_swapping = false
	# from_id solo lo lee la narración de depuración de abajo.
	if OS.get_environment("BONK_PROBE_DEBUG") == "1":
		print("RunRoot: left %s" % from_id)


## Cierra los menús que se pueden cerrar y congela el mundo. Devuelve si el
## árbol ya estaba pausado ANTES del cambio.
func _freeze_world() -> bool:
	# Primero los menús, antes de leer la pausa: VendorUi y RouletteUi
	# cuelgan de la ARENA, _free_arena() los libera sin correr su _close()
	# (lo único que devuelve la pausa), y con uno abierto `was_paused` saldría
	# true y el árbol quedaría pausado sin nada vivo que lo despause.
	# `dismiss()` es el gancho del grupo "blocking_ui_closable". Los menús
	# que NO se cierran (las cartas) conservan su pausa y los revisa
	# _other_blocking_ui_open() al final.
	get_tree().call_group(&"blocking_ui_closable", "dismiss")
	# La pausa también corta la entrada del jugador, así ningún raider camina
	# hacia una escena que se está liberando.
	var was_paused := get_tree().paused
	get_tree().paused = true
	# La pausa sola NO basta: process_mode se HEREDA, y el harness cuelga
	# toda la partida de un nodo que siempre procesa, así que ahí el spawner
	# seguiría metiendo enemigos en el barrido. Se detiene explícitamente;
	# el director se detiene con on_stage_ended (_tear_down_stage).
	get_tree().call_group("enemy_spawner", "set_physics_process", false)
	return was_paused


## Desarma la etapa: enemigos, objetos de pool, lo del director y los
## objetos de etapa sueltos.
func _tear_down_stage() -> void:
	_free_enemies()
	Pools.release_all_live()
	get_tree().call_group("world_director", "on_stage_ended")
	_free_stage_props()


## Libera la arena. free() y no queue_free(): la etapa siguiente se construye
## enseguida y dos arenas vivas responderían a los grupos "arena_bounds" y
## "enemy_spawner".
func _free_arena() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena_host.remove_child(_arena)
		_arena.free()
	_arena = null


## Avanza los contadores de etapa (y de vuelta al pasar del último mapa al
## primero). Devuelve el índice de la etapa siguiente.
func _advance_counters(from_index: int) -> int:
	var next_index := (from_index + 1) % MapCatalog.MAP_LIBRARY.size()
	if next_index == 0:
		RunState.lap += 1
		RunState.laps_completed += 1
	RunState.stage_index = next_index
	RunState.begin_stage()
	return next_index


## Anuncia la etapa nueva. Numeración desde 1 en todo lo que ve el jugador
## (o un log de soak).
func _announce_stage(from_index: int, next_index: int) -> void:
	var to_id := String(MapCatalog.MAP_LIBRARY[next_index].id)
	get_tree().call_group("boss_ui", "announce_major", "Etapa %d — %s" % [
			RunState.stage_index + 1,
			String(MapCatalog.by_id_or_default(to_id).display_name)])
	get_tree().call_group("hud", "show_stage_tag", RunState.stage_index, RunState.lap)
	# Log de una línea para los soaks headless.
	print("Stage advanced: %d -> %d (%s) at %.1fs" % [
			from_index + 1, next_index + 1, to_id, RunState.run_time])


## Balizas todavía en pie. on_stage_ended LIBERA sus balizas, así que un
## valor distinto de cero aquí es una fuga real.
func _live_beacons() -> int:
	var director := get_tree().get_first_node_in_group("world_director")
	if director == null or not director.has_method("beacon_count"):
		return 0
	return int(director.call("beacon_count"))


## Libera de inmediato cada cuerpo enemigo. free() y no queue_free() para
## que el barrido cuente lo que de verdad se fue: un free en cola cae al
## final del cuadro, después del conteo.
func _free_enemies() -> void:
	for group: StringName in [&"enemies", &"boss"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.get_parent().remove_child(node)
				node.free()


## Objetos del mundo de la etapa que NO son hijos de la escena de arena: lo
## que el director y el mundo soltaron durante la etapa. Cuelgan de la arena
## (StageLayout.stage_parent()), así que casi todos morirían con ella,
## pero el barrido corre ANTES de liberar la arena, y una etapa que filtra
## uno de estos es justo lo que el barrido detecta.
func _free_stage_props() -> void:
	for group: StringName in STAGE_PROP_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				var parent := node.get_parent()
				if parent != null:
					parent.remove_child(node)
				node.free()
	# Cofres, portales, ruletas y manantiales no tienen grupo propio: son
	# Interactables colgados de la arena, y el recorrido de abajo los atrapa.
	# Las balizas las libera el director en on_stage_ended.
	var arena := arena_root()
	if arena != null:
		for node: Node in _stage_leftovers(arena):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.get_parent().remove_child(node)
				node.free()


## Interactables que siguen en pie dentro de `root`. Recursivo porque una
## arena guarda sus santuarios de escena bajo un nodo "Interactables" y el
## director cuelga los suyos directo de la raíz.
func _stage_leftovers(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		if child is Interactable:
			found.append(child)
			continue
		found.append_array(_stage_leftovers(child))
	return found


## Lo que sigue vivo justo antes de que se vaya la arena. Todo contador
## debe ser cero: uno distinto es una fuga que seguiría al equipo a la etapa
## siguiente. El formato de la línea es fijo: tools/verificar.sh la compara
## entera.
func _print_sweep() -> void:
	var chests := 0
	var arena := arena_root()
	if arena != null:
		for node: Node in _stage_leftovers(arena):
			if node is Chest:
				chests += 1
	var beacons := _live_beacons()
	print(("Stage sweep: enemies=%d gems=%d orbs=%d chests=%d altars=%d beacons=%d"
			+ " pickups=%d boxes=%d vendors=%d possessed=%d") % [
			get_tree().get_node_count_in_group(&"enemies"),
			get_tree().get_node_count_in_group(XpGem.LIVE_GROUP),
			get_tree().get_node_count_in_group(HealthOrb.LIVE_GROUP),
			chests,
			get_tree().get_node_count_in_group(&"altars"),
			beacons,
			get_tree().get_node_count_in_group(&"powerup_pickups"),
			get_tree().get_node_count_in_group(&"pet_boxes"),
			get_tree().get_node_count_in_group(&"vendors"),
			get_tree().get_node_count_in_group(&"possessed")])


## El progreso del equipo, calculado de los nodos VIVOS a ambos lados del
## cambio. Se imprime dos veces a propósito: dos líneas iguales prueban que
## cambiar de etapa no le cuesta nada al equipo. Nunca en caché: una copia
## diría lo que quisimos llevar, no lo que cruzó de verdad.
func _print_carry() -> void:
	var weapons := 0
	var tomes := 0
	var items := 0
	var points := 0
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var mount := node.get_node_or_null("Weapons")
			if mount != null:
				for child: Node in mount.get_children():
					if child is WeaponBase:
						weapons += 1
			var stats := PlayerStats.find_in(node)
			if stats != null:
				tomes += stats.distinct_tome_count()
			var bag := ItemBag.find_in(node)
			if bag != null:
				items += bag.carried_ids().size()
			var purse: Variant = node.get("points")
			if purse != null:
				points += int(purse)
	print("Stage carry: level=%d weapons=%d tomes=%d items=%d points=%d" % [
			RunState.level, weapons, tomes, items, points])


## Algún miembro de "ui_blocking" con la pausa tomada ahora (las cartas, la
## pantalla de fin). El cambio no debe devolverle el mundo a una pantalla que
## tomó la pausa para sí.
func _other_blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if not node.has_method(&"is_blocking"):
			continue
		if node.call(&"is_blocking") == true:
			return true
	return false
