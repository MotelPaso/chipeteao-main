extends Node
## Headless catalog lint (iteration 57): the cross-references a soak can
## never check, because a broken one does not crash — it silently does
## nothing. A misspelled `passive_stat` costs its raider its whole
## passive and prints one warning buried in a 20 000-line log; a `scene`
## path with a typo only fails the day somebody rolls that row; a glyph
## reused between two catalogs shows the wrong sigil on a HUD slot.
##
## Run it alone with:
##   godot --headless --fixed-fps 60 --quit-after 600 \
##     res://scenes/tests/CatalogLint.tscn
##
## Output contract (tools/verificar.sh greps every name from its own
## fixed list, so a check that stops running is a failure, not a silence):
##   Catalog lint: check <name> ok rows=%d   ... one per PASSING check
##   Catalog lint: ok checks=%d              ... only when all of them pass
## Every failure is a push_error, which PATRON_ERROR catches on its own.
##
## `rows` is the number of entries the check actually INSPECTED. Zero rows
## is a failure: a check that walks an empty list passes for the wrong
## reason, and that is exactly how a renamed constant would go unnoticed.

## The director declares no class_name; its EVENT_LIBRARY and
## WEATHER_CATALOG are only reachable through the script resource.
const WORLD_DIRECTOR := preload("res://scripts/world/world_director.gd")
## Scanned as TEXT for the `match stat:` arms of _apply_effect. There is no
## reflection for a match block, and hard-coding the list here would mean
## two copies of the same truth drifting apart on the next stat.
const PLAYER_STATS_PATH := "res://scripts/systems/player_stats.gd"
## Directories scanned for `marker_kind = &"..."` assignments.
const SCRIPT_ROOTS: Array[String] = ["res://scripts"]

## Marker kinds the map legend deliberately has no row for (MapDraw
## documents this; the lint reads the same constant so the exemption
## cannot drift).
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
	if _checks_failed == 0:
		print("Catalog lint: ok checks=%d" % _checks_run)
	else:
		print("Catalog lint: FAILED checks=%d failures=%d" % [_checks_run, _checks_failed])
	_quit.call_deferred()


func _quit() -> void:
	get_tree().quit(0 if _checks_failed == 0 else 1)


## One check's verdict. `rows` is what was inspected; `failures` is one
## human sentence per problem. A passing check prints its line, a failing
## one prints none (so the grep in verificar.sh misses it) and pushes one
## error per failure.
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


## Every id-keyed library, one at a time: a duplicate id makes by_id()
## return the first row forever and the second one dead content.
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


## name, library, id key.
func _id_libraries() -> Array[Array]:
	return [
		["WEAPON_LIBRARY", UpgradePool.WEAPON_LIBRARY, "id"],
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
		["WEATHER_CATALOG", WORLD_DIRECTOR.WEATHER_CATALOG, "id"],
		["PACT_LIBRARY", CurseShrine.PACT_LIBRARY, "id"],
	]


## Glyphs are the two-letter sigil a HUD slot paints when no icon PNG
## exists. They are keyed by CONTENT, not by library: the same "PA" on a
## weapon slot and an item slot reads as the same thing to a player.
func _check_glyphs_unique() -> void:
	var failures: Array[String] = []
	var rows := 0
	var seen: Dictionary[String, String] = {}
	var sources: Array[Array] = [
		["WEAPON_LIBRARY", UpgradePool.WEAPON_LIBRARY, "id"],
		["EVOLUTION_LIBRARY", EvolutionCatalog.EVOLUTION_LIBRARY, "weapon_id"],
		["TOME_LIBRARY", Tome.TOME_LIBRARY, "id"],
		["ITEM_LIBRARY", ItemCatalog.ITEM_LIBRARY, "id"],
		["POWERUP_LIBRARY", PowerUpCatalog.POWERUP_LIBRARY, "id"],
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


## Every res:// path a catalog row names. ResourceLoader.exists() and not
## FileAccess: an .tscn whose .import is missing loads as nothing.
func _check_paths_exist() -> void:
	var failures: Array[String] = []
	var rows := 0
	var sources: Array[Array] = [
		["WEAPON_LIBRARY", UpgradePool.WEAPON_LIBRARY, "id"],
		["PET_LIBRARY", PetCatalog.PET_LIBRARY, "id"],
		["CHARACTER_LIBRARY", CharacterCatalog.CHARACTER_LIBRARY, "id"],
		["MAP_LIBRARY", MapCatalog.MAP_LIBRARY, "id"],
		["ITEM_LIBRARY", ItemCatalog.ITEM_LIBRARY, "id"],
		["POWERUP_LIBRARY", PowerUpCatalog.POWERUP_LIBRARY, "id"],
		["TOME_LIBRARY", Tome.TOME_LIBRARY, "id"],
	]
	var path_keys: Array[String] = ["scene", "weapon_scene", "scene_path", "icon"]
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


## Every stat id any content row hands to PlayerStats._apply_effect. An id
## that is not one of its match arms falls through to the `_` arm, which
## warns once and applies NOTHING: the raider keeps the passive on its
## card and never gets it.
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


## The `match stat:` arms of PlayerStats._apply_effect, read off the
## source. There is no reflection for a match block and a hard-coded copy
## here would be a second truth to keep in sync.
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
	# The arms end at the catch-all; everything after it belongs to the
	# next function.
	var end := body.find("\n\t\t_:")
	if end >= 0:
		body = body.substr(0, end)
	var arm := RegEx.create_from_string("(?m)^\\t\\t\"([a-z_]+)\":")
	for found: RegExMatch in arm.search_all(body):
		accepted[found.get_string(1)] = true
	return accepted


## Every raider's weapon_node_name must be a node_name a WEAPON_LIBRARY
## row publishes: it is how the level-up pool finds the weapon the raider
## is already carrying, and a mismatch offers the starting weapon again as
## a "new" card.
func _check_character_weapons() -> void:
	var failures: Array[String] = []
	var rows := 0
	var node_names: Dictionary[String, bool] = {}
	for row: Dictionary in UpgradePool.WEAPON_LIBRARY:
		node_names[String(row.get("node_name", ""))] = true
	for row: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		rows += 1
		var node_name := String(row.get("weapon_node_name", ""))
		if not node_names.has(node_name):
			failures.append("character '%s' weapon_node_name '%s' is in no WEAPON_LIBRARY row"
					% [String(row.get("id", "?")), node_name])
	_report("character_weapons", rows, failures)


## Every method name EVENT_LIBRARY and WEATHER_CATALOG hand to call().
## They are called through call(), so a renamed method is a silent no-op
## with one error per roll, minutes into a run.
func _check_director_methods() -> void:
	var failures: Array[String] = []
	var rows := 0
	var declared: Dictionary[String, bool] = {}
	# Through a Script-typed local: `WORLD_DIRECTOR.get_script_method_list()`
	# reads as "call a static method declared in that script" and does not
	# parse. The resource's own method list is what we want.
	var director_script: Script = WORLD_DIRECTOR
	for method: Dictionary in director_script.get_script_method_list():
		declared[String(method.get("name", ""))] = true
	for row: Dictionary in WORLD_DIRECTOR.EVENT_LIBRARY:
		rows += 1
		var method := String(row.get("method", ""))
		if not declared.has(method):
			failures.append("event '%s' method '%s' is not declared on WorldDirector"
					% [String(row.get("id", "?")), method])
	for row: Dictionary in WORLD_DIRECTOR.WEATHER_CATALOG:
		for key: String in ["start", "tick", "stop"]:
			var method := String(row.get(key, ""))
			if method.is_empty():
				continue  # tick and stop are optional, and empty means none
			rows += 1
			if not declared.has(method):
				failures.append("weather '%s' %s '%s' is not declared on WorldDirector"
						% [String(row.get("id", "?")), key, method])
	_report("director_methods", rows, failures)


## Every property a card or an evolution writes on a weapon. Both go
## through set()/get() by name, so a renamed export turns the card into a
## no-op that still costs the player their level-up.
func _check_weapon_properties() -> void:
	var failures: Array[String] = []
	var rows := 0
	var by_node: Dictionary[String, Dictionary] = {}
	for row: Dictionary in UpgradePool.WEAPON_LIBRARY:
		by_node[String(row.get("node_name", ""))] = row
	var properties: Dictionary[String, Dictionary] = {}
	for node_name: String in by_node:
		properties[node_name] = _weapon_properties(String(by_node[node_name].get("scene", "")))
	for row: Dictionary in UpgradePool.WEAPON_LIBRARY:
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


## The property names one weapon scene publishes. Read off the instance's
## property list rather than with get() != null: an @onready node member
## is legitimately null before _ready and would fail a null test while
## existing perfectly well.
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


## The three small id tables that live outside scripts/systems: they are
## rolled the same way and a duplicate does the same damage.
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


## Every marker kind that can reach the map needs a legend row, so a
## player who sees a dot can find out what it is. The exceptions are
## VARIANTS of a kind that already has one (a free chest is a chest), and
## they are named in MapDraw.LEGEND_VARIANTS rather than here.
func _check_marker_labels() -> void:
	var failures: Array[String] = []
	var rows := 0
	var kinds: Dictionary[String, String] = {}
	for kind: StringName in MapDraw.MARKER_STYLES:
		kinds[String(kind)] = "MARKER_STYLES"
	for entry: Array in _assigned_marker_kinds():
		kinds[String(entry[0])] = String(entry[1])
	# The party, the boss and the way out are drawn always_visible and are
	# not things you go looking for in a legend.
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


## Every `marker_kind = &"..."` assignment in the codebase, as
## [kind, "file.gd:line"]. Scanned as text because the kinds are set in
## _init() on scenes this lint never instances.
func _assigned_marker_kinds() -> Array[Array]:
	var found: Array[Array] = []
	var pattern := RegEx.create_from_string('marker_kind\\s*=\\s*&"([a-z_]+)"')
	for path: String in _gd_files(SCRIPT_ROOTS):
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


## Every .gd under the given roots, recursively.
func _gd_files(roots: Array[String]) -> Array[String]:
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
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found
