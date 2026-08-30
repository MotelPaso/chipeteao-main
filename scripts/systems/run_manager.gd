extends Node
## Owns the run-end flow (GDD 9.6): defeat when the player's Health dies,
## victory when RunState.run_time reaches run_duration (GDD 1: survive the
## clock or die). Ends the run exactly once — flags RunState inactive,
## stops the spawner, pauses the tree — then emits run_ended, which
## RunSystems.tscn wires to the RunEndScreen.

signal run_ended(victory: bool)

## Seconds the player must survive to win the run (default 15 minutes).
@export var run_duration: float = 900.0

var _run_over: bool = false


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("RunManager: no player in scene; defeat detection disabled.")
		return
	var health := Health.find_in(player)
	if health != null:
		health.died.connect(_end_run.bind(false))


func _physics_process(_delta: float) -> void:
	# Pausable process mode: while the upgrade-card UI has the tree paused
	# this check freezes along with RunState.run_time, so a victory can
	# never yank an open card pick away.
	if RunState.run_time >= run_duration:
		_end_run(true)


func _end_run(victory: bool) -> void:
	if _run_over:
		return
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
	# One-line log so headless soak runs can confirm the loop end-to-end
	# (grunts reached the player / the clock ran out).
	print("Run ended: %s at %.1fs (level %d, %d kills)" % [
			"victory" if victory else "defeat",
			RunState.run_time, RunState.level, RunState.kills])
	# Fold the finished run into the meta-progression ledger (GDD 8) before
	# the end screen opens: lifetime counters, quest completion marks, and
	# the save write all happen here, exactly once per run. The screen reads
	# the outcome from SaveData.last_* so the signal shape stays unchanged.
	var fold := SaveData.fold_run_results(victory, GameConfig.selected_character_id,
			GameConfig.selected_map_id, RunState.level, RunState.kills, RunState.run_time)
	print("Meta saved: %d quest(s) newly completed, %d shard(s) to claim" % [
			(fold.new_quest_ids as Array).size(), int(fold.reward_shards)])
	run_ended.emit(victory)
