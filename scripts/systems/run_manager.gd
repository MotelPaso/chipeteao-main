extends Node
## Dueño del fin de partida y de la PUERTA DE ETAPA. La partida no tiene
## límite de reloj: sigue hasta que cae toda la party o el jugador extrae
## desde la pausa (extract_run). Lo que la califica son las etapas: una etapa
## se SUPERA cuando su reloj pasa stage_goal Y su jefe murió, lo que abre el
## portal de salida y arranca la rampa pseudo-infinita. Todo final (muerte o
## extracción) con al menos una etapa superada cuenta como victoria; si no,
## como derrota. Termina la partida exactamente una vez — marca RunState
## inactivo, detiene el spawner, pausa el árbol — y emite run_ended, que
## RunSystems.tscn conecta a la RunEndScreen.

signal run_ended(victory: bool)

## Segundos que debe durar una ETAPA antes de que su puerta pueda abrirse.
## Se mide con RunState.stage_time, así cada mapa de la partida tiene su
## tramo completo.
@export var stage_goal: float = 900.0

## Interruptor del harness: BONK_STAGE_FAST=1 supera una etapa a los
## STAGE_FAST_GOAL segundos y sin jefe, para que un soak cruce de etapa.
## Solo pruebas; nada del juego lo pone.
const STAGE_FAST_ENV: String = "BONK_STAGE_FAST"
const STAGE_FAST_GOAL: float = 60.0
## Aviso del momento en que se supera una etapa. Sin marcadores de formato:
## habla de la puerta que se acaba de abrir, no de un número.
@export var survival_text: String = "¡Etapa superada! Se abrió el portal — quédate cuanto quieras"

var _run_over: bool = false
## True si BONK_STAGE_FAST está puesto (se lee una vez, en _ready).
var _stage_fast: bool = false

## El Health de cada miembro de la party, conectado un frame después de
## _ready (el co-op crea los cuerpos extra en RunSystems._ready, que corre
## después del de este hijo).
var _party_health: Array[Health] = []


func _ready() -> void:
	# El menú de pausa llega por este grupo para extraer.
	add_to_group("run_manager")
	_stage_fast = OS.get_environment(STAGE_FAST_ENV) == "1"
	if _stage_fast:
		print("RunManager: fast stage gate (%.0fs, no boss)" % STAGE_FAST_GOAL)
	_bind_party.call_deferred()


func _bind_party() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		bind_player(node)
	if _party_health.is_empty():
		push_warning("RunManager: no player in scene; defeat detection disabled.")


## Pone a un raider bajo la detección de derrota. Pública (e idempotente)
## para que un cuerpo que se suma DESPUÉS — co-op que entra a mitad, un
## espacio reanimado que vuelve al grupo — se registre por el grupo
## "run_manager" en vez de quedar invisible para el chequeo de derrota.
func bind_player(node: Node) -> void:
	var health := Health.find_in(node)
	if health == null or _party_health.has(health):
		return
	_party_health.append(health)
	if not health.died.is_connected(_on_player_died):
		health.died.connect(_on_player_died)


## Solitario: una muerte termina la partida. Co-op: una muerte solo
## derriba a ese raider (se puede reanimar); la derrota llega cuando NADIE
## queda en pie, con todos los Health conectados muertos a la vez.
func _on_player_died() -> void:
	for health: Health in _party_health:
		if is_instance_valid(health) and not health.is_dead:
			return
	_end_run(goal_reached())


func _physics_process(_delta: float) -> void:
	# Modo de proceso pausable: mientras la UI de cartas pausa el árbol, este
	# chequeo se congela junto con RunState.stage_time.
	if not RunState.stage_cleared and _stage_gate_open():
		RunState.mark_stage_cleared(GameConfig.selected_map_id)
		get_tree().call_group("boss_ui", "announce_major", survival_text)
		# Log de una línea (convención de RunManager): el momento en que el
		# portal de salida puede aparecer, con las dos mitades de la puerta.
		print("Stage gate: time=%.1f boss=%s" % [
				RunState.stage_time, RunState.stage_boss_dead])


## Segundos que debe durar esta etapa. El interruptor del harness lo acorta
## para que un soak llegue a un cambio de etapa.
func _stage_goal() -> float:
	return STAGE_FAST_GOAL if _stage_fast else stage_goal


## La puerta de etapa: el reloj Y el jefe de etapa. El interruptor del
## harness quita la mitad del jefe, porque un soak no puede matar a un
## Ancestral dentro de su tiempo. Una arena sin escena de jefe cuenta como
## "jefe muerto", así un bioma sin jefe igual se puede terminar.
func _stage_gate_open() -> bool:
	if RunState.stage_time < _stage_goal():
		return false
	return _stage_fast or RunState.stage_boss_dead or not _stage_has_boss()


## True si el spawner de esta etapa trae algún jefe.
func _stage_has_boss() -> bool:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	return spawner != null and spawner.get("boss_scene") != null


## Nota de victoria: una partida cuenta como ganada si superó al menos UNA
## etapa. El logro es llegar a la salida de un mapa.
func goal_reached() -> bool:
	return RunState.stages_cleared_total > 0


## «Extraer» de la pausa: termina la partida por voluntad propia. Se
## califica como una muerte — victoria si se cumplió la meta, derrota si no —
## y se guarda en el registro meta igual (a diferencia de Salir al menú, que
## abandona la partida).
func extract_run() -> void:
	# Solo se loguea la extracción que de verdad terminó la partida: un
	# segundo toque (o uno en el frame en que una muerte ya la cerró) no debe
	# imprimir un segundo final, porque estos logs SON la interfaz de
	# verificación de los soaks.
	if _end_run(goal_reached()):
		print("Run extracted at %.1fs" % RunState.run_time)


## Termina la partida una vez. Devuelve false si ya había terminado (esta
## llamada no hizo nada), para que los llamadores logueen con verdad.
func _end_run(victory: bool) -> bool:
	if _run_over:
		return false
	_run_over = true
	set_physics_process(false)
	RunState.run_active = false
	# El spawner vive en la escena de la arena y no en RunSystems: se llega
	# por su grupo y se detiene explícitamente, así queda inerte aunque algo
	# despause el árbol sin recargar.
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner != null:
		spawner.set_physics_process(false)
	# Sfx suena en pausa, así que el zumbido de un santuario debe terminar
	# con la partida.
	Sfx.stop_all_loops()
	get_tree().paused = true
	# Log de una línea para que los soaks sin ventana confirmen el ciclo completo.
	print("Run ended: %s at %.1fs (level %d, %d kills)" % [
			"victory" if victory else "defeat",
			RunState.run_time, RunState.level, RunState.kills])
	print("Run stages: %d cleared, %d lap(s), %d map(s) visited" % [
			RunState.stages_cleared_total, RunState.laps_completed,
			RunState.visited_map_ids.size()])
	# Puntaje de la Cacería diaria: se guarda gane o pierda, el mejor por
	# fecha. Se acredita ANTES del registro meta a propósito: el registro es
	# el que juzga las misiones, y si no daily_1/daily_7 se evaluarían con la
	# cuenta de la partida anterior.
	if GameConfig.daily_mode:
		GameConfig.last_daily_score = GameConfig.daily_score(
				RunState.kills, RunState.level, RunState.run_time)
		SaveData.raise_to("daily_best_" + GameConfig.daily_date,
				GameConfig.last_daily_score)
		SaveData.bump("daily_runs")
	# Pasa la partida terminada al registro de progresión meta antes de abrir
	# la pantalla final: contadores de por vida, misiones completadas y el
	# guardado ocurren aquí, una vez por partida. La pantalla lee el
	# resultado de SaveData.last_*.
	SaveData.fold_run_results(victory, _party_character_ids(),
			RunState.visited_map_ids, RunState.cleared_map_ids,
			RunState.stages_cleared_total, RunState.laps_completed,
			RunState.level, RunState.kills, RunState.run_time)
	if GameConfig.daily_mode:
		print("Daily run scored: %d" % GameConfig.last_daily_score)
	print("Meta saved: %d quest(s) newly completed, %d shard(s) to claim" % [
			SaveData.last_new_quest_ids.size(), SaveData.last_reward_shards])
	run_ended.emit(victory)
	return true


## Cada raider que jugó esta partida, una entrada por espacio de co-op (en
## solitario, solo el elegido). El registro meta acredita runs_as_/wins_as_
## por raider, así que los espacios 1..3 tienen que nombrarse aquí.
func _party_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot: int in maxi(Coop.player_count, 1):
		ids.append(Coop.character_for_slot(slot))
	return ids
