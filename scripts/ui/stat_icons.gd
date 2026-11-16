class_name StatIcons
extends RefCounted
## Iconos de estadística (salud, armadura, velocidad, daño…) que comparten la
## Armería, los Objetos y los Tomos. Cada icono es un SVG propio de
## assets/ui/icons/stats/. Quien dibuja pasa el nombre del stat tal como está
## en el catálogo ("damage", "max_hp"…) y recibe la textura; un stat sin icono,
## o un archivo que falta, devuelve el icono de respaldo sin registrar errores.
##
## Es estático y nunca va en una escena: edita los valores aquí.

## Carpeta de los SVG.
const ICON_DIR := "res://assets/ui/icons/stats/"
## Edita aquí: stat de PlayerStats -> archivo dentro de ICON_DIR. Para un icono
## nuevo, deja el SVG en la carpeta y agrega su fila.
const ICON_FILES: Dictionary[String, String] = {
	"damage": "stat_damage.svg",
	"max_hp": "stat_max_hp.svg",
	"cooldown": "stat_cooldown.svg",
	"move_speed": "stat_move_speed.svg",
	"armor": "stat_armor.svg",
	"luck": "stat_luck.svg",
	"area": "stat_area.svg",
	"crit_chance": "stat_crit_chance.svg",
	"crit_damage": "stat_crit_damage.svg",
	"lifesteal": "stat_lifesteal.svg",
	"evasion": "stat_evasion.svg",
	"projectiles": "stat_projectiles.svg",
	"duration": "stat_duration.svg",
	"xp_gain": "stat_xp_gain.svg",
	"jumps": "stat_jumps.svg",
	"difficulty": "stat_difficulty.svg",
	"gambling": "stat_gambling.svg",
}
## Icono de un stat que no está en ICON_FILES.
const FALLBACK_FILE := "stat_generic.svg"
## Edita aquí: nombre que ve el jugador de cada stat (GLOSARIO), para las
## líneas «qué sube» de Objetos y Tomos.
const LABELS: Dictionary[String, String] = {
	"damage": "Daño",
	"max_hp": "HP máx.",
	"cooldown": "Velocidad de ataque",
	"move_speed": "Velocidad de movimiento",
	"armor": "Armadura",
	"luck": "Suerte",
	"area": "Área de ataque",
	"crit_chance": "Prob. de crítico",
	"crit_damage": "Daño crítico",
	"lifesteal": "Robo de vida",
	"evasion": "Evasión",
	"projectiles": "Proyectiles",
	"duration": "Duración de efectos",
	"xp_gain": "XP ganada",
	"jumps": "Saltos en el aire",
	"difficulty": "Dificultad",
	"gambling": "Azar",
}

## Texturas ya cargadas, por nombre de archivo.
static var _cache: Dictionary[String, Texture2D] = {}


## El icono de ese stat. Nunca falla: sin fila propia devuelve el de respaldo,
## y null solo si tampoco existe el archivo de respaldo.
static func texture(stat: String) -> Texture2D:
	var icon := _load(String(ICON_FILES.get(stat, FALLBACK_FILE)))
	return icon if icon != null else _load(FALLBACK_FILE)


## Nombre que ve el jugador de ese stat, o el propio id si no tiene fila.
static func label(stat: String) -> String:
	return String(LABELS.get(stat, stat))


## Los stats principales de una lista de efectos del catálogo ([{stat,
## amount}]), en su orden y sin repetir, hasta `limit`.
static func main_stats(effects: Array, limit: int = 2) -> Array[String]:
	var stats: Array[String] = []
	for effect: Variant in effects:
		if not effect is Dictionary:
			continue
		var stat := String((effect as Dictionary).get("stat", ""))
		if stat.is_empty() or stats.has(stat):
			continue
		stats.append(stat)
		if stats.size() >= limit:
			break
	return stats


static func _load(file_name: String) -> Texture2D:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := ICON_DIR + file_name
	var icon: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		icon = load(path) as Texture2D
	_cache[file_name] = icon
	return icon
