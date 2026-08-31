extends Node
## Autoload "GameConfig": configuration chosen outside a run that must
## survive scene changes and RunState.reset() — kept separate from the
## run-scoped RunState so per-run resets can never wipe it. No disk
## persistence yet; defaults apply once per app launch.

## CharacterCatalog id the next run spawns with. Set by the character
## select screen; an arena booted directly (headless soaks) keeps the
## default.
var selected_character_id: String = CharacterCatalog.DEFAULT_ID

## MapCatalog id of the arena the next run loads (and, mid-run, the arena
## being played). Set by the select screen; the arena's RunSystems root
## republishes it at ready so direct boots stay consistent.
var selected_map_id: String = MapCatalog.DEFAULT_ID

## Map tier (1..MapCatalog.TIER_COUNT) the next run plays at. The select
## screen resets it to 1 when switching to a map where the pick is still
## locked, and RunSystems clamps it again at ready (direct boots, stale
## cross-map picks), so an unearned tier can never reach a spawner.
var selected_tier: int = 1
