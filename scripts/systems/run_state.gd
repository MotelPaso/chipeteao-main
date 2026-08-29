extends Node
## Autoload "RunState": the current run's XP, level, kills, and elapsed
## time, plus run-scoped stat multipliers that upgrades modify and other
## systems read (loose coupling through this singleton instead of node
## references). Default process_mode is pausable, so run_time freezes
## while the upgrade-card UI has the tree paused.

signal xp_changed(current_xp: int, xp_to_next: int)
signal leveled_up(new_level: int)

var xp: int = 0
var level: int = 1
var xp_to_next: int = 8
var kills: int = 0
var run_time: float = 0.0
## Multiplies every gem's magnet radius; raised by pickup-radius upgrades.
var pickup_radius_multiplier: float = 1.0


func _ready() -> void:
	reset()


func _physics_process(delta: float) -> void:
	run_time += delta


## Call at the start of a new run.
func reset() -> void:
	xp = 0
	level = 1
	kills = 0
	run_time = 0.0
	pickup_radius_multiplier = 1.0
	xp_to_next = _xp_required(level)
	xp_changed.emit(xp, xp_to_next)


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	# Loop: a single big pickup can grant several levels; one leveled_up
	# fires per level so the card UI can queue extra picks.
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = _xp_required(level)
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next)


func add_kill() -> void:
	kills += 1


func _xp_required(for_level: int) -> int:
	return 5 + for_level * 3
