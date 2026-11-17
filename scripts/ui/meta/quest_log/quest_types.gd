class_name QuestTypes
extends RefCounted
## Tipo de cada misión (bajas, jefes, altares…) para el Registro de misiones:
## su título de grupo y su icono. El tipo sale del contador `stat` de la fila
## de QuestCatalog, así el catálogo no necesita un campo nuevo. Un contador
## que no está en ninguna lista cae en el tipo de respaldo (FALLBACK_TYPE).
##
## Es estático y nunca va en una escena: edita los valores aquí.

## Carpeta de los SVG.
const ICON_DIR := "res://assets/ui/icons/quests/"
## Tipo de una misión cuyo contador no aparece en STATS ni en PREFIXES.
const FALLBACK_TYPE := "runs"
## Edita aquí: los tipos en el orden en que salen en el registro. `title` es
## el título del grupo (GLOSARIO) e `icon` un archivo dentro de ICON_DIR.
const TYPES: Array[Dictionary] = [
	{"id": "kills", "title": "Bajas", "icon": "quest_kills.svg"},
	{"id": "bosses", "title": "Jefes", "icon": "quest_bosses.svg"},
	{"id": "shrines", "title": "Altares", "icon": "quest_shrines.svg"},
	{"id": "chests", "title": "Cofres", "icon": "quest_chests.svg"},
	{"id": "characters", "title": "Personajes", "icon": "quest_characters.svg"},
	{"id": "maps", "title": "Mapas", "icon": "quest_maps.svg"},
	{"id": "laps", "title": "Vueltas", "icon": "quest_laps.svg"},
	{"id": "evolutions", "title": "Evoluciones", "icon": "quest_evolutions.svg"},
	{"id": "runs", "title": "Incursiones", "icon": "quest_runs.svg"},
]
## Edita aquí: contador exacto de SaveData -> id de tipo.
const STATS: Dictionary[String, String] = {
	"total_kills": "kills",
	"bosses_killed": "bosses",
	"shrines_used": "shrines",
	"chests_opened": "chests",
	"evolutions_total": "evolutions",
	"any_t2_win": "laps",
	"any_t3_win": "laps",
}
## Edita aquí: prefijo de contador -> id de tipo, para los contadores que
## llevan un id de otro catálogo en el nombre (ver quest_catalog.gd). Se
## prueban en este orden, después de STATS.
const PREFIXES: Array[Array] = [
	["kills_", "kills"],
	["slain_", "bosses"],
	["runs_as_", "characters"],
	["wins_as_", "characters"],
	["runs_on_", "maps"],
	["victories_", "maps"],
	["evo_", "evolutions"],
]

## Texturas ya cargadas, por nombre de archivo.
static var _cache: Dictionary[String, Texture2D] = {}


## Id del tipo de una misión según su contador `stat`.
static func type_of(stat: String) -> String:
	if STATS.has(stat):
		return STATS[stat]
	for pair: Array in PREFIXES:
		if stat.begins_with(String(pair[0])):
			return String(pair[1])
	return FALLBACK_TYPE


## Ids de todos los tipos, en el orden del registro.
static func ids() -> Array[String]:
	var all: Array[String] = []
	for row: Dictionary in TYPES:
		all.append(String(row.id))
	return all


## Título de grupo de ese tipo, o el propio id si no tiene fila.
static func title(type_id: String) -> String:
	return String(_row(type_id).get("title", type_id))


## Icono de ese tipo; null si el tipo no tiene fila o falta el archivo.
static func texture(type_id: String) -> Texture2D:
	var file_name := String(_row(type_id).get("icon", ""))
	if file_name.is_empty():
		return null
	if _cache.has(file_name):
		return _cache[file_name]
	var path := ICON_DIR + file_name
	var icon: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		icon = load(path) as Texture2D
	_cache[file_name] = icon
	return icon


static func _row(type_id: String) -> Dictionary:
	for row: Dictionary in TYPES:
		if String(row.id) == type_id:
			return row
	return {}
