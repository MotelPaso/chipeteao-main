extends Node
## Owns the run-end flow and the STAGE GATE. The run has no clock limit:
## it keeps going until the party is wiped or the player extracts from the
## pause menu (extract_run). What grades it is stages: a stage is CLEARED
## when its own clock passes stage_goal AND its boss is dead, which opens
## the exit portal and starts the pseudo-infinite ramp. Any end (death or
## extraction) with at least one stage cleared folds as a victory, before
## it folds as a defeat. Ends the run exactly once — flags RunState inactive,
## stops the spawner, pauses the tree — then emits run_ended, which
## RunSystems.tscn wires to the RunEndScreen.

signal run_ended(victory: bool)

## Seconds a STAGE has to last before its gate can open. Measured on
## RunState.stage_time, so every map of a run gets its own full stretch
## instead of the second one inheriting a clock that already ran out.
@export var stage_goal: float = 900.0

## Harness switch: BONK_STAGE_FAST=1 clears a stage after STAGE_FAST_GOAL
## seconds and with no boss requirement, so one 240 s soak can cross two
## stages and exercise the swap. Test-only — nothing in the game sets it.
const STAGE_FAST_ENV: String = "BONK_STAGE_FAST"
const STAGE_FAST_GOAL: float = 60.0
## Banner for the moment a stage is cleared. NO format markers: the number
## it used to carry was the survival goal in minutes, and the gate is no
## longer about a number the player is counting down — it is about the
## door that just opened (GLOSARIO rule 8 allows dropping markers when the
## call site stops formatting the string, which it does).
@export var survival_text: String = "¡Etapa superada! Se abrió el portal — quédate cuanto quieras"

var _run_over: bool = false
## True while BONK_STAGE_FAST is set (read once, at ready).
var _stage_fast: bool = false

## Every party member's Health, bound one frame after ready (co-op spawns
## the extra bodies in RunSystems._ready, which runs after this child's).
var _party_health: Array[Health] = []


func _ready() -> void:
	# The pause menu reaches back through this group to extract.
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


## Puts one raider under defeat detection. Public (and idempotent) so a
## body that joins the party AFTER this bind — drop-in co-op, a revived
## slot re-entering the group — can be registered through the
## "run_manager" group instead of being invisible to the wipe check.
func bind_player(node: Node) -> void:
	var health := Health.find_in(node)
	if health == null or _party_health.has(health):
		return
	_party_health.append(health)
	if not health.died.is_connected(_on_player_died):
		health.died.connect(_on_player_died)


## Solo: one death ends the run (unchanged). Co-op: a death only downs
## that raider (revivable); defeat lands when NOBODY is left standing —
## every bound Health dead at once.
func _on_player_died() -> void:
	for health: Health in _party_health:
		if is_instance_valid(health) and not health.is_dead:
			return
	_end_run(goal_reached())


func _physics_process(_delta: float) -> void:
	# Pausable process mode: while the upgrade-card UI has the tree paused
	# this check freezes along with RunState.stage_time.
	if not RunState.stage_cleared and _stage_gate_open():
		RunState.mark_stage_cleared(GameConfig.selected_map_id)
		get_tree().call_group("boss_ui", "announce_major", survival_text)
		# One-line log (RunManager convention): the moment the exit portal
		# is allowed to appear, with the two halves of the gate spelled out.
		print("Stage gate: time=%.1f boss=%s" % [
				RunState.stage_time, RunState.stage_boss_dead])


## Seconds this stage has to last. The harness switch shortens it so a
## soak can reach a stage change.
func _stage_goal() -> float:
	return STAGE_FAST_GOAL if _stage_fast else stage_goal


## The stage gate: the clock AND the stage boss. The harness switch drops
## the boss half, because a soak cannot be asked to kill an Elder inside
## its budget. An arena with no boss scene counts as "boss dead", so a
## future biome without one is still finishable.
func _stage_gate_open() -> bool:
	if RunState.stage_time < _stage_goal():
		return false
	return _stage_fast or RunState.stage_boss_dead or not _stage_has_boss()


## True when this stage's spawner ships a boss at all.
func _stage_has_boss() -> bool:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	return spawner != null and spawner.get("boss_scene") != null


## Victory grading: a run counts as won once it cleared at least ONE
## stage. Reaching a map's exit is the achievement now, not surviving a
## fixed number of minutes in whichever map you happened to pick.
func goal_reached() -> bool:
	return RunState.stages_cleared_total > 0


## Pause-menu "Extract": ends the run voluntarily. Graded like a death —
## victory if the goal was reached, defeat otherwise — and folded into the
## meta save either way (unlike Quit to Menu, which abandons the run).
func extract_run() -> void:
	# Only log the extraction that actually ended the run: a second press
	# (or one landing on the frame a death already closed the run) must not
	# print a second ending, since these one-line logs ARE the soaks'
	# verification interface.
	if _end_run(goal_reached()):
		print("Run extracted at %.1fs" % RunState.run_time)


## Ends the run once. Returns false when it was already over (this call
## did nothing), so callers can keep their logging honest.
func _end_run(victory: bool) -> bool:
	if _run_over:
		return false
	_run_over = true
	set_physics_process(false)
	RunState.run_active = false
	# The spawner lives in the arena scene, not in RunSystems, so it is
	# reached through its group and stopped explicitly — it stays inert
	# even if something later unpauses the tree without reloading.
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner != null:
		spawner.set_physics_process(false)
	# Sfx plays through pause, so any shrine-channel hum must end with the run.
	Sfx.stop_all_loops()
	get_tree().paused = true
	# One-line log so headless soak runs can confirm the loop end-to-end.
	print("Run ended: %s at %.1fs (level %d, %d kills)" % [
			"victory" if victory else "defeat",
			RunState.run_time, RunState.level, RunState.kills])
	print("Run stages: %d cleared, %d lap(s), %d map(s) visited" % [
			RunState.stages_cleared_total, RunState.laps_completed,
			RunState.visited_map_ids.size()])
	# Daily Hunt score (iteration 36): recorded win or lose, best-per-date.
	# Credited BEFORE the fold on purpose — the fold is what judges the
	# quests, so daily_1/daily_7 would otherwise always be evaluated with
	# the previous run's count and complete one run late.
	if GameConfig.daily_mode:
		GameConfig.last_daily_score = GameConfig.daily_score(
				RunState.kills, RunState.level, RunState.run_time)
		SaveData.raise_to("daily_best_" + GameConfig.daily_date,
				GameConfig.last_daily_score)
		SaveData.bump("daily_runs")
	# Fold the finished run into the meta-progression ledger (GDD 8) before
	# the end screen opens: lifetime counters, quest completion marks, and
	# the save write all happen here, exactly once per run. The screen reads
	# the outcome from SaveData.last_* so the signal shape stays unchanged.
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


## Every raider that played this run, one entry per co-op slot (solo is
## just the selected raider). The meta ledger credits runs_as_/wins_as_ per
## raider, so slots 1..3 have to be named here or they play for free.
func _party_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot: int in maxi(Coop.player_count, 1):
		ids.append(Coop.character_for_slot(slot))
	return ids
