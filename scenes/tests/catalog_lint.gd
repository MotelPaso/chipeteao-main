extends Node
## Lint headless de catálogos: revisa las referencias cruzadas que un soak
## nunca revisa, porque una rota no se cae, simplemente no hace nada. Un
## `passive_stat` mal escrito le quita la pasiva entera a su raider con una
## sola advertencia perdida en el log; una ruta `scene` con un error solo
## falla el día que alguien sortea esa fila; un glifo repetido entre dos
## catálogos muestra la sigla equivocada en el HUD.
##
## Se corre solo con:
##   godot --headless --fixed-fps 60 --quit-after 600 \
##     res://scenes/tests/CatalogLint.tscn
##
## Contrato de salida (tools/verificar.sh busca cada nombre de su lista fija
## LINT_CHECKS, así una comprobación que deja de correr es un fallo y no un
## silencio):
##   Catalog lint: check <name> ok rows=%d   ... una por comprobación que pasa
##   Catalog lint: ok checks=%d              ... solo cuando pasan todas
## Cada fallo es un push_error, que PATRON_ERROR atrapa por su cuenta.
##
## `rows` es la cantidad de entradas que la comprobación REVISÓ de verdad. Cero
## filas es un fallo: una comprobación que recorre una lista vacía pasa por la
## razón equivocada (así pasaría inadvertida una constante renombrada).

## El director no declara class_name: su EVENT_LIBRARY solo se alcanza por
## el recurso del script.
const WORLD_DIRECTOR := preload("res://scripts/world/run/world_director.gd")
## El clima vive en su propio nodo (WeatherDirector): declara los métodos
## start/tick/stop y reexpone WEATHER_CATALOG, que está en WeatherCatalog.
const WEATHER_DIRECTOR := preload("res://scripts/world/run/director/weather_director.gd")
## Se lee como TEXTO para sacar los brazos `match stat:` de _apply_effect: no
## hay reflexión para un bloque match, y copiar la lista aquí serían dos
## verdades que se separan con el próximo stat.
const PLAYER_STATS_PATH := "res://scripts/systems/player_stats.gd"
## Carpetas donde se buscan asignaciones `marker_kind = &"..."`, en .gd y .tscn.
const MARKER_ROOTS: Array[String] = ["res://scripts", "res://scenes"]
## Escenas donde se buscan los `secret_boss_id` de los jefes secretos.
const SCENE_ROOTS: Array[String] = ["res://scenes"]
## Scripts de enemigos: EnemyBase cuenta las bajas en kills_<nombre del script>.
const ENEMY_SCRIPT_ROOTS: Array[String] = ["res://scripts/enemies"]
## Formato de todo id de catálogo: minúsculas, dígitos y guiones bajos.
const ID_PATTERN := "^[a-z0-9_]+$"
## Script del autoload Sfx: su SOUND_LIBRARY se lee por el recurso, así la
## comprobación no depende de que el autoload exista.
const SFX_SCRIPT := preload("res://scripts/systems/autoloads/sfx.gd")
## Carpetas donde se buscan ids de sonido escritos a mano (.gd y .tscn).
const SFX_ROOTS: Array[String] = ["res://scripts", "res://scenes"]
## Llamadas a Sfx que reciben un id; el grupo 1 son sus argumentos hasta el
## paréntesis, un comentario o el fin de línea.
const SFX_CALL_PATTERN := "Sfx\\.(?:play|play_loop|stop_loop|acquire_loop|release_loop|loop_refcount)\\(([^)#]*)"
## Llamadas a MetaScreen.payoff(), que recibe el sonido entre sus argumentos;
## el grupo 1 son esos argumentos, como en SFX_CALL_PATTERN.
const SFX_PAYOFF_PATTERN := "payoff\\(([^)#]*)"
## Constante de sonido en un .gd: un nombre con SOUND o SFX cuyo valor es un
## literal StringName (FANFARE_SFX, SOUND...). BUS_NAME no entra.
const SFX_CONST_PATTERN := "^const \\w*(?:SOUND|SFX)\\w*(?::\\s*StringName)?\\s*:?=\\s*&\"([^\"]+)\""
## Default de un export de sonido (`*_sound` / `*_loop`) en un .gd.
const SFX_EXPORT_PATTERN := "^@export var \\w+_(?:sound|loop): StringName = &\"([^\"]+)\""
## Valor de un export de sonido guardado en un .tscn.
const SFX_SCENE_PATTERN := "^\\w+_(?:sound|loop) = &\"([^\"]+)\"$"
## Un literal StringName dentro de los argumentos de una llamada.
const STRING_NAME_PATTERN := "&\"([^\"]*)\""

var _checks_run: int = 0
var _checks_failed: int = 0


func _ready() -> void:
	_check_ids_unique()
	_check_glyphs_unique()
	_check_paths_exist()
	_check_stat_ids()
	_check_character_weapons()
	_check_director_methods()
	_check_weapon_properties()
	_check_vendor_lucky_roulette_ids()
	_check_marker_labels()
	_check_id_format()
	_check_quest_stats()
	_check_text_numbers()
	_check_text_values()
	_check_item_kinds_unique()
	_check_sfx_ids()
	if _checks_failed == 0:
		print("Catalog lint: ok checks=%d" % _checks_run)
	else:
		print("Catalog lint: FAILED checks=%d failures=%d" % [_checks_run, _checks_failed])
	_quit.call_deferred()


func _quit() -> void:
	get_tree().quit(0 if _checks_failed == 0 else 1)


## Veredicto de una comprobación. `rows` es lo revisado; `failures`, una frase
## por problema. Una comprobación que pasa imprime su línea; una que falla no
## imprime ninguna (así el grep de verificar.sh no la encuentra) y lanza un
## error por fallo.
func _report(check_name: String, rows: int, failures: Array[String]) -> void:
	_checks_run += 1
	if rows <= 0:
		failures = failures.duplicate()
		failures.append("inspected 0 rows — did a constant get renamed?")
	if failures.is_empty():
		print("Catalog lint: check %s ok rows=%d" % [check_name, rows])
		return
	_checks_failed += 1
	for failure: String in failures:
		push_error("Catalog lint: %s — %s" % [check_name, failure])


## Cada biblioteca con llave id, una por una: un id repetido hace que by_id()
## devuelva siempre la primera fila y deja la segunda como contenido muerto.
func _check_ids_unique() -> void:
	var failures: Array[String] = []
	var rows := 0
	for entry: Array in _id_libraries():
		var library_name := String(entry[0])
		var library: Array[Dictionary] = entry[1]
		var key := String(entry[2])
		var seen: Dictionary[String, bool] = {}
		for row: Dictionary in library:
			rows += 1
			var id := String(row.get(key, ""))
			if id.is_empty():
				failures.append("%s has a row with no '%s'" % [library_name, key])
				continue
			if seen.has(id):
				failures.append("%s repeats %s '%s'" % [library_name, key, id])
			seen[id] = true
	_report("ids_unique", rows, failures)


## nombre, biblioteca, llave del id.
func _id_libraries() -> Array[Array]:
	return [
		["WEAPON_LIBRARY", WeaponCatalog.WEAPON_LIBRARY, "id"],
		["EVOLUTION_LIBRARY", EvolutionCatalog.EVOLUTION_LIBRARY, "weapon_id"],
		["TOME_LIBRARY", Tome.TOME_LIBRARY, "id"],
		["ITEM_LIBRARY", ItemCatalog.ITEM_LIBRARY, "id"],
		["POWERUP_LIBRARY", PowerUpCatalog.POWERUP_LIBRARY, "id"],
		["PET_LIBRARY", PetCatalog.PET_LIBRARY, "id"],
		["CHARACTER_LIBRARY", CharacterCatalog.CHARACTER_LIBRARY, "id"],
		["RELIC_LIBRARY", RelicCatalog.RELIC_LIBRARY, "id"],
		["MAP_LIBRARY", MapCatalog.MAP_LIBRARY, "id"],
		["QUEST_LIBRARY", QuestCatalog.QUEST_LIBRARY, "id"],
		["EVENT_LIBRARY", WORLD_DIRECTOR.EVENT_LIBRARY, "id"],
		["WEATHER_CATALOG", WEATHER_DIRECTOR.WEATHER_CATALOG, "id"],
		["PACT_LIBRARY", CurseShrine.PACT_LIBRARY, "id"],
	]


## Los glifos son la sigla de dos letras que pinta un espacio del HUD cuando
## no hay ícono PNG. Se comparan por CONTENIDO, no por biblioteca: el mismo
## «PA» en un arma y en un objeto se lee como la misma cosa. La mascota se
## dibuja en la misma tira que armas y tomos, por eso entra también.
func _check_glyphs_unique() -> void:
	var failures: Array[String] = []
	var rows := 0
	var seen: Dictionary[String, String] = {}
	var sources: Array[Array] = [
		["WEAPON_LIBRARY", WeaponCatalog.WEAPON_LIBRARY, "id"],
		["EVOLUTION_LIBRARY", EvolutionCatalog.EVOLUTION_LIBRARY, "weapon_id"],
		["TOME_LIBRARY", Tome.TOME_LIBRARY, "id"],
		["ITEM_LIBRARY", ItemCatalog.ITEM_LIBRARY, "id"],
		["POWERUP_LIBRARY", PowerUpCatalog.POWERUP_LIBRARY, "id"],
		["PET_LIBRARY", PetCatalog.PET_LIBRARY, "id"],
	]
	for entry: Array in sources:
		var library_name := String(entry[0])
		var library: Array[Dictionary] = entry[1]
		var key := String(entry[2])
		for row: Dictionary in library:
			var glyph := String(row.get("glyph", ""))
			if glyph.is_empty():
				continue
			rows += 1
			var owner_text := "%s/%s" % [library_name, String(row.get(key, "?"))]
			if seen.has(glyph):
				failures.append("glyph '%s' is on both %s and %s"
						% [glyph, seen[glyph], owner_text])
				continue
			seen[glyph] = owner_text
	_report("glyphs_unique", rows, failures)


## Cada ruta res:// que nombra una fila de catálogo. Con
## ResourceLoader.exists() y no FileAccess: un recurso sin su .import no carga.
func _check_paths_exist() -> void:
	var failures: Array[String] = []
	var rows := 0
	var sources: Array[Array] = [
		["WEAPON_LIBRARY", WeaponCatalog.WEAPON_LIBRARY, "id"],
		["PET_LIBRARY", PetCatalog.PET_LIBRARY, "id"],
		["CHARACTER_LIBRARY", CharacterCatalog.CHARACTER_LIBRARY, "id"],
		["MAP_LIBRARY", MapCatalog.MAP_LIBRARY, "id"],
		["ITEM_LIBRARY", ItemCatalog.ITEM_LIBRARY, "id"],
		["POWERUP_LIBRARY", PowerUpCatalog.POWERUP_LIBRARY, "id"],
		["TOME_LIBRARY", Tome.TOME_LIBRARY, "id"],
	]
	var path_keys: Array[String] = ["scene", "weapon_scene", "scene_path", "icon",
			"model_scene"]
	for entry: Array in sources:
		var library_name := String(entry[0])
		var library: Array[Dictionary] = entry[1]
		var key := String(entry[2])
		for row: Dictionary in library:
			for path_key: String in path_keys:
				var path := String(row.get(path_key, ""))
				if path.is_empty():
					continue
				rows += 1
				if not ResourceLoader.exists(path):
					failures.append("%s/%s: %s '%s' does not exist"
							% [library_name, String(row.get(key, "?")), path_key, path])
	_report("paths_exist", rows, failures)


## Cada id de stat que una fila de contenido le pasa a
## PlayerStats._apply_effect. Un id que no es uno de sus brazos cae en `_`,
## que advierte una vez y no aplica NADA: el raider muestra la pasiva en su
## carta y nunca la recibe.
func _check_stat_ids() -> void:
	var accepted := _accepted_stat_ids()
	var failures: Array[String] = []
	var rows := 0
	if accepted.is_empty():
		_report("stat_ids", 0, ["could not read the match arms of _apply_effect"])
		return
	for row: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		rows += 1
		var stat := String(row.get("passive_stat", ""))
		if not accepted.has(stat):
			failures.append("character '%s' passive_stat '%s' is not a PlayerStats effect"
					% [String(row.get("id", "?")), stat])
	var effect_sources: Array[Array] = [
		["ITEM_LIBRARY", ItemCatalog.ITEM_LIBRARY, "id"],
		["POWERUP_LIBRARY", PowerUpCatalog.POWERUP_LIBRARY, "id"],
		["TOME_LIBRARY", Tome.TOME_LIBRARY, "id"],
	]
	for entry: Array in effect_sources:
		var library_name := String(entry[0])
		var library: Array[Dictionary] = entry[1]
		var key := String(entry[2])
		for row: Dictionary in library:
			for effect: Dictionary in (row.get("effects", []) as Array):
				rows += 1
				var stat := String(effect.get("stat", ""))
				if not accepted.has(stat):
					failures.append("%s/%s effect stat '%s' is not a PlayerStats effect"
							% [library_name, String(row.get(key, "?")), stat])
	for row: Dictionary in PetCatalog.PET_LIBRARY:
		rows += 1
		var stat := String(row.get("stat", ""))
		if not accepted.has(stat):
			failures.append("pet '%s' stat '%s' is not a PlayerStats effect"
					% [String(row.get("id", "?")), stat])
	for row: Dictionary in RelicCatalog.RELIC_LIBRARY:
		rows += 1
		var stat := String(row.get("stat", ""))
		if not accepted.has(stat):
			failures.append("relic '%s' stat '%s' is not a PlayerStats effect"
					% [String(row.get("id", "?")), stat])
	for row: Dictionary in ChargeShrine.ALTAR_BOONS:
		rows += 1
		var stat := String(row.get("stat", ""))
		if not accepted.has(stat):
			failures.append("altar boon '%s' stat '%s' is not a PlayerStats effect"
					% [String(row.get("name", "?")), stat])
	for row: Dictionary in CurseShrine.PACT_LIBRARY:
		var benefit: Dictionary = row.get("benefit", {})
		if String(benefit.get("kind", "")) != "boon":
			continue
		rows += 1
		var stat := String(benefit.get("stat", ""))
		if not accepted.has(stat):
			failures.append("pact '%s' benefit stat '%s' is not a PlayerStats effect"
					% [String(row.get("id", "?")), stat])
	_report("stat_ids", rows, failures)


## Los brazos `match stat:` de PlayerStats._apply_effect, leídos del código
## fuente.
func _accepted_stat_ids() -> Dictionary[String, bool]:
	var accepted: Dictionary[String, bool] = {}
	var file := FileAccess.open(PLAYER_STATS_PATH, FileAccess.READ)
	if file == null:
		return accepted
	var text := file.get_as_text()
	file.close()
	var start := text.find("func _apply_effect")
	if start < 0:
		return accepted
	var body := text.substr(start)
	# Los brazos terminan en el comodín `_`; lo que sigue es de la próxima
	# función.
	var end := body.find("\n\t\t_:")
	if end >= 0:
		body = body.substr(0, end)
	var arm := RegEx.create_from_string("(?m)^\\t\\t\"([a-z_]+)\":")
	for found: RegExMatch in arm.search_all(body):
		accepted[found.get_string(1)] = true
	return accepted


## El weapon_node_name de cada raider debe ser el node_name de una fila de
## WeaponCatalog: así el pool de mejoras encuentra el arma que el raider ya
## lleva; si no coincide, ofrece el arma inicial otra vez como carta «nueva».
func _check_character_weapons() -> void:
	var failures: Array[String] = []
	var rows := 0
	var node_names: Dictionary[String, bool] = {}
	for row: Dictionary in WeaponCatalog.WEAPON_LIBRARY:
		node_names[String(row.get("node_name", ""))] = true
	for row: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		rows += 1
		var node_name := String(row.get("weapon_node_name", ""))
		if not node_names.has(node_name):
			failures.append("character '%s' weapon_node_name '%s' is in no WEAPON_LIBRARY row"
					% [String(row.get("id", "?")), node_name])
	_report("character_weapons", rows, failures)


## Cada nombre de método que EVENT_LIBRARY y WEATHER_CATALOG pasan a call().
## Se llaman por call(), así un método renombrado no hace nada y da un error
## por tirada, minutos dentro de la incursión.
func _check_director_methods() -> void:
	var failures: Array[String] = []
	var rows := 0
	var declared: Dictionary[String, bool] = {}
	# Por una variable local tipada Script:
	# `WORLD_DIRECTOR.get_script_method_list()` se lee como «llamar a un
	# método estático de ese script» y no compila. Se quiere la lista de
	# métodos del recurso.
	var director_script: Script = WORLD_DIRECTOR
	for method: Dictionary in director_script.get_script_method_list():
		declared[String(method.get("name", ""))] = true
	for row: Dictionary in WORLD_DIRECTOR.EVENT_LIBRARY:
		rows += 1
		if not row.has("method"):
			if not (row.get("scene") is PackedScene):
				failures.append("event '%s' has neither a method nor a scene"
						% String(row.get("id", "?")))
			continue
		var method := String(row.get("method", ""))
		if not declared.has(method):
			failures.append("event '%s' method '%s' is not declared on WorldDirector"
					% [String(row.get("id", "?")), method])
	var weather_declared: Dictionary[String, bool] = {}
	var weather_script: Script = WEATHER_DIRECTOR
	for method: Dictionary in weather_script.get_script_method_list():
		weather_declared[String(method.get("name", ""))] = true
	for row: Dictionary in WEATHER_DIRECTOR.WEATHER_CATALOG:
		for key: String in ["start", "tick", "stop"]:
			var method := String(row.get(key, ""))
			if method.is_empty():
				continue  # tick y stop son opcionales; vacío = ninguno
			rows += 1
			if not weather_declared.has(method):
				failures.append("weather '%s' %s '%s' is not declared on WeatherDirector"
						% [String(row.get("id", "?")), key, method])
	_report("director_methods", rows, failures)


## Cada propiedad que una carta o una evolución escribe en un arma. Las dos
## pasan por set()/get() por nombre, así un export renombrado convierte la
## carta en una que no hace nada y aun así gasta la subida de nivel.
func _check_weapon_properties() -> void:
	var failures: Array[String] = []
	var rows := 0
	var by_node: Dictionary[String, Dictionary] = {}
	for row: Dictionary in WeaponCatalog.WEAPON_LIBRARY:
		by_node[String(row.get("node_name", ""))] = row
	var properties: Dictionary[String, Dictionary] = {}
	for node_name: String in by_node:
		properties[node_name] = _weapon_properties(String(by_node[node_name].get("scene", "")))
	for row: Dictionary in WeaponCatalog.WEAPON_LIBRARY:
		for extra: Dictionary in (row.get("extra_entries", []) as Array):
			var target := String(extra.get("target", ""))
			if not target.begins_with("weapon/"):
				continue
			var node_name := target.trim_prefix("weapon/")
			var property := String(extra.get("property", ""))
			rows += 1
			if not properties.has(node_name):
				failures.append("card '%s' targets weapon '%s', which is in no WEAPON_LIBRARY row"
						% [String(extra.get("id", "?")), node_name])
				continue
			if not properties[node_name].has(property):
				failures.append("card '%s': %s has no property '%s'"
						% [String(extra.get("id", "?")), node_name, property])
	for row: Dictionary in EvolutionCatalog.EVOLUTION_LIBRARY:
		var node_name := String(row.get("weapon_node", ""))
		for table_key: String in ["mults", "adds"]:
			for property: Variant in (row.get(table_key, {}) as Dictionary):
				rows += 1
				if not properties.has(node_name):
					failures.append("evolution '%s' targets weapon '%s', which is in no WEAPON_LIBRARY row"
							% [String(row.get("weapon_id", "?")), node_name])
					break
				if not properties[node_name].has(String(property)):
					failures.append("evolution '%s': %s has no property '%s' (%s)"
							% [String(row.get("weapon_id", "?")), node_name,
							String(property), table_key])
	_report("weapon_properties", rows, failures)


## Los nombres de propiedad que publica la escena de un arma. Se leen de la
## lista de propiedades de la instancia y no con get() != null: un miembro
## @onready es null antes de _ready y fallaría esa prueba aunque exista.
func _weapon_properties(scene_path: String) -> Dictionary[String, bool]:
	var names: Dictionary[String, bool] = {}
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return names
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return names
	var weapon := packed.instantiate()
	if weapon == null:
		return names
	for property: Dictionary in weapon.get_property_list():
		names[String(property.get("name", ""))] = true
	weapon.free()
	return names


## Las tres tablas chicas de ids que viven fuera de scripts/systems: se
## sortean igual y un id repetido hace el mismo daño.
func _check_vendor_lucky_roulette_ids() -> void:
	var failures: Array[String] = []
	var rows := 0
	var sources: Array[Array] = [
		["VENDOR_LIBRARY", Vendor.VENDOR_LIBRARY],
		["LUCKY_REWARDS", LuckyBlock.LUCKY_REWARDS],
		["OUTCOMES", RouletteShrine.OUTCOMES],
	]
	for entry: Array in sources:
		var library_name := String(entry[0])
		var library: Array[Dictionary] = entry[1]
		var seen: Dictionary[String, bool] = {}
		for row: Dictionary in library:
			rows += 1
			var id := String(row.get("id", ""))
			if id.is_empty():
				failures.append("%s has a row with no id" % library_name)
				continue
			if seen.has(id):
				failures.append("%s repeats id '%s'" % [library_name, id])
			seen[id] = true
	_report("vendor_lucky_roulette_ids", rows, failures)


## Cada tipo de marcador que puede llegar al mapa necesita una fila en la
## leyenda, así quien ve un punto puede saber qué es. Las excepciones son
## VARIANTES de un tipo que ya tiene fila (un cofre gratis es un cofre) y se
## nombran en MapDraw.LEGEND_VARIANTS, no aquí.
func _check_marker_labels() -> void:
	var failures: Array[String] = []
	var rows := 0
	var kinds: Dictionary[String, String] = {}
	for kind: StringName in MapDraw.MARKER_STYLES:
		kinds[String(kind)] = "MARKER_STYLES"
	for entry: Array in _assigned_marker_kinds():
		kinds[String(entry[0])] = String(entry[1])
	# El grupo, el jefe y la salida se dibujan siempre (always_visible) y no
	# son cosas que se buscan en una leyenda.
	var exempt: Dictionary[String, bool] = {"player": true, "boss": true, "exit": true}
	for kind: String in kinds:
		if exempt.has(kind):
			continue
		rows += 1
		if MapDraw.MARKER_LABELS.has(StringName(kind)):
			continue
		if MapDraw.LEGEND_VARIANTS.has(StringName(kind)):
			continue
		failures.append("marker kind '%s' (%s) has no MARKER_LABELS row and is not a LEGEND_VARIANT"
				% [kind, kinds[kind]])
	_report("marker_labels", rows, failures)


## Cada asignación `marker_kind = &"..."` del código y de las escenas, como
## [tipo, "archivo:línea"]. Se lee como texto porque los tipos se asignan en
## _init() o en .tscn que este lint nunca instancia.
func _assigned_marker_kinds() -> Array[Array]:
	var found: Array[Array] = []
	var pattern := RegEx.create_from_string('marker_kind\\s*=\\s*&"([a-z_]+)"')
	for path: String in _gd_files(MARKER_ROOTS) + _gd_files(MARKER_ROOTS, ".tscn"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var lines := file.get_as_text().split("\n")
		file.close()
		for i in lines.size():
			var hit := pattern.search(lines[i])
			if hit == null:
				continue
			found.append([hit.get_string(1), "%s:%d" % [path.get_file(), i + 1]])
	return found


## Cada id de catálogo con el formato de ID_PATTERN. Un id con espacios o
## mayúsculas termina dentro de llaves del guardado ("runs_as_Electro Gato") y
## de los contadores que nombran las misiones.
func _check_id_format() -> void:
	var failures: Array[String] = []
	var rows := 0
	var pattern := RegEx.create_from_string(ID_PATTERN)
	var sources: Array[Array] = _id_libraries()
	sources.append(["VENDOR_LIBRARY", Vendor.VENDOR_LIBRARY, "id"])
	sources.append(["LUCKY_REWARDS", LuckyBlock.LUCKY_REWARDS, "id"])
	sources.append(["OUTCOMES", RouletteShrine.OUTCOMES, "id"])
	for entry: Array in sources:
		var library_name := String(entry[0])
		var library: Array[Dictionary] = entry[1]
		var key := String(entry[2])
		for row: Dictionary in library:
			rows += 1
			var id := String(row.get(key, ""))
			if pattern.search(id) == null:
				failures.append("%s %s '%s' is not lowercase snake_case" % [library_name, key, id])
	_report("id_format", rows, failures)


## Cada misión cuyo `stat` lleva un id de otro catálogo después de un prefijo
## de SaveData. Si ese id no existe, el contador nunca sube y la misión queda
## imposible para siempre sin ningún error.
func _check_quest_stats() -> void:
	var failures: Array[String] = []
	var rows := 0
	var character_ids := _ids_of(CharacterCatalog.CHARACTER_LIBRARY)
	var map_ids := _ids_of(MapCatalog.MAP_LIBRARY)
	var weapon_ids := _ids_of(WeaponCatalog.WEAPON_LIBRARY)
	# prefijo -> [qué debe nombrar, ids válidos]
	var prefixes: Dictionary[String, Array] = {
		"runs_as_": ["a character id", character_ids],
		"wins_as_": ["a character id", character_ids],
		"runs_on_": ["a map id", map_ids],
		"victories_": ["a map id", map_ids],
		"slain_": ["a secret_boss_id in a scene", _secret_boss_ids()],
		"kills_": ["an enemy script name", _enemy_script_names()],
		"evo_": ["a weapon id", weapon_ids],
		"used_weapon_": ["a weapon id", weapon_ids],
	}
	for row: Dictionary in QuestCatalog.QUEST_LIBRARY:
		var stat := String(row.get("stat", ""))
		for prefix: String in prefixes:
			if not stat.begins_with(prefix):
				continue
			rows += 1
			var rule: Array = prefixes[prefix]
			var valid: Dictionary[String, bool] = rule[1]
			if not valid.has(stat.trim_prefix(prefix)):
				failures.append("quest '%s' stat '%s' does not name %s"
						% [String(row.get("id", "?")), stat, String(rule[0])])
			break
	_report("quest_stats", rows, failures)


## Números que un texto repite de su propia fila: la pasiva de cada
## personaje, la etiqueta de cada mascota y el texto de rango de cada
## reliquia. El texto se escribe a mano al lado del número que de verdad se
## aplica; si alguien cambia uno y no el otro, la carta miente.
func _check_text_numbers() -> void:
	var failures: Array[String] = []
	var rows := 0
	for row: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		rows += 1
		var text := String(row.get("passive_description", ""))
		var numbers := _numbers_in(text)
		if numbers.is_empty() or not is_equal_approx(numbers[0], float(row.get("passive_amount", 0.0))):
			failures.append("character '%s' passive_description '%s' does not start with passive_amount %s"
					% [String(row.get("id", "?")), text, str(row.get("passive_amount", 0.0))])
		var base := float(row.get("passive_base", 0.0))
		if base > 0.0 and not _has_number(numbers, base):
			failures.append("character '%s' passive_description '%s' does not show passive_base %s"
					% [String(row.get("id", "?")), text, str(base)])
	for row: Dictionary in PetCatalog.PET_LIBRARY:
		rows += 1
		var label := String(row.get("stat_label", ""))
		var numbers := _numbers_in(label)
		if numbers.is_empty() or not is_equal_approx(numbers[0], float(row.get("amount_per_level", 0.0))):
			failures.append("pet '%s' stat_label '%s' does not show amount_per_level %s"
					% [String(row.get("id", "?")), label, str(row.get("amount_per_level", 0.0))])
	for row: Dictionary in RelicCatalog.RELIC_LIBRARY:
		rows += 1
		var amount_text := String(row.get("amount_text", ""))
		var numbers := _numbers_in(amount_text)
		if numbers.is_empty() or not is_equal_approx(numbers[0], float(row.get("amount", 0.0))):
			failures.append("relic '%s' amount_text '%s' does not show amount %s"
					% [String(row.get("id", "?")), amount_text, str(row.get("amount", 0.0))])
	_report("text_numbers", rows, failures)


## Las filas que RowText arma: cada campo de text_values es un número de la
## fila ("amount" pide un primer efecto con amount), y la descripción tiene un
## %d por campo y ningún % suelto (el signo de porcentaje se escribe %%). Un
## campo que falta se dibuja como 0, y un % suelto hace fallar el formato: el
## jugador ve la plantilla cruda.
func _check_text_values() -> void:
	var failures: Array[String] = []
	var rows := 0
	var sources: Array[Array] = [
		["ITEM_LIBRARY", ItemCatalog.ITEM_LIBRARY],
		["POWERUP_LIBRARY", PowerUpCatalog.POWERUP_LIBRARY],
	]
	for entry: Array in sources:
		var library_name := String(entry[0])
		var library: Array[Dictionary] = entry[1]
		for row: Dictionary in library:
			rows += 1
			var owner_text := "%s/%s" % [library_name, String(row.get("id", "?"))]
			var names: Array = row.get("text_values", [])
			for field: Variant in names:
				if not _row_has_text_field(row, String(field)):
					failures.append("%s text_values names '%s', which is not a number field of the row"
							% [owner_text, String(field)])
			var bare := String(row.get("description", "")).replace("%%", "")
			var slots := bare.count("%d")
			if slots != names.size():
				failures.append("%s description has %d %%d but text_values lists %d fields"
						% [owner_text, slots, names.size()])
			# Solo las filas con text_values pasan por el formato; las demás
			# pueden llevar un % suelto.
			if not names.is_empty() and bare.count("%") != slots:
				failures.append("%s description has a lone %% (write %%%% for a percent sign)"
						% owner_text)
	_report("text_values", rows, failures)


## Si `field` es un número (int o float) que RowText.value_of() puede leer de
## la fila.
func _row_has_text_field(row: Dictionary, field: String) -> bool:
	var value: Variant = null
	if field == "amount":
		var effects: Array = row.get("effects", [])
		if effects.is_empty():
			return false
		value = (effects[0] as Dictionary).get("amount")
	else:
		value = row.get(field)
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## Cada `kind` de comportamiento en una sola fila de ITEM_LIBRARY:
## ItemCatalog.kind_row() lee los números de la PRIMERA fila del tipo, así que
## una segunda fila mostraría sus números en el texto y jugaría con los de la
## primera.
func _check_item_kinds_unique() -> void:
	var failures: Array[String] = []
	var rows := 0
	var seen: Dictionary[String, String] = {}
	for row: Dictionary in ItemCatalog.ITEM_LIBRARY:
		var kind := String(row.get("kind", ""))
		if kind.is_empty():
			continue
		rows += 1
		var item_id := String(row.get("id", "?"))
		if seen.has(kind):
			failures.append("kind '%s' is on both '%s' and '%s'" % [kind, seen[kind], item_id])
			continue
		seen[kind] = item_id
	_report("item_kinds_unique", rows, failures)


## Cada id de sonido escrito a mano: los `&"x"` de una llamada a Sfx
## (play, acquire_loop...) o a MetaScreen.payoff(), las constantes de sonido
## (un nombre con SOUND o SFX, como FANFARE_SFX), los defaults de los exports
## `*_sound` / `*_loop` y sus valores en las escenas. Un id que no está en
## Sfx.SOUND_LIBRARY no suena y solo deja una advertencia perdida en el log.
func _check_sfx_ids() -> void:
	var failures: Array[String] = []
	var rows := 0
	var known: Dictionary = SFX_SCRIPT.SOUND_LIBRARY
	var call_pattern := RegEx.create_from_string(SFX_CALL_PATTERN)
	var payoff_pattern := RegEx.create_from_string(SFX_PAYOFF_PATTERN)
	var const_pattern := RegEx.create_from_string(SFX_CONST_PATTERN)
	var export_pattern := RegEx.create_from_string(SFX_EXPORT_PATTERN)
	var scene_pattern := RegEx.create_from_string(SFX_SCENE_PATTERN)
	var literal_pattern := RegEx.create_from_string(STRING_NAME_PATTERN)
	var files := _gd_files(SFX_ROOTS)
	files.append_array(_gd_files(SFX_ROOTS, ".tscn"))
	for path: String in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			var ids: Array[String] = []
			for args_pattern: RegEx in [call_pattern, payoff_pattern]:
				for call_match: RegExMatch in args_pattern.search_all(line):
					for literal: RegExMatch in literal_pattern.search_all(call_match.get_string(1)):
						ids.append(literal.get_string(1))
			for pattern: RegEx in [export_pattern, scene_pattern, const_pattern]:
				var value_match := pattern.search(line)
				if value_match != null:
					ids.append(value_match.get_string(1))
			for id: String in ids:
				rows += 1
				if not known.has(StringName(id)):
					failures.append("%s:%d sound id '%s' is not in Sfx.SOUND_LIBRARY"
							% [path, i + 1, id])
	_report("sfx_ids", rows, failures)


## Conjunto de los valores de `field` en `rows`.
func _ids_of(rows: Array[Dictionary], field: String = "id") -> Dictionary[String, bool]:
	var ids: Dictionary[String, bool] = {}
	for row: Dictionary in rows:
		ids[String(row.get(field, ""))] = true
	return ids


## Cada `secret_boss_id = "..."` guardado en una escena, leído como texto
## porque los jefes secretos solo se instancian en plena incursión.
func _secret_boss_ids() -> Dictionary[String, bool]:
	var ids: Dictionary[String, bool] = {}
	var pattern := RegEx.create_from_string('(?m)^secret_boss_id = "([^"]+)"')
	for path: String in _gd_files(SCENE_ROOTS, ".tscn"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		for found: RegExMatch in pattern.search_all(file.get_as_text()):
			ids[found.get_string(1)] = true
		file.close()
	return ids


## Nombre de archivo (sin .gd) de cada script de enemigo.
func _enemy_script_names() -> Dictionary[String, bool]:
	var names: Dictionary[String, bool] = {}
	for path: String in _gd_files(ENEMY_SCRIPT_ROOTS):
		names[path.get_file().get_basename()] = true
	return names


## Los números de un texto, en orden ("+0.8% de daño" -> [0.8]).
func _numbers_in(text: String) -> Array[float]:
	var numbers: Array[float] = []
	var pattern := RegEx.create_from_string("[0-9]+(?:\\.[0-9]+)?")
	for found: RegExMatch in pattern.search_all(text):
		numbers.append(found.get_string().to_float())
	return numbers


func _has_number(numbers: Array[float], value: float) -> bool:
	for number: float in numbers:
		if is_equal_approx(number, value):
			return true
	return false


## Cada archivo con extensión `extension` bajo las carpetas dadas,
## recursivamente.
func _gd_files(roots: Array[String], extension: String = ".gd") -> Array[String]:
	var found: Array[String] = []
	var pending := roots.duplicate()
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(extension):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found
