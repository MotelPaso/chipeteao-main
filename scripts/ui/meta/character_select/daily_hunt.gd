class_name DailyHunt
extends RefCounted
## Cacería diaria: la partida con semilla del día. El personaje sale de la
## fecha (de forma determinista, entre los desbloqueados de ESTE jugador) y
## la semilla hace iguales el mundo, las cartas y las apariciones para todos
## ese día. Siempre solo y en el Bosque Hueco. Se puede reintentar: queda la
## mejor marca del día. Solo funciones estáticas; nunca va en una escena.

## Prefijo de la llave de SaveData con la mejor marca de una fecha
## ("daily_best_2026-11-06"). RunManager la escribe con este mismo nombre.
const BEST_STAT_PREFIX := "daily_best_"


## Fecha de hoy, "AAAA-MM-DD": la llave de la diaria.
static func today_id() -> String:
	return Time.get_date_string_from_system()


## Mejor marca de hoy (0 si todavía no se jugó).
static func best_today() -> int:
	return SaveData.stat(BEST_STAT_PREFIX + today_id())


## Deja GameConfig y Coop listos para la diaria de hoy. Devuelve false, sin
## tocar nada, si no hay ningún personaje desbloqueado. El RandomNumberGenerator
## es propio y se siembra con la fecha: la misma fecha elige el mismo raider.
static func configure_today() -> bool:
	var date_id := today_id()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(date_id)
	var characters: Array[String] = []
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		if SaveData.is_unlocked(String(character.id)):
			characters.append(String(character.id))
	if characters.is_empty():
		return false
	GameConfig.daily_mode = true
	GameConfig.daily_seed = int(hash(date_id))
	GameConfig.daily_date = date_id
	GameConfig.selected_character_id = characters[rng.randi() % characters.size()]
	# La diaria empieza en el bosque como toda partida; lo que la hace igual
	# para todos ese día es la semilla, no el mapa.
	GameConfig.selected_map_id = MapCatalog.DEFAULT_ID
	GameConfig.start_map_id = MapCatalog.DEFAULT_ID
	Coop.configure(1, [Coop.KEYBOARD_DEVICE] as Array[int],
			[GameConfig.selected_character_id] as Array[String])
	return true
