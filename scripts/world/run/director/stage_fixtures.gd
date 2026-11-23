class_name StageFixtures
extends Node
## Objetos de inicio de cada etapa: el inicio irregular (quita al azar
## altares de la escena), los portales, los altares, ruletas, cofres extra,
## manantiales y vendedores repartidos por todo el mapa (todos solo salen
## aquí, al empezar), unos pocos cofres gratis y, con suerte, un bloque de
## la suerte.
## Es el nodo RunSystems.tscn > WorldDirector > StageFixtures: sus números
## se editan en el Inspector de ese nodo. El director llama a place() en
## cada etapa, después de mover los POI y antes de que el scatter ponga
## sus props: todo lo que pone entra a "scatter_keepout", así el scatter no
## le planta props ni estructuras encima. Todo sale del RNG de la partida:
## el orden de place() es parte del sorteo de cada semilla.

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")
const CHARGE_SHRINE_SCENE := preload("res://scenes/world/shrines/ChargeShrine.tscn")
const CURSE_SHRINE_SCENE := preload("res://scenes/world/shrines/CurseShrine.tscn")
const PORTAL_SHRINE_SCENE := preload("res://scenes/world/director/PortalShrine.tscn")
const ROULETTE_SHRINE_SCENE := preload("res://scenes/world/shrines/RouletteShrine.tscn")
const SPRING_SHRINE_SCENE := preload("res://scenes/world/shrines/SpringShrine.tscn")
const VENDOR_SCENE := preload("res://scenes/world/Vendor.tscn")
const LUCKY_BLOCK_SCENE := preload("res://scenes/world/chests/LuckyBlock.tscn")
## Grupo de lo que el scatter deja libre de props y estructuras.
const KEEPOUT_GROUP: StringName = &"scatter_keepout"

@export_group("Inicio irregular")
## Probabilidad (0-1) de quitar cada altar de la escena en esta etapa. Los cofres de la escena nunca se quitan.
@export var poi_skip_chance: float = 0.3
## Cofres por etapa, como mínimo, contando los que ya trae el mapa (se sortea entre mínimo y máximo). Son los únicos cofres de la etapa.
@export var start_chests_min: int = 45
## Cofres por etapa, como máximo, contando los que ya trae el mapa.
@export var start_chests_max: int = 50
## Cofres gratis por etapa, como mínimo (se sortea entre mínimo y máximo, entre todos los cofres de inicio).
@export var free_start_chests_min: int = 7
## Cofres gratis por etapa, como máximo.
@export var free_start_chests_max: int = 8


@export_group("Portales y ruletas")
## Portales al inicio de la etapa. No van en pares: cada uno lleva a un punto al azar del mapa.
@export var portal_count: int = 10
## Puntos que se prueban por portal; se queda con el más lejano a los otros portales (más = más repartidos).
@export var portal_spread_tries: int = 20
## Ruletas al inicio de la etapa.
@export var roulette_count: int = 20

@export_group("Altares de inicio")
## Altares de carga al empezar la etapa, contando los que ya trae el mapa.
@export var start_charge_altars: int = 20
## Altares demoníacos al empezar la etapa, contando los que ya trae el mapa.
@export var start_demonic_altars: int = 20

@export_group("Manantiales y vendedores")
## Manantiales al empezar la etapa, repartidos por el mapa (es el único lugar de donde salen).
@export var start_springs: int = 15
## Vendedores al empezar la etapa, como mínimo (se sortea entre mínimo y máximo). Cada uno es de power-ups o de objetos, al azar.
@export var start_vendors_min: int = 15
## Vendedores al empezar la etapa, como máximo.
@export var start_vendors_max: int = 20

@export_group("Sorpresas de inicio")
## Probabilidad (0-1) de que la etapa empiece con un bloque de la suerte.
@export var lucky_block_start_chance: float = 0.5

var _layout: StageLayout = null


## Pone los objetos de inicio de la etapa. Este orden es parte del sorteo:
## no cambiarlo. El inicio irregular va primero porque quita POI de la
## escena, y sus puntos tienen que quedar libres para lo que sigue.
func place(layout: StageLayout) -> void:
	_layout = layout
	_randomize_starting_pois()
	_spawn_portals()
	_spawn_spread_pois()
	_make_start_chests_free()
	_spawn_start_lucky_blocks()


## Inicio irregular: quita al azar altares de la escena (los cofres se
## quedan todos).
func _randomize_starting_pois() -> void:
	var removed := 0
	for node: Node in get_tree().get_nodes_in_group(KEEPOUT_GROUP):
		if (node is ChargeShrine or node is GreedShrine) and randf() < poi_skip_chance:
			node.queue_free()
			removed += 1
	_layout.refresh_placed_points()
	print("Start layout: %d POI(s) skipped" % removed)


## Altares de carga, demoníacos, ruletas y cofres extra repartidos por todo
## el mapa: se ponen intercalados (uno de cada tipo por vuelta) y cada uno
## en el punto libre más lejano a lo ya puesto, así ningún tipo se amontona.
## Los altares completan start_charge_altars y start_demonic_altars contando
## los que el mapa ya trae.
func _spawn_spread_pois() -> void:
	var scenes: Array[PackedScene] = [CHARGE_SHRINE_SCENE, CURSE_SHRINE_SCENE,
			ROULETTE_SHRINE_SCENE, CHEST_SCENE, SPRING_SHRINE_SCENE, VENDOR_SCENE]
	var left: Array[int] = [
		_missing(&"charge_altars", start_charge_altars),
		_missing(&"demonic_altars", start_demonic_altars),
		roulette_count,
		maxi(randi_range(start_chests_min, start_chests_max) - _chest_count(), 0),
		start_springs,
		randi_range(start_vendors_min, start_vendors_max),
	]
	var placed: Array[int] = [0, 0, 0, 0, 0, 0]
	var pending := true
	while pending:
		pending = false
		for i in scenes.size():
			if left[i] <= 0:
				continue
			pending = true
			left[i] -= 1
			_spread_one(scenes[i])
			placed[i] += 1
	print("Start altars placed: %d charge, %d demonic" % [placed[0], placed[1]])
	print("Start spread: %d roulette(s), %d extra chest(s), %d spring(s), %d vendor(s)" % [
			placed[2], placed[3], placed[4], placed[5]])


## Cofres que ya hay en la etapa (los de la escena).
func _chest_count() -> int:
	var have := 0
	for node: Node in get_tree().get_nodes_in_group(KEEPOUT_GROUP):
		if node is Chest and not node.is_queued_for_deletion():
			have += 1
	return have


## Cuántos faltan para que el grupo `group` tenga `target` nodos vivos.
func _missing(group: StringName, target: int) -> int:
	var have := 0
	for node: Node in get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			have += 1
	return maxi(target - have, 0)


## Pone una instancia de `scene` en el punto más repartido del mapa.
func _spread_one(scene: PackedScene) -> void:
	var node := scene.instantiate() as Node3D
	if node is Vendor:
		# ANTES de entrar al árbol: Vendor._ready lo lee para su texto y color.
		var kind: Dictionary = Vendor.VENDOR_LIBRARY[randi() % Vendor.VENDOR_LIBRARY.size()]
		node.set("kind", String(kind.id))
	_layout.stage_parent().add_child(node)
	var interactable := node as Interactable
	node.global_position = _layout.claim_spread_point(node,
			interactable.footprint_reach() if interactable != null else 0.0)
	_keep_clear(node)


## Hace gratis entre free_start_chests_min y free_start_chests_max cofres al
## azar de todos los de inicio (los de la escena y los extra).
func _make_start_chests_free() -> void:
	var chests: Array[Chest] = []
	for node: Node in get_tree().get_nodes_in_group(KEEPOUT_GROUP):
		if node is Chest and not node.is_queued_for_deletion():
			chests.append(node as Chest)
	chests.shuffle()
	var count := mini(randi_range(free_start_chests_min, free_start_chests_max), chests.size())
	for i in count:
		chests[i].make_free()
	print("Start chests: %d total, %d free" % [chests.size(), count])


## Portales repartidos por todo el mapa (PortalShrine.tscn): cada uno queda
## lo más lejos posible de los ya puestos. No tienen pareja: cada viaje
## lleva a un punto al azar.
func _spawn_portals() -> void:
	var spots: Array[Vector2] = []
	for i in portal_count:
		var portal := PORTAL_SHRINE_SCENE.instantiate() as PortalShrine
		# El nombre sale en el log "Portal used:".
		portal.name = "Portal%d" % (i + 1)
		_layout.stage_parent().add_child(portal)
		# Su marco ocupa unos 4 m: las distancias se guardan desde ese borde.
		portal.global_position = _layout.claim_far_point(portal.footprint_reach(), spots,
				portal_spread_tries)
		spots.append(Vector2(portal.global_position.x, portal.global_position.z))
		_keep_clear(portal)
	if portal_count > 0:
		print("Portals placed: %d" % portal_count)


## 0-1 bloques de la suerte. Con probabilidad 0 no se tira ningún dado: el
## RNG de la partida es uno solo y un dado de más mueve todo lo que se
## sortea después.
func _spawn_start_lucky_blocks() -> void:
	if lucky_block_start_chance <= 0.0 or randf() >= lucky_block_start_chance:
		return
	_keep_clear(_layout.spawn_at(LUCKY_BLOCK_SCENE, _layout.claim_clear_point()))


## Mete `node` (recién puesto) en KEEPOUT_GROUP: el scatter viste la arena
## después de place() y lee ese grupo para saber dónde no plantar nada.
func _keep_clear(node: Node) -> void:
	if node != null:
		node.add_to_group(KEEPOUT_GROUP)
