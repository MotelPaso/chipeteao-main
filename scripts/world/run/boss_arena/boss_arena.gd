class_name BossArena
extends Arena
## Raíz del CAMPO DE BATALLA propio de un jefe (una escena de
## scenes/world/boss_arenas/). Es una arena, pero no es una etapa: el equipo
## llega desde el mapa de la etapa, pelea con el jefe y vuelve. BossArenaHost
## la cuelga de ArenaHost mientras el mapa de la etapa espera fuera del árbol.
##
## Por eso NO le avisa al WorldDirector (no llama a on_stage_started): el
## director, el clima, la niebla y el minimapa siguen siendo los de la etapa,
## y aquí no hay eventos ni POIs que barajar.
##
## Contrato de la escena (lo que BossArenaHost y el resto del juego esperan):
##   - esta raíz, con su map_id (aquí es el nombre de la arena en los logs,
##     «Boss arena: left … for <map_id>»: en inglés y sin espacios, y no es
##     una fila de MapCatalog);
##   - un WorldEnvironment y un DirectionalLight3D propios;
##   - un nodo de límites en el grupo "arena_bounds" (BossField);
##   - un Terrain (después de los límites en el árbol, como en un mapa);
##   - un EnemySpawner con `dormant` encendido (el Tiempo detenido pasa por él);
##   - un Marker3D "SpawnPoint" (donde aterriza el equipo), uno "BossPoint"
##     (donde aparece el jefe) y uno "PortalPoint" (cerca de donde se abre el
##     portal de salida).

## Nombres de los Marker3D hijos (ver el contrato de arriba).
const BOSS_POINT_NAME: String = "BossPoint"
const PORTAL_POINT_NAME: String = "PortalPoint"


func _ready() -> void:
	# Sin super(): Arena._ready le entrega la arena al WorldDirector, y esta no
	# es una etapa. El grupo sí: Pools, WorldFreeze y RunRoot la buscan por él.
	add_to_group("arena_root")


## Posición de mundo donde aparece el jefe, a ras de suelo.
func boss_origin() -> Vector3:
	return _grounded(BOSS_POINT_NAME, global_position)


## Posición de mundo alrededor de la cual se abre el portal de salida.
func portal_origin() -> Vector3:
	return _grounded(PORTAL_POINT_NAME, spawn_origin())


## El nodo del que cuelga el jefe: el spawner de la arena (como en un mapa) o,
## si la escena no trae uno, esta raíz.
func boss_parent() -> Node:
	for child: Node in get_children():
		if child is EnemySpawner:
			return child
	return self


## El marcador `marker_name` bajado al suelo, o `fallback` si la escena no lo trae.
func _grounded(marker_name: String, fallback: Vector3) -> Vector3:
	var marker := get_node_or_null(marker_name) as Node3D
	if marker == null:
		return fallback
	var at := marker.global_position
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		terrain.ensure_built()
		at.y = terrain.height_at(at.x, at.z)
	return at
