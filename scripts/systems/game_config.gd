extends Node
## Autoload "GameConfig": configuration chosen outside a run that must
## survive scene changes and RunState.reset() — kept separate from the
## run-scoped RunState so per-run resets can never wipe it. No disk
## persistence yet; defaults apply once per app launch.

## CharacterCatalog id the next run spawns with. Set by the character
## select screen; Main booted directly (headless soaks) keeps the default.
var selected_character_id: String = CharacterCatalog.DEFAULT_ID
