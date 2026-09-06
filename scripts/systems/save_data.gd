extends Node
## Autoload "SaveData": the between-runs meta-progression ledger (GDD 8) —
## Shard balance, unlocked/purchased characters, lifetime quest counters,
## and completed/claimed quest ids — persisted as JSON at user://save.json.
## Shards buy character unlocks and, since iteration 36, Armory relic ranks
## (small permanent stat buffs — RelicCatalog keeps the amounts modest so
## mastery, not grinding, remains the real power curve per GDD 8's intent).
##
## Write points: fold_run_results() on every run end (RunManager), plus
## purchases and quest claims. Mid-run systems credit counters with bump()
## / raise_to(), which land in a RUN BUFFER (_run_counters/_run_highs) that
## only a run END merges into the persisted ledger — so an abandoned run
## persists nothing even though a purchase, a quest claim or a secret-boss
## unlock can write the file while that run is still going. RunState.reset()
## drops whatever is pending (run start and the abandon path both go
## through it). Progress readouts use stat() (ledger + buffer); quest
## completion deliberately reads the LEDGER only, so a quest can never be
## marked complete off counters that a later abandon rolls back.
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
##   slain_<miniboss_id> (hidden-boss kills, bumped by SecretBossBase),
##   used_weapon_<weapon_id> (Collection: ever carried; Player/UpgradePool),
##   evo_<weapon_id> / evolutions_total (chest evolution ceremonies),
##   kills_<enemy_script> (bestiary, bumped by EnemyBase on death),
##   relics_bought (Armory purchases), daily_runs / daily_best_<date>
##   (Daily Hunt; best is a per-date high-water), best_endless_minutes
##   (longest victorious run in minutes; runs have no clock since it. 38).

signal shards_changed(balance: int)

const DEFAULT_SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
## save() writes here first and only renames on success, so an interrupted
## write can never truncate the real file...
const TEMP_SUFFIX := ".tmp"
## ...and the copy it replaces stays around as the last-known-good file.
const BACKUP_SUFFIX := ".bak"

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
## Lifetime quest counters, keyed by stat id (see header). Only credits
## that survived a run end (or happened outside a run) live here — this is
## the dictionary save() serializes.
var counters: Dictionary[String, int] = {}
## In-run credit buffer: bump() lands here (as a delta) and raise_to() in
## _run_highs (as an absolute high-water), and both only reach `counters`
## when fold_run_results merges them. Abandoning drops them.
var _run_counters: Dictionary[String, int] = {}
var _run_highs: Dictionary[String, int] = {}
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

## Owned Armory ranks per relic id (iteration 36; see RelicCatalog).
var relic_ranks: Dictionary[String, int] = {}

## True when the file on disk was written by a NEWER build: its schema is
## unknown here, so this build plays on defaults and never writes, rather
## than silently downgrading real progress.
var _read_only: bool = false

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

## Lifetime value INCLUDING what the current run has credited so far — the
## number to show a player (quest-log progress bars, map unlock checks).
func stat(stat_id: String) -> int:
	return maxi(_persisted_stat(stat_id) + int(_run_counters.get(stat_id, 0)),
			int(_run_highs.get(stat_id, 0)))


## Value already on disk, ignoring the current run's pending credits. Quest
## completion evaluates against THIS so an abandoned run can never leave a
## quest permanently marked complete off counters that rolled back.
func _persisted_stat(stat_id: String) -> int:
	return int(counters.get(stat_id, 0))


## In-run increment for cumulative counters. Shrines, chests, and boss
## deaths call this where they resolve; it becomes permanent only when the
## run is folded (see the header).
func bump(stat_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_run_counters[stat_id] = int(_run_counters.get(stat_id, 0)) + amount


## High-water counters (best level / best minutes in one run).
func raise_to(stat_id: String, value: int) -> void:
	if value > stat(stat_id):
		_run_highs[stat_id] = value


## Credit that must persist immediately because it happens OUTSIDE a run
## (Armory purchases): straight into the ledger, bypassing the run buffer
## that only a fold commits.
func _credit_now(stat_id: String, amount: int = 1) -> void:
	counters[stat_id] = _persisted_stat(stat_id) + amount


## Merges the run buffer into the lifetime ledger. ONLY fold_run_results
## calls this: it is the single point where a run's credits become real.
func _merge_run_counters() -> void:
	for stat_id: String in _run_counters:
		counters[stat_id] = _persisted_stat(stat_id) + _run_counters[stat_id]
	for stat_id: String in _run_highs:
		counters[stat_id] = maxi(_persisted_stat(stat_id), _run_highs[stat_id])
	_run_counters.clear()
	_run_highs.clear()


## Drops every credit the current run made without folding. Called by
## RunState.reset(), which every run start AND the "Quit to Menu" abandon
## path go through.
func discard_run_counters() -> void:
	_run_counters.clear()
	_run_highs.clear()


## --- Run-end fold (RunManager) ----------------------------------------

## Folds one finished run into the lifetime counters, marks any quest that
## just hit its target (claiming stays manual, in the quest log), credits
## any tier victory bonus outright and saves. The outcome is published in
## last_new_quest_ids / last_reward_shards / last_tier_bonus_shards, which
## RunManager and the run-end screen read (the tier bonus is separate
## because it needs no claim).
##
## `character_ids` is the WHOLE party (one entry per co-op slot, solo is a
## single id): every distinct raider in it earns the runs_as_/wins_as_
## credit, so slots 1..3 stop playing for free.
func fold_run_results(victory: bool, character_ids: Array[String], map_id: String, tier: int,
		level: int, kills: int, run_seconds: float) -> void:
	tier = clampi(tier, 1, MapCatalog.TIER_COUNT)
	var party := _distinct(character_ids)
	bump("total_kills", kills)
	bump("runs_finished")
	bump("runs_on_" + map_id)
	for character_id: String in party:
		bump("runs_as_" + character_id)
	last_tier_bonus_shards = 0
	if victory:
		bump("victories")
		bump("victories_" + map_id)
		bump("victories_%s_t%d" % [map_id, tier])
		for character_id: String in party:
			bump("wins_as_" + character_id)
		if tier >= 2:
			bump("any_t%d_win" % tier)
			last_tier_bonus_shards = MapCatalog.tier_shard_bonus(map_id, tier)
			shards += last_tier_bonus_shards
	raise_to("max_level", level)
	raise_to("best_run_minutes", int(run_seconds / 60.0))
	# Iteration 38: runs have no clock, so "endless" minutes are simply a
	# victorious run's total (the counter name is kept for old saves/quests).
	if victory:
		raise_to("best_endless_minutes", int(run_seconds / 60.0))
	# The run reached its end, so everything it credited becomes permanent
	# BEFORE the quests are judged — this is the only merge point.
	_merge_run_counters()
	last_new_quest_ids = _commit(last_tier_bonus_shards > 0)
	last_reward_shards = 0
	for quest_id: String in last_new_quest_ids:
		last_reward_shards += int(QuestCatalog.by_id(quest_id).reward)


## Ids without repeats, order preserved (a co-op party can field the same
## raider twice; the credit is per raider, not per slot).
static func _distinct(ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


## The single commit point: judge the quests against what is now on the
## ledger, persist, and optionally announce the new balance. Every write
## path goes through it, so a counter credited OUTSIDE a run (an Armory
## purchase) completes its quest right away instead of waiting for the
## next run to end.
func _commit(emit_shards: bool = false) -> Array[String]:
	var newly := _evaluate_quests()
	save()
	if emit_shards:
		shards_changed.emit(shards)
	return newly


## Marks every not-yet-completed quest whose PERSISTED counter reached its
## target; returns the newly completed ids. completed_quest_ids persists,
## so a quest can never complete (or pay out) twice.
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
	_commit(true)
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


## --- Relics (Armory; iteration 36) --------------------------------------

func relic_rank(relic_id: String) -> int:
	return int(relic_ranks.get(relic_id, 0))


## Buys the next rank of a relic at RelicCatalog's price ladder. Deducts,
## records, saves, and returns true; false (and no deduction) when the id
## is unknown, capped, or the balance is short. The purchase happens
## outside a run, so its counter is credited straight to the ledger and
## _commit judges the quests on it right away (the "First Relic" quest is
## claimable the moment you buy, without finishing another run).
func purchase_relic(relic_id: String) -> bool:
	var cost := RelicCatalog.next_rank_cost(relic_id, relic_rank(relic_id))
	if cost < 0 or not can_afford(cost):
		return false
	shards -= cost
	relic_ranks[relic_id] = relic_rank(relic_id) + 1
	_credit_now("relics_bought")
	_commit(true)
	return true


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
	_commit()
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

## Loads save_path, falling back to the .bak copy and then to clean
## defaults on a missing, corrupt, or wrongly-typed file (never crashes; a
## bad file just starts fresh). A file from a newer build is read as far as
## this schema allows and then locked (see _read_only) instead of being
## overwritten.
func load_from_disk() -> void:
	_apply_defaults()
	_read_only = false
	discard_run_counters()
	var data := _read_save_dict(save_path)
	if data.is_empty():
		# save() only ever renames a complete file into place and keeps the
		# one it replaced, so a truncated main file has a good predecessor.
		data = _read_save_dict(save_path + BACKUP_SUFFIX)
		if not data.is_empty():
			print("Save recovered from backup: %s" % save_path)
	if data.is_empty():
		return
	# Pre-versioned saves read as 0; every schema change since is additive
	# (missing keys fall back to defaults), so there is no migration to run
	# yet — this is where one would hang off.
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
	# Missing on legacy (pre-tier) saves: every map just remembers tier 1.
	tier_choices = _as_int_dict(data.get("tier_choice"))
	# Missing on pre-iteration-36 saves: no relics owned.
	relic_ranks = _as_int_dict(data.get("relics"))
	_load_settings(data.get("settings"))
	# Starters are always playable, even if an edited file dropped them.
	for starter_id: String in CharacterCatalog.starter_ids():
		if not unlocked_character_ids.has(starter_id):
			unlocked_character_ids.append(starter_id)


## Parsed contents of one save file, or {} when it is missing, unreadable
## or not a JSON object.
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


## Atomic write: the JSON goes to a temp file that is renamed over
## save_path only once it is complete, and the file it replaces is kept as
## .bak. A crash mid-write can therefore never leave a half-written
## save.json — which would take the whole meta-progression with it.
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
	tier_choices = {}
	relic_ranks = {}
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


## The persisted ledger. Note it serializes `counters` only: whatever the
## current run has pending in the buffer stays out of the file by design.
func _to_save_dict() -> Dictionary[String, Variant]:
	return {
		"version": SAVE_VERSION,
		"shards": shards,
		"unlocked_characters": unlocked_character_ids,
		"purchased_characters": purchased_character_ids,
		"counters": counters,
		"completed_quests": completed_quest_ids,
		"claimed_quests": claimed_quest_ids,
		"tier_choice": tier_choices,
		"relics": relic_ranks,
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
