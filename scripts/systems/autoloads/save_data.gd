extends Node
## Autoload "SaveData": el libro de progreso entre incursiones (saldo de
## esquirlas, personajes desbloqueados y comprados, contadores de misiones de
## toda la vida, misiones completadas y reclamadas, rangos de reliquias y
## ajustes), guardado como JSON en user://save.json.
##
## Escrituras: fold_run_results() al terminar cada incursión (RunManager), más
## las compras y los reclamos de misiones. Durante una incursión los sistemas
## suman con bump() / raise_to(), que caen en un BÚFER DE INCURSIÓN
## (_run_counters/_run_highs); solo el FINAL de la incursión lo mezcla con el
## libro. Así una incursión abandonada no guarda nada, aunque una compra, un
## reclamo o el desbloqueo de un jefe secreto escriban el archivo mientras
## sigue en curso. RunState.reset() descarta lo pendiente (el inicio de una
## incursión y el abandono pasan por ahí). Las lecturas de progreso usan
## stat() (libro + búfer); completar misiones lee SOLO el libro, para que una
## misión nunca quede completa por contadores que un abandono deshace.
##
## Ids de contadores (las filas de QuestCatalog los nombran en `stat`):
##   total_kills, bosses_killed, runs_finished, victories, shrines_used,
##   chests_opened, portals_used, roulette_spins, stages_cleared,
##   evolutions_total, relics_bought, daily_runs, any_t2_win / any_t3_win
##   (misiones de vuelta), y los máximos de una incursión: max_level,
##   best_run_minutes, laps_completed y best_endless_minutes (minutos en modo
##   pseudo-infinito después de superar una etapa).
## Con prefijo, donde el resto del nombre es un id de otro catálogo
## (renombrar ese id deja el contador huérfano):
##   runs_as_<character_id>, wins_as_<character_id>: CharacterCatalog (los
##   ids renombrados se traducen al cargar, ver ID_ALIASES).
##   runs_on_<map_id> (cada mapa visitado), victories_<map_id> (cada mapa
##   superado): MapCatalog.
##   slain_<secret_boss_id>: jefes ocultos (SecretBossBase).
##   used_weapon_<weapon_id>: Colección, arma llevada alguna vez (Player y
##   UpgradePool); el id es de WeaponCatalog. evo_<weapon_id>: evoluciones
##   (EvolutionCatalog).
##   kills_<script_del_enemigo>: bestiario (EnemyBase al morir).
##   item_<item_id>: objetos tomados (ItemBag).
##   daily_best_<fecha>: mejor puntaje de la Cacería diaria de ese día.

signal shards_changed(balance: int)

const DEFAULT_SAVE_PATH := "user://save.json"
## Variable de entorno solo para pruebas: BONK_SAVE_PATH apunta el libro a
## otro archivo antes de la primera lectura, así cualquier arranque headless
## corre sin tocar el guardado real del jugador. El harness de soak además
## redirige por su cuenta, antes, porque arranca la incursión él mismo.
const SAVE_PATH_ENV: String = "BONK_SAVE_PATH"
const SAVE_VERSION := 1
## save() escribe primero aquí y solo renombra si salió bien, así una
## escritura interrumpida nunca trunca el archivo real...
const TEMP_SUFFIX := ".tmp"
## ...y la copia que reemplaza queda como último archivo bueno conocido.
const BACKUP_SUFFIX := ".bak"

## Valores por defecto de los ajustes (el diccionario "settings" del JSON).
## Los volúmenes son valores de slider 0..100 (100 = la mezcla original, ver
## Settings.volume_to_db); la sensibilidad multiplica la base exportada del
## jugador.
const DEFAULT_SFX_VOLUME := 100.0
const DEFAULT_AMBIENT_VOLUME := 100.0
const DEFAULT_MOUSE_SENSITIVITY := 1.0
const MIN_MOUSE_SENSITIVITY := 0.3
const MAX_MOUSE_SENSITIVITY := 2.0
## Preset gráfico: 0 Alta, 1 Media, 2 Baja. Lo que hace cada uno vive en
## Settings (settings_apply.gd), el único que lo aplica; el guardado solo
## guarda el índice. Un guardado sin la llave juega en Alta.
const DEFAULT_GRAPHICS_QUALITY := 0
const MAX_GRAPHICS_QUALITY := 2

## Ids viejos de personaje -> id actual. load_from_disk traduce con esta tabla
## los personajes desbloqueados y comprados y los contadores runs_as_/wins_as_
## de un guardado viejo. Si renombras un id en CharacterCatalog, agrega aquí
## la fila viejo -> nuevo. Una llave de esta tabla no puede volver a ser id de
## un personaje, y se traduce un solo salto: si renombras un id que ya es
## destino de otras filas, cambia también esas filas.
const ID_ALIASES: Dictionary[String, String] = {
	"juno": "yandere_chan",
	"Yandere-chan": "yandere_chan",
	"torren": "electro_gato",
	"Electro Gato": "electro_gato",
	"miro": "moka",
	"Moka": "moka",
	"kael": "goku",
	"Goku": "goku",
}
## Prefijos de contador seguidos de un id de personaje.
const CHARACTER_COUNTER_PREFIXES: Array[String] = ["runs_as_", "wins_as_"]

## Los harness de prueba lo apuntan a un archivo descartable antes de
## load_from_disk().
var save_path: String = DEFAULT_SAVE_PATH

var shards: int = 0
## Ids de personajes jugables ahora (los gratis más los comprados).
var unlocked_character_ids: Array[String] = []
## Los ids desbloqueados que se compraron con esquirlas (historial de compras).
var purchased_character_ids: Array[String] = []
## Contadores de toda la vida por id de stat (ver la cabecera). Solo viven
## aquí los créditos que sobrevivieron al final de una incursión (o que
## ocurrieron fuera de una); es el diccionario que save() escribe.
var counters: Dictionary[String, int] = {}
## Misiones que llegaron a su meta; se pueden reclamar hasta pasar a claimed.
var completed_quest_ids: Array[String] = []
var claimed_quest_ids: Array[String] = []

## Resultado del último fold_run_results(); lo lee la pantalla de fin de
## incursión.
var last_new_quest_ids: Array[String] = []
var last_reward_shards: int = 0
## Rangos de la Armería comprados por id de reliquia (ver RelicCatalog).
var relic_ranks: Dictionary[String, int] = {}

# --- Ajustes (valores guardados; el autoload Settings los aplica a los buses
# y a la ventana y es el único que los escribe, ver settings_apply.gd) ------
var sfx_volume: float = DEFAULT_SFX_VOLUME
var ambient_volume: float = DEFAULT_AMBIENT_VOLUME
## Multiplicador de la velocidad de mirada sobre la base exportada del jugador.
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var fullscreen: bool = false
## Contador de FPS del HUD para el jugador. Es independiente de la sonda de
## rendimiento de depuración, que tiene su propio interruptor.
var show_fps: bool = false
## Índice del preset gráfico, 0..MAX_GRAPHICS_QUALITY (ver la const de arriba).
var graphics_quality: int = DEFAULT_GRAPHICS_QUALITY

## Búfer de la incursión: bump() suma aquí (como delta) y raise_to() en
## _run_highs (como máximo absoluto); los dos llegan a `counters` solo cuando
## fold_run_results los mezcla. Abandonar los descarta.
var _run_counters: Dictionary[String, int] = {}
var _run_highs: Dictionary[String, int] = {}

## True cuando el archivo en disco lo escribió una versión MÁS NUEVA: su
## esquema es desconocido aquí, así que esta versión juega con lo que pudo
## leer y nunca escribe, para no degradar progreso real en silencio.
var _read_only: bool = false


func _ready() -> void:
	var override_path := OS.get_environment(SAVE_PATH_ENV)
	if not override_path.is_empty():
		save_path = override_path
		print("Save path overridden: %s" % save_path)
	load_from_disk()


# --- Contadores -------------------------------------------------------

## Valor de toda la vida INCLUYENDO lo que la incursión actual ya sumó: el
## número que se le muestra al jugador (barras del registro de misiones).
func stat(stat_id: String) -> int:
	return maxi(_persisted_stat(stat_id) + int(_run_counters.get(stat_id, 0)),
			int(_run_highs.get(stat_id, 0)))


## Valor ya guardado, sin lo pendiente de la incursión actual. Las misiones
## se evalúan contra ESTE valor, para que una incursión abandonada nunca deje
## una misión completa por contadores que se deshicieron.
func _persisted_stat(stat_id: String) -> int:
	return int(counters.get(stat_id, 0))


## Suma durante la incursión para los contadores acumulativos. Altares,
## cofres y muertes de jefes la llaman al resolverse; se vuelve permanente
## solo cuando la incursión se cierra (ver la cabecera).
func bump(stat_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_run_counters[stat_id] = int(_run_counters.get(stat_id, 0)) + amount


## Contadores de máximo (mejor nivel / más minutos en una incursión).
func raise_to(stat_id: String, value: int) -> void:
	if value > stat(stat_id):
		_run_highs[stat_id] = value


## Crédito que debe guardarse al instante porque ocurre FUERA de una
## incursión (compras en la Armería): va directo al libro, sin pasar por el
## búfer de la incursión.
func _credit_now(stat_id: String, amount: int = 1) -> void:
	counters[stat_id] = _persisted_stat(stat_id) + amount


## Mezcla el búfer de la incursión con el libro. SOLO fold_run_results la
## llama: es el único punto donde los créditos de una incursión se vuelven
## reales.
func _merge_run_counters() -> void:
	for stat_id: String in _run_counters:
		counters[stat_id] = _persisted_stat(stat_id) + _run_counters[stat_id]
	for stat_id: String in _run_highs:
		counters[stat_id] = maxi(_persisted_stat(stat_id), _run_highs[stat_id])
	_run_counters.clear()
	_run_highs.clear()


## Descarta todo lo que la incursión actual sumó sin cerrarla. La llama
## RunState.reset(), por donde pasan el inicio de cada incursión Y el
## abandono con «Salir al menú».
func discard_run_counters() -> void:
	_run_counters.clear()
	_run_highs.clear()


# --- Cierre de la incursión (RunManager) -------------------------------

## Cierra una incursión terminada: la suma a los contadores de toda la vida,
## marca las misiones que acaban de llegar a su meta (reclamarlas sigue siendo
## manual, en el registro) y guarda. El resultado queda en last_new_quest_ids
## y last_reward_shards, que leen RunManager y la pantalla final.
## `character_ids` es el grupo ENTERO (una entrada por espacio co-op; en solo,
## un id): cada raider distinto suma su runs_as_/wins_as_. Una incursión
## recorre VARIOS mapas, así que runs_on_<mapa> se suma por cada mapa visitado
## y victories_<mapa> por cada mapa superado. `victory` significa «superó al
## menos una etapa».
func fold_run_results(victory: bool, character_ids: Array[String],
		visited_map_ids: Array[String], cleared_map_ids: Array[String],
		stages_cleared: int, laps: int,
		level: int, kills: int, run_seconds: float) -> void:
	var party := _distinct(character_ids)
	bump("total_kills", kills)
	bump("runs_finished")
	for map_id: String in _distinct(visited_map_ids):
		bump("runs_on_" + map_id)
	for character_id: String in party:
		bump("runs_as_" + character_id)
	if victory:
		bump("victories")
		for map_id: String in _distinct(cleared_map_ids):
			bump("victories_" + map_id)
		for character_id: String in party:
			bump("wins_as_" + character_id)
	bump("stages_cleared", stages_cleared)
	# Las misiones de vuelta leen any_t2_win / any_t3_win: esos nombres se
	# mantienen para que los guardados que ya las completaron las conserven.
	raise_to("laps_completed", laps)
	if laps >= 1:
		bump("any_t2_win")
	if laps >= 2:
		bump("any_t3_win")
	raise_to("max_level", level)
	raise_to("best_run_minutes", int(run_seconds / 60.0))
	# Minutos que esta incursión pasó en modo pseudo-infinito tras superar
	# una etapa.
	raise_to("best_endless_minutes", int(RunState.endless_seconds_total / 60.0))
	# La incursión llegó al final: lo que sumó se vuelve permanente ANTES de
	# evaluar las misiones (único punto de mezcla).
	_merge_run_counters()
	last_new_quest_ids = _commit()
	last_reward_shards = 0
	for quest_id: String in last_new_quest_ids:
		last_reward_shards += int(QuestCatalog.by_id(quest_id).reward)


## Ids sin repetir, en el mismo orden (un grupo co-op puede llevar dos veces
## al mismo raider; el crédito es por raider, no por espacio).
static func _distinct(ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


## Único punto de confirmación: evalúa las misiones contra lo que hay en el
## libro, guarda y, si se pide, anuncia el saldo nuevo. Toda escritura pasa
## por aquí, así un contador sumado FUERA de una incursión (una compra en la
## Armería) completa su misión al momento, sin esperar otra incursión.
func _commit(emit_shards: bool = false) -> Array[String]:
	var newly := _evaluate_quests()
	save()
	if emit_shards:
		shards_changed.emit(shards)
	return newly


## Marca cada misión aún no completada cuyo contador GUARDADO llegó a la
## meta; devuelve los ids recién completados. completed_quest_ids se guarda,
## así una misión nunca se completa (ni paga) dos veces.
func _evaluate_quests() -> Array[String]:
	var newly: Array[String] = []
	for quest: Dictionary in QuestCatalog.QUEST_LIBRARY:
		var quest_id := String(quest.id)
		if completed_quest_ids.has(quest_id):
			continue
		if _persisted_stat(String(quest.stat)) >= int(quest.target):
			completed_quest_ids.append(quest_id)
			newly.append(quest_id)
	return newly


# --- Reclamos de misiones ----------------------------------------------

func is_quest_completed(quest_id: String) -> bool:
	return completed_quest_ids.has(quest_id)


func is_quest_claimed(quest_id: String) -> bool:
	return claimed_quest_ids.has(quest_id)


## Paga una sola vez las esquirlas de una misión completada y no reclamada,
## y guarda. Devuelve las esquirlas dadas (0 si no se puede reclamar).
func claim_quest(quest_id: String) -> int:
	if not is_quest_completed(quest_id) or is_quest_claimed(quest_id):
		return 0
	var quest := QuestCatalog.by_id(quest_id)
	if quest.is_empty():
		return 0
	var reward := int(quest.reward)
	claimed_quest_ids.append(quest_id)
	shards += reward
	_commit(true)
	return reward


# --- Reliquias (Armería) -----------------------------------------------

func relic_rank(relic_id: String) -> int:
	return int(relic_ranks.get(relic_id, 0))


## Compra el siguiente rango de una reliquia según la escalera de precios de
## RelicCatalog. Descuenta, registra, guarda y devuelve true; false (sin
## descontar) si el id no existe, está en el tope o no alcanza el saldo. La
## compra ocurre fuera de una incursión, así que su contador va directo al
## libro y la misión «Primera reliquia» se puede reclamar al instante.
func purchase_relic(relic_id: String) -> bool:
	var cost := RelicCatalog.next_rank_cost(relic_id, relic_rank(relic_id))
	if cost < 0 or not can_afford(cost):
		return false
	shards -= cost
	relic_ranks[relic_id] = relic_rank(relic_id) + 1
	_credit_now("relics_bought")
	_commit(true)
	return true


# --- Desbloqueo de personajes -----------------------------------------

func is_unlocked(character_id: String) -> bool:
	return unlocked_character_ids.has(character_id)


func can_afford(cost: int) -> bool:
	return shards >= cost


## Da un personaje sin más: la única escritura de desbloqueo que comparten
## los dos caminos. La muerte de un jefe la llama con source "boss" (sin
## costo); purchase_character pasa por aquí con source "purchase", la única
## etiqueta que además registra la compra. Idempotente: un id desconocido o
## ya desbloqueado no hace nada y devuelve false; un desbloqueo nuevo se
## guarda al instante y devuelve true.
func unlock_character(character_id: String, source: String) -> bool:
	if CharacterCatalog.by_id(character_id).is_empty() or is_unlocked(character_id):
		return false
	unlocked_character_ids.append(character_id)
	if source == "purchase":
		purchased_character_ids.append(character_id)
	_commit()
	return true


## Compra un personaje bloqueado al unlock_cost de su fila. Descuenta,
## desbloquea, registra la compra y guarda. False (sin descontar) si el id no
## existe, ya está desbloqueado o no alcanza el saldo.
func purchase_character(character_id: String) -> bool:
	var row := CharacterCatalog.by_id(character_id)
	if row.is_empty() or is_unlocked(character_id):
		return false
	var cost := int(row.get("unlock_cost", 0))
	if not can_afford(cost):
		return false
	shards -= cost
	unlock_character(character_id, "purchase")
	shards_changed.emit(shards)
	return true


# --- Disco -------------------------------------------------------------

## Carga save_path; si falta, está corrupto o tiene tipos equivocados, usa la
## copia .bak y después los valores por defecto (nunca se cae: un archivo
## malo empieza de cero). Un archivo de una versión más nueva se lee hasta
## donde este esquema permite y queda bloqueado (ver _read_only) en vez de
## sobrescribirse. Los ids viejos de personaje se traducen (ID_ALIASES) y, si
## hubo alguno, el guardado se reescribe una vez con los ids actuales.
func load_from_disk() -> void:
	_apply_defaults()
	_read_only = false
	discard_run_counters()
	var data := _read_save_dict(save_path)
	if data.is_empty():
		# save() solo pone en su lugar un archivo completo y conserva el que
		# reemplaza, así un archivo principal truncado tiene un antecesor bueno.
		data = _read_save_dict(save_path + BACKUP_SUFFIX)
		if not data.is_empty():
			print("Save recovered from backup: %s" % save_path)
	if data.is_empty():
		return
	# Un guardado sin versión se lee como 0. Los cambios de esquema son
	# aditivos: una llave que falta toma su valor por defecto.
	var version := _as_int(data.get("version"), 0)
	if version > SAVE_VERSION:
		push_warning("SaveData: %s comes from a newer build (v%d); read-only."
				% [save_path, version])
		_read_only = true
	shards = maxi(_as_int(data.get("shards"), 0), 0)
	unlocked_character_ids = _as_string_array(data.get("unlocked_characters"))
	purchased_character_ids = _as_string_array(data.get("purchased_characters"))
	counters = _as_int_dict(data.get("counters"))
	completed_quest_ids = _as_string_array(data.get("completed_quests"))
	claimed_quest_ids = _as_string_array(data.get("claimed_quests"))
	# Sin la llave "relics" no hay reliquias. Las llaves que esta versión ya
	# no conoce simplemente no se leen.
	relic_ranks = _as_int_dict(data.get("relics"))
	_load_settings(data.get("settings"))
	var migrated := _migrate_character_ids()
	# Los personajes gratis siempre son jugables, aunque un archivo editado
	# los haya quitado.
	for starter_id: String in CharacterCatalog.starter_ids():
		if not unlocked_character_ids.has(starter_id):
			unlocked_character_ids.append(starter_id)
	if migrated > 0:
		print("Save migrated: %d character id(s)" % migrated)
		save()


## Traduce los ids viejos de personaje (ID_ALIASES) en los desbloqueos, las
## compras y los contadores runs_as_/wins_as_; si el contador viejo y el
## nuevo existen a la vez, suma los dos. Devuelve cuántos ids viejos distintos
## encontró: con 0 nada cambió.
func _migrate_character_ids() -> int:
	var found: Dictionary[String, bool] = {}
	unlocked_character_ids = _renamed_ids(unlocked_character_ids, found)
	purchased_character_ids = _renamed_ids(purchased_character_ids, found)
	counters = _renamed_counters(counters, found)
	return found.size()


## `ids` con cada id viejo cambiado por el actual y sin repetidos. Sin ids
## viejos devuelve la misma lista intacta. Anota en `found` los ids viejos.
static func _renamed_ids(ids: Array[String], found: Dictionary[String, bool]) -> Array[String]:
	var has_old := false
	for id: String in ids:
		if ID_ALIASES.has(id):
			has_old = true
			found[id] = true
	if not has_old:
		return ids
	var out: Array[String] = []
	for id: String in ids:
		var current: String = ID_ALIASES.get(id, id)
		if not out.has(current):
			out.append(current)
	return out


## `source` con los contadores runs_as_/wins_as_ de ids viejos renombrados al
## id actual, sumando cuando las dos llaves existen. Sin ids viejos devuelve
## el mismo diccionario intacto. Anota en `found` los ids viejos.
static func _renamed_counters(source: Dictionary[String, int],
		found: Dictionary[String, bool]) -> Dictionary[String, int]:
	var renames: Dictionary[String, String] = {}
	for key: String in source:
		for prefix: String in CHARACTER_COUNTER_PREFIXES:
			var old_id := key.trim_prefix(prefix)
			if key.begins_with(prefix) and ID_ALIASES.has(old_id):
				renames[key] = prefix + ID_ALIASES[old_id]
				found[old_id] = true
	if renames.is_empty():
		return source
	var out: Dictionary[String, int] = {}
	for key: String in source:
		var target: String = renames.get(key, key)
		out[target] = int(out.get(target, 0)) + source[key]
	return out


## Contenido de un archivo de guardado, o {} si falta, no se puede leer o no
## es un objeto JSON.
func _read_save_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveData: cannot read %s." % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_warning("SaveData: %s is not valid JSON." % path)
		return {}
	return parsed as Dictionary


## Escritura atómica: el JSON va a un archivo temporal que se renombra sobre
## save_path solo cuando está completo, y el archivo que reemplaza queda como
## .bak. Un cierre a mitad de escritura nunca deja un save.json a medias.
func save() -> void:
	if _read_only:
		return
	var temp_path := save_path + TEMP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveData: cannot write %s." % temp_path)
		return
	file.store_string(JSON.stringify(_to_save_dict(), "\t"))
	var write_status := file.get_error()
	file.close()
	if write_status != OK:
		push_warning("SaveData: incomplete write to %s (code %d)." % [temp_path, write_status])
		DirAccess.remove_absolute(temp_path)
		return
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(save_path, save_path + BACKUP_SUFFIX)
	var rename_status := DirAccess.rename_absolute(temp_path, save_path)
	if rename_status != OK:
		push_warning("SaveData: cannot commit %s (code %d)." % [save_path, rename_status])


func _apply_defaults() -> void:
	shards = 0
	unlocked_character_ids = CharacterCatalog.starter_ids()
	purchased_character_ids = []
	counters = {}
	completed_quest_ids = []
	claimed_quest_ids = []
	relic_ranks = {}
	sfx_volume = DEFAULT_SFX_VOLUME
	ambient_volume = DEFAULT_AMBIENT_VOLUME
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	fullscreen = false
	show_fps = false
	graphics_quality = DEFAULT_GRAPHICS_QUALITY


## Si "settings" falta o viene mal formado se quedan los valores que
## _apply_defaults acaba de poner; los valores se limitan a su rango legal.
func _load_settings(value: Variant) -> void:
	if value is not Dictionary:
		return
	var settings := value as Dictionary
	sfx_volume = clampf(_as_float(settings.get("sfx_volume"), DEFAULT_SFX_VOLUME), 0.0, 100.0)
	ambient_volume = clampf(
			_as_float(settings.get("ambient_volume"), DEFAULT_AMBIENT_VOLUME), 0.0, 100.0)
	mouse_sensitivity = clampf(
			_as_float(settings.get("mouse_sensitivity"), DEFAULT_MOUSE_SENSITIVITY),
			MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	fullscreen = _as_bool(settings.get("fullscreen"), false)
	show_fps = _as_bool(settings.get("show_fps"), false)
	graphics_quality = clampi(
			_as_int(settings.get("graphics_quality"), DEFAULT_GRAPHICS_QUALITY),
			0, MAX_GRAPHICS_QUALITY)


## El libro que se guarda. Solo escribe `counters`: lo pendiente en el búfer
## de la incursión actual queda fuera del archivo a propósito.
func _to_save_dict() -> Dictionary[String, Variant]:
	return {
		"version": SAVE_VERSION,
		"shards": shards,
		"unlocked_characters": unlocked_character_ids,
		"purchased_characters": purchased_character_ids,
		"counters": counters,
		"completed_quests": completed_quest_ids,
		"claimed_quests": claimed_quest_ids,
		"relics": relic_ranks,
		"settings": {
			"sfx_volume": sfx_volume,
			"ambient_volume": ambient_volume,
			"mouse_sensitivity": mouse_sensitivity,
			"fullscreen": fullscreen,
			"show_fps": show_fps,
			"graphics_quality": graphics_quality,
		},
	}


# --- Ayudas de lectura del JSON (los valores llegan sin tipo y los números
# como float). Todo lo mal formado cae al valor vacío o cero. -------------

static func _as_int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


static func _as_float(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value)
	return fallback


static func _as_bool(value: Variant, fallback: bool) -> bool:
	if value is bool:
		return value
	return fallback


static func _as_string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry: Variant in value as Array:
			if entry is String:
				out.append(entry)
	return out


static func _as_int_dict(value: Variant) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	if value is Dictionary:
		var source := value as Dictionary
		for key: Variant in source:
			if key is String and (source[key] is int or source[key] is float):
				out[String(key)] = int(source[key])
	return out
