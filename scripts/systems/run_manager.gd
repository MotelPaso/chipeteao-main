extends Node
## Owns the run-end flow (GDD 9.6): defeat when the player's Health dies,
## victory when RunState.run_time reaches run_duration (GDD 1: survive the
## clock or die). Ends the run exactly once — flags RunState inactive,
## stops the spawner, pauses the tree — then emits run_ended, which
## Main.tscn wires to the RunEndScreen.

signal run_ended(victory: bool)

## Seconds the player must survive to win the run (default 15 minutes).
@export var run_duration: float = 900.0
## The spawner is stopped explicitly on run end so it stays inert even if
## something later unpauses the tree without reloading the scene.
@export var spawner_path: NodePath = ^"../EnemySpawner"

var _spawner: Node = null
var _run_over: bool = false


func _ready() -> void:
	_spawner = get_node_or_null(spawner_path)
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
	if _spawner != null:
		_spawner.set_physics_process(false)
	get_tree().paused = true
	# One-line log so headless soak runs can confirm the loop end-to-end
	# (grunts reached the player / the clock ran out).
	print("Run ended: %s at %.1fs (level %d, %d kills)" % [
			"victory" if victory else "defeat",
			RunState.run_time, RunState.level, RunState.kills])
	run_ended.emit(victory)
