class_name MapCatalog
extends RefCounted
## Catálogo de mapas (biomas) de una incursión. Un bioma nuevo es una fila aquí
## más su escena de arena (script raíz arena.gd).
##
## EL ORDEN DE ESTA LISTA ES EL ORDEN DE LA INCURSIÓN: cada incursión empieza
## en DEFAULT_ID (la primera fila) y baja por la lista, volviendo arriba con
## vuelta + 1. No hay selector de mapa ni desbloqueo, así que un bioma
## insertado aquí cambia la progresión de todos de inmediato.
##
## Se puede cambiar libremente: display_name, blurb, palette y el orden de las
## filas.
## Llave interna, NUNCA la cambies: id. Va dentro de los contadores
## runs_on_<id> y victories_<id> de SaveData, que las misiones de mapa nombran
## en QuestCatalog, y debe ser igual al export map_id de su escena de arena.
## scene_path debe apuntar a una escena que exista.
##
## Campos de cada fila:
##   id: llave interna (ver arriba). Nunca se muestra.
##   display_name, blurb: texto del jugador (cartel de etapa, pantalla final).
##   scene_path: escena de arena que RunRoot instancia para esa etapa.
##   palette: colores del ambiente del bioma (los usa la UI).

## Primera etapa de cada incursión y respaldo para un id desconocido.
const DEFAULT_ID: String = "hollow_woods"

const MAP_LIBRARY: Array[Dictionary] = [
	{
		"id": "hollow_woods", "display_name": "Bosque Hueco",
		"blurb": "Claros musgosos bajo un dosel verde y paciente.",
		"scene_path": "res://scenes/world/HollowWoods.tscn",
		"palette": [Color(0.3, 0.56, 0.3), Color(0.15, 0.34, 0.19),
				Color(0.44, 0.3, 0.2), Color(0.79, 0.83, 0.72)],
	},
	{
		"id": "ash_dunes", "display_name": "Dunas de Ceniza",
		"blurb": "Arena calcinada, monumentos inclinados, un horizonte que zumba.",
		"scene_path": "res://scenes/world/AshDunes.tscn",
		"palette": [Color(0.82, 0.66, 0.4), Color(0.68, 0.36, 0.26),
				Color(0.24, 0.55, 0.45), Color(0.94, 0.66, 0.42)],
	},
	{
		"id": "gloomfen", "display_name": "Ciénaga Lóbrega",
		"blurb": "Islas de musgo anegado bajo un cielo que nunca termina de aclarar.",
		"scene_path": "res://scenes/world/Gloomfen.tscn",
		"palette": [Color(0.16, 0.28, 0.19), Color(0.1, 0.17, 0.14),
				Color(0.35, 0.85, 0.6), Color(0.42, 0.55, 0.46)],
	},
]


## Índice id -> fila armado al primer uso (ver CatalogIndex): RunRoot resuelve
## una fila en cada etapa y la pantalla final una por cada mapa que nombra.
static var _by_id: Dictionary[String, Dictionary] = {}


## Fila con ese id, o un Dictionary vacío si no existe.
static func by_id(map_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(MAP_LIBRARY)
	return _by_id.get(map_id, {})


## Posición de un mapa en el orden de la incursión, o 0 (la primera etapa) para
## un id desconocido. RunRoot avanza por índice y da la vuelta con
## MAP_LIBRARY.size(), así que el orden de la biblioteca ES el de la incursión.
static func index_of(map_id: String) -> int:
	for i: int in MAP_LIBRARY.size():
		if String(MAP_LIBRARY[i].id) == map_id:
			return i
	return 0


## Fila con ese id, o la del mapa por defecto si el id es desconocido.
static func by_id_or_default(map_id: String) -> Dictionary:
	var row := by_id(map_id)
	return row if not row.is_empty() else by_id(DEFAULT_ID)
