class_name BossArenaCatalog
extends RefCounted
## Las ARENAS DE JEFE: qué jefes pelean en un campo de batalla propio, fuera
## del mapa de la etapa. Una fila por jefe. Cuando al jefe de una fila le toca
## llegar (el EnemySpawner del mapa lo nombra en su hueco de jefe), no aparece
## en el mapa: el equipo viaja a su arena, pelea ahí y vuelve por un portal
## (lo lleva BossArenaHost; ver «Arenas de jefe» en docs/ARQUITECTURA.md).
## Un jefe sin fila llega al mapa como siempre.
##
## EDITA AQUÍ. Llaves internas (NUNCA las cambies): `id` y los valores de
## `exit`. Los demás campos se pueden cambiar con libertad:
##   boss_scene       escena del jefe. Es la que nombra el EnemySpawner del
##                    mapa (mini_boss_scene): con ella se encuentra la fila.
##   arena_scene      escena de su campo de batalla (raíz BossArena).
##   omen_scene       escena del presagio que avisa en el mapa antes del
##                    viaje (raíz BossOmen); "" = sin presagio.
##   omen_seconds     segundos de presagio antes del viaje. Desde ahí los
##                    demás jefes del mapa esperan.
##   cinematic_scene  escena de la cinemática del viaje, del rapto al cartel;
##                    "" = el equipo viaja con un fundido y el jefe llega con
##                    su propia entrada.
##   portal_scene     escena del portal que aparece en la arena cuando el
##                    jefe muere (raíz BossArenaPortal); "" = el equipo
##                    vuelve solo.
##   exit             qué pasa al salir de la arena. "return": el equipo
##                    vuelve al mapa de la etapa, tal como lo dejó.
##   exit_delay       segundos entre la muerte del jefe y el portal (o la
##                    vuelta, sin portal): lo que dura su caída.
const ARENA_LIBRARY: Array[Dictionary] = [
	{
		"id": "blue_lobster",
		"boss_scene": "res://scenes/enemies/BlueLobster.tscn",
		"arena_scene": "res://scenes/world/boss_arenas/ShipGraveyard.tscn",
		"omen_scene": "res://scenes/enemies/blue_lobster/LobsterOmen.tscn",
		"omen_seconds": 30.0,
		"cinematic_scene": "res://scenes/enemies/blue_lobster/LobsterEntrance.tscn",
		"portal_scene": "res://scenes/world/boss_arenas/BossArenaPortal.tscn",
		"exit": "return",
		"exit_delay": 2.5,
	},
]

## Valor de `exit`: volver al mapa de la etapa.
const EXIT_RETURN: String = "return"
## Meta de una instancia donde viaja la escena de la que salió (ver instance_of).
const SCENE_META: StringName = &"boss_arena_scene"


## La fila del jefe cuya escena es `scene`, o vacío si ese jefe no tiene
## arena propia (o `scene` es null). Una fila sin `arena_scene`, o con una
## que no existe, cuenta como sin arena: ese jefe llega al mapa.
static func for_boss(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	for row: Dictionary in ARENA_LIBRARY:
		if String(row.boss_scene) == scene.resource_path:
			return row if ResourceLoader.exists(String(row.get("arena_scene", ""))) else {}
	return {}


## La fila con ese id, o vacío.
static func by_id(id: String) -> Dictionary:
	for row: Dictionary in ARENA_LIBRARY:
		if String(row.id) == id:
			return row
	return {}


## La escena del campo `key` de `row` (boss_scene, arena_scene…), o null si
## la fila no la trae. Una ruta que no carga es un error, no un silencio.
static func scene_of(row: Dictionary, key: String) -> PackedScene:
	var path := String(row.get(key, ""))
	if path.is_empty():
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("BossArenaCatalog: cannot load %s '%s'" % [key, path])
	return scene


## Una instancia de la escena del campo `key` de `row`, o null si la fila no
## la trae. La instancia LLEVA CONSIGO su escena. En un mapa, la escena de un
## jefe la tiene el spawner, que muere después que él; aquí quien la carga la
## suelta enseguida, y si la escena muriera antes que su instancia (al cerrar
## la partida a mitad de un viaje) sus materiales morirían con las mallas
## todavía vivas.
static func instance_of(row: Dictionary, key: String) -> Node:
	var scene := scene_of(row, key)
	if scene == null:
		return null
	var node := scene.instantiate()
	node.set_meta(SCENE_META, scene)
	return node


## El título del jefe de `row`, leído de su escena sin instanciarla (el
## presagio lo nombra antes de que el jefe exista).
static func boss_title(row: Dictionary) -> String:
	var scene := scene_of(row, "boss_scene")
	if scene == null:
		return ""
	var state := scene.get_state()
	for index: int in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == &"boss_title":
			return String(state.get_node_property_value(0, index))
	return ""
