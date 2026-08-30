class_name QuestCatalog
extends RefCounted
## Static catalog of launch quests (GDD 8): the challenges that pay out
## Shards. Data-driven like the other catalogs — a new quest is one row.
## Row fields:
##   id/display_name/description: identity plus the quest-log lines.
##   stat:   SaveData counter stat id the quest watches (see the canonical
##           id list in save_data.gd). Lifetime counters accumulate across
##           runs; max_level and best_run_minutes are single-run
##           high-water marks, so those quests read "in one run".
##   target: counter value that completes the quest (evaluated on run end;
##           claiming the reward stays manual, in the quest log).
##   reward: Shards granted on claim (10-80, scaled to difficulty).

const QUEST_LIBRARY: Array[Dictionary] = [
	# Kill milestones (lifetime).
	{
		"id": "kills_100", "display_name": "Hundred Down",
		"description": "Defeat 100 enemies.",
		"stat": "total_kills", "target": 100, "reward": 10,
	},
	{
		"id": "kills_500", "display_name": "Cull the Tide",
		"description": "Defeat 500 enemies.",
		"stat": "total_kills", "target": 500, "reward": 20,
	},
	{
		"id": "kills_2000", "display_name": "Horde Accountant",
		"description": "Defeat 2,000 enemies.",
		"stat": "total_kills", "target": 2000, "reward": 40,
	},
	{
		"id": "kills_5000", "display_name": "Extinction Event",
		"description": "Defeat 5,000 enemies.",
		"stat": "total_kills", "target": 5000, "reward": 80,
	},
	# Boss kills (lifetime).
	{
		"id": "bosses_1", "display_name": "Kingslayer",
		"description": "Bring down your first boss.",
		"stat": "bosses_killed", "target": 1, "reward": 15,
	},
	{
		"id": "bosses_5", "display_name": "Crown Collector",
		"description": "Bring down 5 bosses.",
		"stat": "bosses_killed", "target": 5, "reward": 35,
	},
	{
		"id": "bosses_15", "display_name": "Dynasty's End",
		"description": "Bring down 15 bosses.",
		"stat": "bosses_killed", "target": 15, "reward": 70,
	},
	# Survival marks (best single run).
	{
		"id": "survive_5", "display_name": "Five Alive",
		"description": "Survive 5 minutes in one run.",
		"stat": "best_run_minutes", "target": 5, "reward": 10,
	},
	{
		"id": "survive_10", "display_name": "Double Digits",
		"description": "Survive 10 minutes in one run.",
		"stat": "best_run_minutes", "target": 10, "reward": 25,
	},
	{
		"id": "survive_15", "display_name": "Went the Distance",
		"description": "Survive 15 minutes in one run.",
		"stat": "best_run_minutes", "target": 15, "reward": 50,
	},
	# Level marks (best single run).
	{
		"id": "level_10", "display_name": "Growth Spurt",
		"description": "Reach level 10 in one run.",
		"stat": "max_level", "target": 10, "reward": 10,
	},
	{
		"id": "level_20", "display_name": "Seasoned Raider",
		"description": "Reach level 20 in one run.",
		"stat": "max_level", "target": 20, "reward": 25,
	},
	{
		"id": "level_30", "display_name": "Apex Form",
		"description": "Reach level 30 in one run.",
		"stat": "max_level", "target": 30, "reward": 50,
	},
	# Victories (lifetime).
	{
		"id": "wins_1", "display_name": "Saw the Dawn",
		"description": "Win a run.",
		"stat": "victories", "target": 1, "reward": 40,
	},
	{
		"id": "wins_3", "display_name": "Habitual Winner",
		"description": "Win 3 runs.",
		"stat": "victories", "target": 3, "reward": 80,
	},
	# Runs finished (lifetime; a run counts once it ends, win or lose).
	{
		"id": "runs_3", "display_name": "Getting a Feel",
		"description": "Finish 3 runs.",
		"stat": "runs_finished", "target": 3, "reward": 10,
	},
	{
		"id": "runs_10", "display_name": "Regular Raider",
		"description": "Finish 10 runs.",
		"stat": "runs_finished", "target": 10, "reward": 25,
	},
	{
		"id": "runs_25", "display_name": "Lifer",
		"description": "Finish 25 runs.",
		"stat": "runs_finished", "target": 25, "reward": 60,
	},
	# Shrines (lifetime).
	{
		"id": "shrines_3", "display_name": "Devout",
		"description": "Use 3 shrines.",
		"stat": "shrines_used", "target": 3, "reward": 15,
	},
	{
		"id": "shrines_10", "display_name": "Shrine Circuit",
		"description": "Use 10 shrines.",
		"stat": "shrines_used", "target": 10, "reward": 35,
	},
	# Chests (lifetime).
	{
		"id": "chests_3", "display_name": "Lid Lifter",
		"description": "Open 3 chests.",
		"stat": "chests_opened", "target": 3, "reward": 15,
	},
	{
		"id": "chests_10", "display_name": "Treasure Route",
		"description": "Open 10 chests.",
		"stat": "chests_opened", "target": 10, "reward": 35,
	},
	# Per-character flavor.
	{
		"id": "rook_win", "display_name": "Rook's Proof",
		"description": "Win a run as Rook.",
		"stat": "wins_as_rook", "target": 1, "reward": 40,
	},
	{
		"id": "vex_runs_5", "display_name": "Vex's Routine",
		"description": "Finish 5 runs as Vex.",
		"stat": "runs_as_vex", "target": 5, "reward": 30,
	},
	# Per-map flavor (Ash Dunes opens after the first victory, so these
	# double as the reward trail for using the new unlock).
	{
		"id": "dunes_run_1", "display_name": "Dune Strider",
		"description": "Finish a run in Ash Dunes.",
		"stat": "runs_on_ash_dunes", "target": 1, "reward": 40,
	},
	{
		"id": "dunes_runs_3", "display_name": "Sandblasted",
		"description": "Finish 3 runs in Ash Dunes.",
		"stat": "runs_on_ash_dunes", "target": 3, "reward": 50,
	},
	# Hidden minibosses (GDD 6 secrets). Descriptions stay vague on purpose:
	# the quest log teases that a secret exists without mapping the trigger.
	{
		"id": "secret_grubthing", "display_name": "What Lurks Below",
		"description": "Defeat what sleeps beneath the Hollow Woods.",
		"stat": "slain_grubthing", "target": 1, "reward": 60,
	},
	{
		"id": "secret_coffer_mimic", "display_name": "Tomb Raider",
		"description": "Unearth and defeat the tomb-thing of the Ash Dunes.",
		"stat": "slain_coffer_mimic", "target": 1, "reward": 60,
	},
]


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(quest_id: String) -> Dictionary:
	for row: Dictionary in QUEST_LIBRARY:
		if String(row.id) == quest_id:
			return row
	return {}
