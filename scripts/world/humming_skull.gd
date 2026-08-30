class_name HummingSkull
extends SecretTrigger
## Ash Dunes secret (GDD 6): a bone pile whose skull carries a faint teal
## glow and hums. Press E inside the ring to LISTEN: a channel that only
## advances while the player stands still — any real movement (or stepping
## out of the ring) cancels it back to zero — and completes after
## listen_time seconds, unearthing the miniboss. The awaken/spawn flow
## lives on SecretTrigger.

## Seconds of stand-still listening needed to trigger.
@export var listen_time: float = 4.0
## Flat player speed above this counts as moving (cancels the channel).
@export var still_speed_limit: float = 0.2
## Movement inside this initial window is forgiven (progress just doesn't
## accrue), so pressing E while gliding to a stop isn't an instant cancel.
@export var start_grace: float = 0.4
@export var cancel_prompt: String = "[E] The hum shied away — hold still"
@export var hum_loop: StringName = &"shrine_channel"

## True while the listening channel runs (test hook).
var listening: bool = false
## Accrued stand-still seconds (resets on cancel; test hook).
var progress: float = 0.0

var _listen_age: float = 0.0
var _idle_prompt: String
var _glow_base_energy: float = 1.0
var _time: float = 0.0

@onready var _glow_light: OmniLight3D = $Visual/GlowLight


func _ready() -> void:
	super()
	_idle_prompt = prompt_text
	_glow_base_energy = _glow_light.light_energy


func _physics_process(delta: float) -> void:
	_time += delta
	# The glow breathes slowly while dormant and flutters during a listen.
	var rate := 9.0 if listening else 1.6
	_glow_light.light_energy = _glow_base_energy * (1.0 + 0.25 * sin(_time * rate))
	if not listening:
		return
	_listen_age += delta
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		_cancel_listen()
		return
	if Vector2(player.velocity.x, player.velocity.z).length() > still_speed_limit:
		if _listen_age > start_grace:
			_cancel_listen()
		return
	progress += delta
	set_prompt("Listening... %d%%" % roundi(clampf(progress / listen_time, 0.0, 1.0) * 100.0))
	if progress >= listen_time:
		_complete_listen()


func _interact(_player: Node) -> void:
	if listening:
		return
	listening = true
	progress = 0.0
	_listen_age = 0.0
	Sfx.play_loop(hum_loop)
	_emit_started()


func _on_range_exited() -> void:
	if listening:
		_cancel_listen()


## Moving (or leaving the ring) wipes the channel entirely — unlike the
## Charge Shrine there is no resume; listening restarts from silence.
func _cancel_listen() -> void:
	listening = false
	progress = 0.0
	Sfx.stop_loop(hum_loop)
	set_prompt(cancel_prompt)
	_emit_cancelled()


func _complete_listen() -> void:
	listening = false
	Sfx.stop_loop(hum_loop)
	set_prompt(_idle_prompt)
	set_physics_process(false)
	_awaken()


## The hum lives on the Sfx autoload (which outlives this scene), so a
## retry/quit mid-listen must silence it here.
func _exit_tree() -> void:
	if listening:
		Sfx.stop_loop(hum_loop)
