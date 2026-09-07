class_name QuestCatalog
extends RefCounted
## Static catalog of launch quests (GDD 8): the challenges that pay out
## Shards. Data-driven like the other catalogs — a new quest is one row.
## Row fields:
##   id:     identifier (English, keys SaveData completion) — never shown.
##   display_name/description: the quest-log lines, in player language.
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
		"id": "kills_100", "display_name": "Cien caídos",
		"description": "Derrota a 100 enemigos.",
		"stat": "total_kills", "target": 100, "reward": 10,
	},
	{
		"id": "kills_500", "display_name": "Diezma la marea",
		"description": "Derrota a 500 enemigos.",
		"stat": "total_kills", "target": 500, "reward": 20,
	},
	{
		"id": "kills_2000", "display_name": "Contador de hordas",
		"description": "Derrota a 2000 enemigos.",
		"stat": "total_kills", "target": 2000, "reward": 40,
	},
	{
		"id": "kills_5000", "display_name": "Evento de extinción",
		"description": "Derrota a 5000 enemigos.",
		"stat": "total_kills", "target": 5000, "reward": 80,
	},
	# Boss kills (lifetime).
	{
		"id": "bosses_1", "display_name": "Matarreyes",
		"description": "Abate a tu primer jefe.",
		"stat": "bosses_killed", "target": 1, "reward": 15,
	},
	{
		"id": "bosses_5", "display_name": "Cazacoronas",
		"description": "Abate a 5 jefes.",
		"stat": "bosses_killed", "target": 5, "reward": 35,
	},
	{
		"id": "bosses_15", "display_name": "Fin de la dinastía",
		"description": "Abate a 15 jefes.",
		"stat": "bosses_killed", "target": 15, "reward": 70,
	},
	# Survival marks (best single run).
	{
		"id": "survive_5", "display_name": "Cinco y vivo",
		"description": "Sobrevive 5 minutos en una incursión.",
		"stat": "best_run_minutes", "target": 5, "reward": 10,
	},
	{
		"id": "survive_10", "display_name": "Dos cifras",
		"description": "Sobrevive 10 minutos en una incursión.",
		"stat": "best_run_minutes", "target": 10, "reward": 25,
	},
	{
		"id": "survive_15", "display_name": "Hasta el final",
		"description": "Sobrevive 15 minutos en una incursión.",
		"stat": "best_run_minutes", "target": 15, "reward": 50,
	},
	# Level marks (best single run).
	{
		"id": "level_10", "display_name": "Estirón",
		"description": "Llega al nivel 10 en una incursión.",
		"stat": "max_level", "target": 10, "reward": 10,
	},
	{
		"id": "level_20", "display_name": "Raider veterano",
		"description": "Llega al nivel 20 en una incursión.",
		"stat": "max_level", "target": 20, "reward": 25,
	},
	{
		"id": "level_30", "display_name": "Forma suprema",
		"description": "Llega al nivel 30 en una incursión.",
		"stat": "max_level", "target": 30, "reward": 50,
	},
	# Victories (lifetime).
	{
		"id": "wins_1", "display_name": "Viste el amanecer",
		"description": "Gana una incursión.",
		"stat": "victories", "target": 1, "reward": 40,
	},
	{
		"id": "wins_3", "display_name": "Ganar es costumbre",
		"description": "Gana 3 incursiones.",
		"stat": "victories", "target": 3, "reward": 80,
	},
	# Runs finished (lifetime; a run counts once it ends, win or lose).
	{
		"id": "runs_3", "display_name": "Agarrando el ritmo",
		"description": "Termina 3 incursiones.",
		"stat": "runs_finished", "target": 3, "reward": 10,
	},
	{
		"id": "runs_10", "display_name": "Raider asiduo",
		"description": "Termina 10 incursiones.",
		"stat": "runs_finished", "target": 10, "reward": 25,
	},
	{
		"id": "runs_25", "display_name": "Cadena perpetua",
		"description": "Termina 25 incursiones.",
		"stat": "runs_finished", "target": 25, "reward": 60,
	},
	# Shrines (lifetime).
	{
		"id": "shrines_3", "display_name": "Devoto",
		"description": "Usa 3 altares.",
		"stat": "shrines_used", "target": 3, "reward": 15,
	},
	{
		"id": "shrines_10", "display_name": "Ruta de altares",
		"description": "Usa 10 altares.",
		"stat": "shrines_used", "target": 10, "reward": 35,
	},
	# Chests (lifetime).
	{
		"id": "chests_3", "display_name": "Levantatapas",
		"description": "Abre 3 cofres.",
		"stat": "chests_opened", "target": 3, "reward": 15,
	},
	{
		"id": "chests_10", "display_name": "Ruta del tesoro",
		"description": "Abre 10 cofres.",
		"stat": "chests_opened", "target": 10, "reward": 35,
	},
	# Per-character flavor.
	{
		"id": "rook_win", "display_name": "La prueba de Rook",
		"description": "Gana una incursión con Rook.",
		"stat": "wins_as_rook", "target": 1, "reward": 40,
	},
	{
		"id": "vex_runs_5", "display_name": "La rutina de Vex",
		"description": "Termina 5 incursiones con Vex.",
		"stat": "runs_as_vex", "target": 5, "reward": 30,
	},
	# Per-map flavor (Ash Dunes opens after the first victory, so these
	# double as the reward trail for using the new unlock).
	{
		"id": "dunes_run_1", "display_name": "Andadunas",
		"description": "Termina una incursión en las Dunas de Ceniza.",
		"stat": "runs_on_ash_dunes", "target": 1, "reward": 40,
	},
	{
		"id": "dunes_runs_3", "display_name": "Curtido por la arena",
		"description": "Termina 3 incursiones en las Dunas de Ceniza.",
		"stat": "runs_on_ash_dunes", "target": 3, "reward": 50,
	},
	# Gloomfen (iteration 37; opens after the first Ash Dunes victory).
	{
		"id": "fen_run_1", "display_name": "Hacia el fango",
		"description": "Termina una incursión en la Ciénaga Lóbrega.",
		"stat": "runs_on_gloomfen", "target": 1, "reward": 40,
	},
	{
		"id": "fen_win_1", "display_name": "Andaciénagas",
		"description": "Gana una incursión en la Ciénaga Lóbrega.",
		"stat": "victories_gloomfen", "target": 1, "reward": 70,
	},
	{
		"id": "fenwraith_5", "display_name": "Azote de espectros",
		"description": "Abate al Espectro de la Ciénaga 5 veces.",
		"stat": "kills_fenwraith", "target": 5, "reward": 80,
	},
	# Map tiers (win-gated ladders; any map counts).
	{
		# Iteration 50: the tier ladder became LAPS of the map list. The ids
		# and the stat keys are kept so a save that already earned them
		# stays earned; only what they mean changed.
		"id": "tier2_win", "display_name": "Segunda vuelta",
		"description": "Completa una vuelta entera al circuito de mapas.",
		"stat": "any_t2_win", "target": 1, "reward": 70,
	},
	{
		"id": "tier3_win", "display_name": "Tercera vuelta",
		"description": "Completa dos vueltas enteras al circuito de mapas.",
		"stat": "any_t3_win", "target": 1, "reward": 120,
	},
	# Weapon evolutions (iteration 38): reach the evolve level on a weapon.
	{
		"id": "evolve_1", "display_name": "Trascendencia",
		"description": "Evoluciona un arma subiéndola lo suficiente de nivel.",
		"stat": "evolutions_total", "target": 1, "reward": 50,
	},
	{
		"id": "evolve_4", "display_name": "Arsenal ascendente",
		"description": "Evoluciona 4 armas a lo largo de tus incursiones.",
		"stat": "evolutions_total", "target": 4, "reward": 90,
	},
	# Meta modes (iteration 36): the Armory, the Daily Hunt, and Endless.
	{
		"id": "relic_1", "display_name": "Primera reliquia",
		"description": "Compra un rango de reliquia en la Armería.",
		"stat": "relics_bought", "target": 1, "reward": 20,
	},
	{
		"id": "daily_1", "display_name": "Animal de costumbres",
		"description": "Termina una Cacería diaria.",
		"stat": "daily_runs", "target": 1, "reward": 30,
	},
	{
		"id": "daily_7", "display_name": "Ritualista",
		"description": "Termina 7 Cacerías diarias.",
		"stat": "daily_runs", "target": 7, "reward": 80,
	},
	{
		# Iteration 50: "endless" is now the pseudo-infinite time a run
		# spent past its stage gates, which is what the mode is for.
		"id": "endless_20", "display_name": "Más allá del amanecer",
		"description": "Quédate 20 minutos en modo pseudo-infinito tras superar una etapa.",
		"stat": "best_endless_minutes", "target": 20, "reward": 80,
	},
	{
		"id": "endless_25", "display_name": "La noche larga",
		"description": "Quédate 25 minutos en modo pseudo-infinito tras superar una etapa.",
		"stat": "best_endless_minutes", "target": 25, "reward": 150,
	},
	# Hidden minibosses (GDD 6 secrets). Descriptions stay vague on purpose:
	# the quest log teases that a secret exists without mapping the trigger.
	{
		"id": "secret_grubthing", "display_name": "Lo que acecha abajo",
		"description": "Derrota a lo que duerme bajo el Bosque Hueco.",
		"stat": "slain_grubthing", "target": 1, "reward": 60,
	},
	{
		"id": "secret_coffer_mimic", "display_name": "Saqueador de tumbas",
		"description": "Desentierra y derrota a la cosa sepulcral de las Dunas de Ceniza.",
		"stat": "slain_coffer_mimic", "target": 1, "reward": 60,
	},
]


## Lazily built id -> row index (see CatalogIndex): the quest log resolves
## one row per listed quest and SaveData one per completion check.
static var _by_id: Dictionary[String, Dictionary] = {}


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(quest_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(QUEST_LIBRARY)
	return _by_id.get(quest_id, {})
