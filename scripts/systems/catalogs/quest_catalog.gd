class_name QuestCatalog
extends RefCounted
## Catálogo de misiones: los desafíos que pagan esquirlas. Una misión nueva es
## una fila aquí.
##
## Se puede cambiar libremente: display_name, description, target, reward.
## Llave interna, NUNCA la cambies: id (SaveData guarda las misiones
## completadas y reclamadas por id).
## stat nombra un contador de SaveData (lista en save_data.gd). Los contadores
## con prefijo llevan un id de otro catálogo dentro del nombre y dejan de
## avanzar en silencio si ese id cambia:
##   runs_as_<id> / wins_as_<id>: id de CharacterCatalog.
##   runs_on_<id> / victories_<id>: id de MapCatalog.
##   slain_<id>: secret_boss_id de la escena de un jefe secreto.
##   kills_<script>: nombre del archivo del script del enemigo, sin .gd.
##   evo_<id> / used_weapon_<id>: id de WEAPON_LIBRARY.
##
## Campos de cada fila:
##   id: llave interna (ver arriba). Nunca se muestra.
##   display_name, description: líneas del registro de misiones.
##   stat: contador de SaveData que vigila la misión. Los contadores de toda
##       la vida se acumulan entre incursiones; max_level, best_run_minutes y
##       best_endless_minutes son máximos de una sola incursión, por eso esas
##       misiones dicen «en una incursión».
##   target: valor del contador que completa la misión (se evalúa al terminar
##       la incursión; reclamar el premio es manual, en el registro).
##   reward: esquirlas que da al reclamarla.

const QUEST_LIBRARY: Array[Dictionary] = [
	# Bajas (toda la vida).
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
	# Jefes abatidos (toda la vida).
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
	# Supervivencia (mejor incursión).
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
	# Nivel (mejor incursión).
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
	# Victorias (toda la vida).
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
	# Incursiones terminadas (toda la vida; cuenta al terminar, se gane o se pierda).
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
	# Altares (toda la vida).
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
	# Cofres (toda la vida).
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
	# Por personaje.
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
	# Por mapa.
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
	# Vueltas al circuito de mapas.
	{
		# Los ids tier*_win y los contadores any_t*_win no se renombran: los
		# guardados que ya completaron estas misiones las conservan así.
		"id": "tier2_win", "display_name": "Segunda vuelta",
		"description": "Completa una vuelta entera al circuito de mapas.",
		"stat": "any_t2_win", "target": 1, "reward": 70,
	},
	{
		"id": "tier3_win", "display_name": "Tercera vuelta",
		"description": "Completa dos vueltas enteras al circuito de mapas.",
		"stat": "any_t3_win", "target": 1, "reward": 120,
	},
	# Evoluciones de arma.
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
	# Modos meta: Armería, Cacería diaria y modo pseudo-infinito.
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
		# best_endless_minutes mide el tiempo que una incursión pasó en modo
		# pseudo-infinito después de superar una etapa.
		"id": "endless_20", "display_name": "Más allá del amanecer",
		"description": "Quédate 20 minutos en modo pseudo-infinito tras superar una etapa.",
		"stat": "best_endless_minutes", "target": 20, "reward": 80,
	},
	{
		"id": "endless_25", "display_name": "La noche larga",
		"description": "Quédate 25 minutos en modo pseudo-infinito tras superar una etapa.",
		"stat": "best_endless_minutes", "target": 25, "reward": 150,
	},
	# Minijefes ocultos. Las descripciones son vagas a propósito: el registro
	# insinúa que hay un secreto sin decir cómo se activa.
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


## Índice id -> fila armado al primer uso (ver CatalogIndex): el registro
## resuelve una fila por misión listada y SaveData una por misión completada
## o reclamada.
static var _by_id: Dictionary[String, Dictionary] = {}


## Fila con ese id, o un Dictionary vacío si no existe.
static func by_id(quest_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(QUEST_LIBRARY)
	return _by_id.get(quest_id, {})
