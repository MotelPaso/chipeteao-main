class_name Arena
extends Node3D
## Raíz de una escena de bioma (Hollow Woods, Ash Dunes, Gloomfen). Una
## arena es SOLO el mundo: suelo, perímetro, fondo, luz, verticalidad,
## interactuables de escena, scatter, spawner y ambiente. El bloque de
## partida (Player, RunManager, WorldDirector, HUD, cartas) vive en
## Run.tscn, sobre el ArenaHost bajo el que se instancia esta escena, y
## sobrevive a cada cambio de etapa. La arena es desechable: se construye
## para una etapa y se libera cuando el equipo sale por el portal.
##
## Por eso una arena NO arranca sola (F6 o `--quit-after` sobre el .tscn):
## sin raíz de partida no hay jugador, ni HUD, ni director. Arranca
## `res://scenes/world/Run.tscn` y elige el bioma con
## GameConfig.start_map_id (el harness lo hace con BONK_ARENA).
##
## Ciclo de vida de la etapa, en el orden OBLIGATORIO (lo maneja RunRoot):
##   1. RunRoot instancia esta escena bajo ArenaHost. Los hijos entran al
##      árbol, así el _enter_tree del scatter construye la máscara de la etapa.
##   2. Los hijos corren su _ready (spawner, ambiente, interactuables).
##   3. Este _ready entrega la arena al WorldDirector, que guarda los
##      límites, baraja los POIs del suelo y coloca lo del inicio de partida.
##   4. Luego este _ready deja que el scatter vista la arena, así su lista
##      de keepouts ve las posiciones YA barajadas.

## Nombre del Marker3D hijo donde aparece el slot 0 al llegar el equipo:
## un bioma mueve su punto de llegada sin tocar código. Sin él, el origen.
const SPAWN_POINT_NAME: String = "SpawnPoint"

@export_group("Mapa")
## Id de MapCatalog de este bioma. Cada escena de arena pone el suyo; con él
## RunRoot y el meta llevan sus contadores por mapa.
@export var map_id: String = MapCatalog.DEFAULT_ID


func _ready() -> void:
	# RunRoot encuentra la arena viva por este grupo, nunca por ruta: el hijo
	# de ArenaHost cambia de nombre en cada etapa.
	add_to_group("arena_root")
	get_tree().call_group("world_director", "on_stage_started", self)
	_dress_arena()


## Paso 4 de arriba. Busca el scatter por "arena_bounds" (su grupo) y lo
## filtra a ESTA arena: durante un cambio puede quedar una arena saliente en
## el árbol, y vestirla pondría props en una escena a punto de liberarse.
func _dress_arena() -> void:
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		if node.has_method("place_props") and is_ancestor_of(node):
			node.call("place_props")


## Posición de mundo donde aparece el slot 0. Sin marcador, el origen de la arena.
func spawn_origin() -> Vector3:
	var marker := get_node_or_null(SPAWN_POINT_NAME) as Node3D
	var at := marker.global_position if marker != null else global_position
	# Bajada al relieve: el marcador está a y = 0 y el terreno bajo él es un
	# claro plano, pero "plano" es la altura del terreno ahí, que no tiene
	# por qué ser 0.
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		terrain.ensure_built()
		at.y = terrain.height_at(at.x, at.z)
	return at
