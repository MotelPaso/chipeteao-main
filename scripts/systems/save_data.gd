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
## Canonical counter stat ids (quest_catalog rows target these):
##   total_kills, bosses_killed, runs_finished, victories, shrines_used,
##   chests_opened, max_level (high-water), best_run_minutes (high-water),
##   runs_as_<character_id>, wins_as_<character_id>.

signal shards_changed(balance: int)

const DEFAULT_SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

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
## just hit its target (claiming stays manual, in the quest log), saves,
## and returns {"new_quest_ids": Array[String], "reward_shards": int} —
## the claimable Shard value of the newly completed quests.
func fold_run_results(victory: bool, character_id: String,
		level: int, kills: int, run_seconds: float) -> Dictionary:
	bump("total_kills", kills)
	bump("runs_finished")
	bump("runs_as_" + character_id)
	if victory:
		bump("victories")
		bump("wins_as_" + character_id)
	raise_to("max_level", level)
	raise_to("best_run_minutes", int(run_seconds / 60.0))
	last_new_quest_ids = _evaluate_quests()
	last_reward_shards = 0
	for quest_id: String in last_new_quest_ids:
		last_reward_shards += int(QuestCatalog.by_id(quest_id).reward)
	save()
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


## --- Character unlocks -------------------------------------------------

func is_unlocked(character_id: String) -> bool:
	return unlocked_character_ids.has(character_id)


func can_afford(cost: int) -> bool:
	return shards >= cost


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
	unlocked_character_ids.append(character_id)
	purchased_character_ids.append(character_id)
	save()
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


func _to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"shards": shards,
		"unlocked_characters": unlocked_character_ids,
		"purchased_characters": purchased_character_ids,
		"counters": counters,
		"completed_quests": completed_quest_ids,
		"claimed_quests": claimed_quest_ids,
	}


## --- JSON round-trip helpers (parsed values arrive untyped; numbers as
## floats). Anything malformed degrades to the empty/zero default. -------

static func _as_int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
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
