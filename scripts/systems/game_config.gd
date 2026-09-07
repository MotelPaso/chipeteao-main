extends Node
## Autoload "GameConfig": configuration chosen outside a run that must
## survive scene changes and RunState.reset() — kept separate from the
## run-scoped RunState so per-run resets can never wipe it. No disk
## persistence yet; defaults apply once per app launch.

## CharacterCatalog id the next run spawns with. Set by the character
## select screen; an arena booted directly (headless soaks) keeps the
## default.
var selected_character_id: String = CharacterCatalog.DEFAULT_ID

## MapCatalog id of the map CURRENTLY being played. Written by RunRoot on
## every stage change, read by the meta fold and the end screen. It is no
## longer a choice — a run walks the whole map list.
var selected_map_id: String = MapCatalog.DEFAULT_ID

## MapCatalog id of the biome stage 1 starts on. Always the default in
## normal play and in the daily (every run opens in the forest); the soak
## harness points it at a biome so BONK_ARENA still means "soak this map",
## and a start past the first stage simply wraps to lap 1 sooner.
var start_map_id: String = MapCatalog.DEFAULT_ID

## --- Daily Hunt (iteration 36) ------------------------------------------
## True while the next/current run is the seeded daily challenge: fixed
## character/map for everyone that day, deterministic RNG (RunState seeds
## the global stream, the scatter adopts daily_seed), and a score recorded
## under daily_date. Cleared by a normal Start Run; Retry keeps it.
var daily_mode: bool = false
## Seed derived from today's date; also the scatter/global RNG seed.
var daily_seed: int = 0
## "YYYY-MM-DD" the daily was launched for (keys the best-score counter).
var daily_date: String = ""
## Score of the most recently ended daily run (RunManager writes it; the
## run-end screen reads it).
var last_daily_score: int = 0


## One deterministic score formula so every player's daily is comparable:
## kills weigh 1, levels 25, and each survived second 1.
static func daily_score(kills: int, level: int, run_seconds: float) -> int:
	return kills + level * 25 + int(run_seconds)
