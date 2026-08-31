extends Node
## Autoload "SaveData": the between-runs meta-progression ledger (GDD 8) —
## Shard balance, unlocked/purchased characters, lifetime quest counters,
## and completed/claimed quest ids — persisted as JSON at user://save.json.
## Deliberately holds NO permanent stat buffs: Shards only ever buy
## character unlocks (GDD 8: mastery, not grinding, is the power curve).
##
## Write points: fold_run_results() on every run end (RunManager), plus
## purchases and quest claims. Mid-run systems credit counters with bump()
## / raise_to() in memory only, so an abandoned run persists nothing.
##
## Canonical counter stat ids (quest_catalog rows target these; map
## unlock rules in map_catalog target them too):
##   total_kills, bosses_killed, runs_finished, victories, shrines_used,
##   chests_opened, max_level (high-water), best_run_minutes (high-water),
##   runs_as_<character_id>, wins_as_<character_id>,
##   runs_on_<map_id>, victories_<map_id>,
##   victories_<map_id>_t<tier> (per-map-tier wins; tier N wins gate tier
##   N+1 — see is_tier_unlocked; victories_<map_id> keeps counting
##   any-tier wins so pre-tier quests and unlocks never regress),
##   any_t2_win / any_t3_win (tier-victory quests),
##   slain_<miniboss_id> (hidden-boss kills, bumped by SecretBossBase).

signal shards_changed(balance: int)

const DEFAULT_SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

## Settings defaults (the "settings" dict in the JSON). Volumes are 0..100
## slider values (100 = the pre-settings mix, see Settings.volume_to_db);
## sensitivity is a look multiplier on the player's exported base.
const DEFAULT_SFX_VOLUME := 100.0
const DEFAULT_AMBIENT_VOLUME := 100.0
const DEFAULT_MOUSE_SENSITIVITY := 1.0
const MIN_MOUSE_SENSITIVITY := 0.3
const MAX_MOUSE_SENSITIVITY := 2.0

## Test harnesses point this at a scratch file before load_from_disk().
var save_path: String = DEFAULT_SAVE_PATH

var shards: int = 0
## Character ids playable right now (starters plus purchases).
var unlocked_character_ids: Array[String] = []
## Subset of unlocked ids that were bought with Shards (purchase history).
var purchased_character_ids: Array[String] = []
## Lifetime quest counters, keyed by stat id (see header).
var counters: Dictionary[String, int] = {}
## Quests whose target has been hit; claimable until they enter claimed.
var completed_quest_ids: Array[String] = []
var claimed_quest_ids: Array[String] = []

## Most recent fold_run_results() outcome, read by the run-end screen
## (the run_ended signal shape stays untouched; loose coupling via here).
var last_new_quest_ids: Array[String] = []
var last_reward_shards: int = 0
## Shards credited outright by the last fold's tier victory bonus (0 for a
## defeat or a tier-1 win).
var last_tier_bonus_shards: int = 0

## Last tier picked per map id on the select screen (a remembered-choice
## nicety, not a gate — the screen still clamps to unlocked tiers).
var tier_choices: Dictionary[String, int] = {}

## --- Settings (persisted values; the Settings autoload applies them to
## buses/window and is the only writer — see settings_apply.gd) ----------
var sfx_volume: float = DEFAULT_SFX_VOLUME
var ambient_volume: float = DEFAULT_AMBIENT_VOLUME
## Look-speed multiplier the player applies on top of its exported base.
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var fullscreen: bool = false


func _ready() -> void:
	load_from_disk()


## --- Counters ---------------------------------------------------------

func stat(stat_id: String) -> int:
	return int(counters.get(stat_id, 0))


## In-memory increment for cumulative counters. Shrines, chests, and boss
## deaths call this where they resolve; persistence happens at the next
## save point (run end / purchase / claim).
func bump(stat_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	counters[stat_id] = stat(stat_id) + amount


## High-water counters (best level / best minutes in one run).
func raise_to(stat_id: String, value: int) -> void:
	if value > stat(stat_id):
		counters[stat_id] = value


## --- Run-end fold (RunManager) ----------------------------------------

## Folds one finished run into the lifetime counters, marks any quest that
## just hit its target (claiming stays manual, in the quest log), credits
## any tier victory bonus outright, saves, and returns
## {"new_quest_ids": Array[String], "reward_shards": int} — the claimable
## Shard value of the newly completed quests (the tier bonus is separate,
## in last_tier_bonus_shards, because it needs no claim).
func fold_run_results(victory: bool, character_id: String, map_id: String, tier: int,
		level: int, kills: int, run_seconds: float) -> Dictionary:
	tier = clampi(tier, 1, MapCatalog.TIER_COUNT)
	bump("total_kills", kills)
	bump("runs_finished")
	bump("runs_as_" + character_id)
	bump("runs_on_" + map_id)
	last_tier_bonus_shards = 0
	if victory:
		bump("victories")
		bump("wins_as_" + character_id)
		bump("victories_" + map_id)
		bump("victories_%s_t%d" % [map_id, tier])
		if tier >= 2:
			bump("any_t%d_win" % tier)
			last_tier_bonus_shards = MapCatalog.tier_shard_bonus(map_id, tier)
			shards += last_tier_bonus_shards
	raise_to("max_level", level)
	raise_to("best_run_minutes", int(run_seconds / 60.0))
	last_new_quest_ids = _evaluate_quests()
	last_reward_shards = 0
	for quest_id: String in last_new_quest_ids:
		last_reward_shards += int(QuestCatalog.by_id(quest_id).reward)
	save()
	if last_tier_bonus_shards > 0:
		shards_changed.emit(shards)
	return {
		"new_quest_ids": last_new_quest_ids,
		"reward_shards": last_reward_shards,
	}


## Marks every not-yet-completed quest whose counter reached its target;
## returns the newly completed ids. completed_quest_ids persists, so a
## quest can never complete (or pay out) twice.
func _evaluate_quests() -> Array[String]:
	var newly: Array[String] = []
	for quest: Dictionary in QuestCatalog.QUEST_LIBRARY:
		var quest_id := String(quest.id)
		if completed_quest_ids.has(quest_id):
			continue
		if stat(String(quest.stat)) >= int(quest.target):
			completed_quest_ids.append(quest_id)
			newly.append(quest_id)
	return newly


## --- Quest claims ------------------------------------------------------

func is_quest_completed(quest_id: String) -> bool:
	return completed_quest_ids.has(quest_id)


func is_quest_claimed(quest_id: String) -> bool:
	return claimed_quest_ids.has(quest_id)


## Credits a completed, unclaimed quest's Shards exactly once and saves.
## Returns the Shards granted (0 if the quest is not claimable).
func claim_quest(quest_id: String) -> int:
	if not is_quest_completed(quest_id) or is_quest_claimed(quest_id):
		return 0
	var quest := QuestCatalog.by_id(quest_id)
	if quest.is_empty():
		return 0
	var reward := int(quest.reward)
	claimed_quest_ids.append(quest_id)
	shards += reward
	save()
	shards_changed.emit(shards)
	return reward


## --- Map unlocks --------------------------------------------------------

## A map is playable when its catalog unlock rule is met: rows with an
## empty unlock_stat are always open; otherwise the named lifetime
## counter must reach unlock_target (Ash Dunes: victories >= 1). Unknown
## ids read as locked.
func is_map_unlocked(map_id: String) -> bool:
	var row := MapCatalog.by_id(map_id)
	if row.is_empty():
		return false
	var stat_id := String(row.unlock_stat)
	if stat_id.is_empty():
		return true
	return stat(stat_id) >= int(row.unlock_target)


## --- Map tiers ----------------------------------------------------------

## Tier 1 is always playable on any known map; tier N+1 unlocks by WINNING
## tier N on that same map (per-map, so a Hollow Woods T2 win says nothing
## about Ash Dunes). Legacy saves have no per-tier counters, so they read
## as "only T1 unlocked" — exactly right.
func is_tier_unlocked(map_id: String, tier: int) -> bool:
	if MapCatalog.by_id(map_id).is_empty():
		return false
	if tier == 1:
		return true
	if tier < 1 or tier > MapCatalog.TIER_COUNT:
		return false
	return stat("victories_%s_t%d" % [map_id, tier - 1]) >= 1


## Remembered select-screen tier pick for a map (1 when never picked).
func tier_choice(map_id: String) -> int:
	return clampi(int(tier_choices.get(map_id, 1)), 1, MapCatalog.TIER_COUNT)


func set_tier_choice(map_id: String, tier: int) -> void:
	tier = clampi(tier, 1, MapCatalog.TIER_COUNT)
	if tier_choice(map_id) == tier:
		return
	tier_choices[map_id] = tier
	save()


## --- Character unlocks -------------------------------------------------

func is_unlocked(character_id: String) -> bool:
	return unlocked_character_ids.has(character_id)


func can_afford(cost: int) -> bool:
	return shards >= cost


## Grants a character outright — the single unlock write both paths share.
## Boss kills call this directly with source "boss" (no Shard cost, GDD 5's
## skill-unlock path); purchase_character routes through it with source
## "purchase", the only tag that also records purchase history. Idempotent:
## an unknown or already-unlocked/purchased id is a no-op returning false;
## a fresh unlock persists immediately and returns true.
func unlock_character(character_id: String, source: String) -> bool:
	if CharacterCatalog.by_id(character_id).is_empty() or is_unlocked(character_id):
		return false
	unlocked_character_ids.append(character_id)
	if source == "purchase":
		purchased_character_ids.append(character_id)
	save()
	return true


## Buys a locked catalog character at its row's unlock_cost. Deducts,
## unlocks, records the purchase, saves. False (and no deduction) when the
## id is unknown, already unlocked, or the balance is short.
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


## --- Disk -------------------------------------------------------------

## Loads save_path, falling back to clean defaults on a missing, corrupt,
## or wrongly-typed file (never crashes; a bad file just starts fresh).
func load_from_disk() -> void:
	_apply_defaults()
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("SaveData: cannot read %s; using defaults." % save_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_warning("SaveData: %s is not valid JSON; using defaults." % save_path)
		return
	var data := parsed as Dictionary
	shards = maxi(_as_int(data.get("shards"), 0), 0)
	unlocked_character_ids = _as_string_array(data.get("unlocked_characters"))
	purchased_character_ids = _as_string_array(data.get("purchased_characters"))
	counters = _as_int_dict(data.get("counters"))
	completed_quest_ids = _as_string_array(data.get("completed_quests"))
	claimed_quest_ids = _as_string_array(data.get("claimed_quests"))
	# Missing on legacy (pre-tier) saves: every map just remembers tier 1.
	tier_choices = _as_int_dict(data.get("tier_choice"))
	_load_settings(data.get("settings"))
	# Starters are always playable, even if an edited file dropped them.
	for starter_id: String in CharacterCatalog.starter_ids():
		if not unlocked_character_ids.has(starter_id):
			unlocked_character_ids.append(starter_id)


func save() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveData: cannot write %s." % save_path)
		return
	file.store_string(JSON.stringify(_to_save_dict(), "\t"))


func _apply_defaults() -> void:
	shards = 0
	unlocked_character_ids = CharacterCatalog.starter_ids()
	purchased_character_ids = []
	counters = {}
	completed_quest_ids = []
	claimed_quest_ids = []
	tier_choices = {}
	sfx_volume = DEFAULT_SFX_VOLUME
	ambient_volume = DEFAULT_AMBIENT_VOLUME
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	fullscreen = false


## Missing/legacy "settings" (pre-iteration-22 saves) or malformed entries
## keep the defaults _apply_defaults just set; values clamp to legal ranges.
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


func _to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"shards": shards,
		"unlocked_characters": unlocked_character_ids,
		"purchased_characters": purchased_character_ids,
		"counters": counters,
		"completed_quests": completed_quest_ids,
		"claimed_quests": claimed_quest_ids,
		"tier_choice": tier_choices,
		"settings": {
			"sfx_volume": sfx_volume,
			"ambient_volume": ambient_volume,
			"mouse_sensitivity": mouse_sensitivity,
			"fullscreen": fullscreen,
		},
	}


## --- JSON round-trip helpers (parsed values arrive untyped; numbers as
## floats). Anything malformed degrades to the empty/zero default. -------

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
