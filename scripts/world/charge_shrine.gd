class_name ChargeShrine
extends Interactable
## Charge Shrine (GDD 4): press E inside the ring to channel the monolith
## for channel_time seconds while it periodically calls a spawn surge down
## on the spot (pressure). A growing floor disc plus a percent prompt show
## progress; stepping out of the ring cancels but KEEPS the progress, so a
## later attempt resumes where it stopped. Completing the channel spends
## the shrine and opens a free upgrade-card pick at luck-boosted rarity
## (UpgradeCardUI via the "upgrade_ui" group).

## Seconds of total in-ring channel time needed to complete.
@export var channel_time: float = 8.0
## Temporary luck points added to the reward roll's rarity tilt.
@export var reward_luck_bonus: float = 60.0
@export var reward_title: String = "Shrine charged — choose your boon"
@export_group("Spawn Surge")
## Seconds between surge bursts while channeling.
@export var surge_interval: float = 2.0
## Enemies per surge burst (spawner-side radii decide where they land).
@export var surge_count: int = 4

@onready var _crystal: MeshInstance3D = $Visual/Crystal
@onready var _progress_disc: MeshInstance3D = $Visual/ProgressDisc
@onready var _crystal_rest_y: float = _crystal.position.y

var channeling: bool = false
var progress: float = 0.0
var _surge_timer: float = 0.0
var _time: float = 0.0


func _init() -> void:
	meta_stat_id = "shrines_used"


func _physics_process(delta: float) -> void:
	_time += delta
	# Idle motion: the crystal slowly spins and bobs; channeling adds a
	# fast pulse so the shrine visibly "drinks" the channel.
	_crystal.rotate_y(delta * 1.4)
	_crystal.position.y = _crystal_rest_y + sin(_time * 2.1) * 0.12
	if not channeling:
		_crystal.scale = Vector3.ONE
		return
	_crystal.scale = Vector3.ONE * (1.0 + 0.12 * sin(_time * 9.0))
	progress += delta
	_surge_timer -= delta
	if _surge_timer <= 0.0:
		_surge_timer = surge_interval
		get_tree().call_group(
				"enemy_spawner", "spawn_pressure_burst", global_position, surge_count)
	_progress_disc.visible = true
	var fraction := clampf(progress / channel_time, 0.001, 1.0)
	_progress_disc.scale = Vector3(fraction, 1.0, fraction)
	set_prompt("Channeling... %d%%" % roundi(fraction * 100.0))
	if progress >= channel_time:
		_complete()


func _interact(_player: Node) -> void:
	if channeling:
		return
	channeling = true
	_surge_timer = 0.0  # first surge lands immediately: pressure from second one
	Sfx.play_loop(&"shrine_channel")
	_emit_started()


func _on_range_exited() -> void:
	if not channeling:
		return
	channeling = false
	Sfx.stop_loop(&"shrine_channel")
	set_prompt("[E] Resume channel (%d%%)" % roundi(progress / channel_time * 100.0))
	_emit_cancelled()


## The hum lives on the Sfx autoload (which outlives this scene), so a
## retry/quit mid-channel must silence it here.
func _exit_tree() -> void:
	if channeling:
		Sfx.stop_loop(&"shrine_channel")


func _complete() -> void:
	channeling = false
	Sfx.stop_loop(&"shrine_channel")
	progress = channel_time
	consume()
	set_physics_process(false)
	_crystal.scale = Vector3.ONE
	_progress_disc.visible = false
	dim_visuals()
	get_tree().call_group("upgrade_ui", "open_bonus_pick", reward_title, reward_luck_bonus, "")
	_emit_completed()
