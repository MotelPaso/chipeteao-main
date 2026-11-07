class_name StageFixtures
extends Node
## Objetos de inicio de cada etapa: el inicio irregular (quita al azar
## cofres y altares de la escena, hace gratis algunos cofres y suma cofres
## extra), los portales en pares, las ruletas y, con suerte, una caja de
## mascota, un altar de evento y un bloque de la suerte.
## Es el nodo RunSystems.tscn > WorldDirector > StageFixtures: sus números
## se editan en el Inspector de ese nodo. El director llama a place() en
## cada etapa, después de mover los POI y antes de que el scatter ponga
## sus props. Todo sale del RNG de la partida: el orden de place() es
## parte del sorteo de cada semilla.

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")
const PORTAL_SHRINE_SCENE := preload("res://scenes/world/director/PortalShrine.tscn")
const ROULETTE_SHRINE_SCENE := preload("res://scenes/world/shrines/RouletteShrine.tscn")
const PET_BOX_SCENE := preload("res://scenes/world/PetBox.tscn")
const EVENT_ALTAR_SCENE := preload("res://scenes/world/shrines/EventAltar.tscn")
const LUCKY_BLOCK_SCENE := preload("res://scenes/world/chests/LuckyBlock.tscn")

@export_group("Inicio irregular")
## Probabilidad (0-1) de quitar cada cofre o altar de la escena en esta
## etapa (el primer cofre de suelo siempre se queda).
@export var poi_skip_chance: float = 0.3
## Cofres extra al empezar la etapa, como mínimo (se sortea entre mínimo y máximo).
@export var extra_start_chests_min: int = 0
## Cofres extra al empezar la etapa, como máximo.
@export var extra_start_chests_max: int = 2
## Probabilidad (0-1) de que cada cofre de inicio (de la escena o extra) sea gratis.
@export var free_start_chest_chance: float = 0.15

@export_group("Portales y ruletas")
## Portales al inicio de la etapa; van en pares, así que conviene un número par.
@export var portal_count: int = 4
## Ruletas al inicio de la etapa.
@export var roulette_count: int = 1

@export_group("Sorpresas de inicio")
## Probabilidad (0-1) de que la etapa empiece con una caja de mascota.
@export var start_pet_box_chance: float = 0.5
## Probabilidad (0-1) de que la etapa empiece con un altar de evento.
@export var start_event_altar_chance: float = 0.5
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
	_spawn_roulettes()
	_spawn_start_pet_boxes()
	_spawn_start_event_altars()
	_spawn_start_lucky_blocks()


## Inicio irregular: quita al azar cofres y altares de la escena (siempre
## queda el primer cofre de suelo), hace gratis algunos cofres y suma
## cofres extra.
func _randomize_starting_pois() -> void:
	var removed := 0
	var chests_kept := 0
	var freebies := 0
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		if node is Chest or node is ChargeShrine or node is GreedShrine:
			if node is Chest and chests_kept == 0:
				chests_kept += 1  # el primer cofre de suelo siempre se queda
				if _make_start_chest_free(node as Chest):
					freebies += 1
				continue
			if randf() < poi_skip_chance:
				node.queue_free()
				removed += 1
			elif node is Chest:
				chests_kept += 1
				if _make_start_chest_free(node as Chest):
					freebies += 1
	_layout.refresh_placed_points()
	var extra := randi_range(extra_start_chests_min, extra_start_chests_max)
	for i in extra:
		var chest := CHEST_SCENE.instantiate() as Chest
		# ANTES de add_child: el cofre elige su tinte y su texto en _ready.
		if randf() < free_start_chest_chance:
			chest.free_open = true
			freebies += 1
		_layout.stage_parent().add_child(chest)
		chest.global_position = _layout.claim_clear_point()
	print("Start layout: %d POI(s) skipped, %d extra chest(s), %d free" % [
			removed, extra, freebies])


## Hace gratis un cofre de la escena que ya pasó su _ready. Devuelve true si cambió.
func _make_start_chest_free(chest: Chest) -> bool:
	if chest == null or randf() >= free_start_chest_chance:
		return false
	chest.make_free()
	return true


## Portales en pares al azar (PortalShrine.tscn). El color sale del índice
## del par de creación (i / 2) y los pares se forman después de mezclar:
## el color no indica cuál es la pareja.
func _spawn_portals() -> void:
	var count := portal_count - (portal_count % 2)
	var portals: Array[PortalShrine] = []
	for i in count:
		var portal := PORTAL_SHRINE_SCENE.instantiate() as PortalShrine
		# El nombre sale en el log "Portal used:".
		portal.name = "Portal%d" % (i + 1)
		portal.pair_index = i / 2
		_layout.stage_parent().add_child(portal)
		portal.global_position = _layout.claim_clear_point()
		portals.append(portal)
	portals.shuffle()
	for i in range(0, portals.size() - 1, 2):
		portals[i].twin = portals[i + 1]
		portals[i + 1].twin = portals[i]
	if count > 0:
		print("Portals placed: %d (%d pairs)" % [count, count / 2])


func _spawn_roulettes() -> void:
	for i in roulette_count:
		_layout.spawn_at(ROULETTE_SHRINE_SCENE, _layout.claim_clear_point())


## 0-1 cajas de mascota: una mascota tiene que sentirse como algo que el
## mapa ofrece, no algo que siempre está.
## Con probabilidad 0 no se tira ningún dado (aquí ni en las dos de abajo):
## el RNG de la partida es uno solo y un dado de más mueve todo lo que se
## sortea después.
func _spawn_start_pet_boxes() -> void:
	if start_pet_box_chance <= 0.0 or randf() >= start_pet_box_chance:
		return
	_layout.spawn_at(PET_BOX_SCENE, _layout.claim_clear_point())


## 0-1 altares de evento, como la caja de mascota.
func _spawn_start_event_altars() -> void:
	if start_event_altar_chance <= 0.0 or randf() >= start_event_altar_chance:
		return
	_layout.spawn_at(EVENT_ALTAR_SCENE, _layout.claim_clear_point())


## 0-1 bloques de la suerte, como la caja de mascota.
func _spawn_start_lucky_blocks() -> void:
	if lucky_block_start_chance <= 0.0 or randf() >= lucky_block_start_chance:
		return
	_layout.spawn_at(LUCKY_BLOCK_SCENE, _layout.claim_clear_point())
