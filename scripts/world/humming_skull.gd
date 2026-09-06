class_name HummingSkull
extends SecretTrigger
## Ash Dunes secret (GDD 6): a bone pile whose skull carries a faint teal
## glow and hums. Press E inside the ring to LISTEN: a channel that only
## advances while the player stands still — any real movement (or stepping
## out of the ring) cancels it back to zero — and completes after
## listen_time seconds, unearthing the miniboss. The awaken/spawn flow
## lives on SecretTrigger.

## Glow breathing rates: slow while dormant, fluttering during a listen.
const GLOW_IDLE_HZ: float = 1.6
const GLOW_LISTEN_HZ: float = 9.0
const GLOW_SWING: float = 0.25

## Seconds of stand-still listening needed to trigger.
@export var listen_time: float = 4.0
## Flat player speed above this counts as moving (cancels the channel).
@export var still_speed_limit: float = 0.2
## Movement inside this initial window is forgiven (progress just doesn't
## accrue), so pressing E while gliding to a stop isn't an instant cancel.
@export var start_grace: float = 0.4
@export var cancel_prompt: String = "[E] El zumbido se apartó — no te muevas"
## Shared with the charge altars, so it goes through the ref-counted
## _hold_loop/_drop_loop pair: whoever stops first must not silence the
## other emitters still holding it.
@export var hum_loop: StringName = &"shrine_channel"

## True while the listening channel runs (test hook).
var listening: bool = false
## Accrued stand-still seconds (resets on cancel; test hook).
var progress: float = 0.0

## The raider who pressed interact: the channel measures THEIR stillness.
var _listener: Node3D = null
var _listen_age: float = 0.0
var _idle_prompt: String
var _glow_base_energy: float = 1.0
var _time: float = 0.0

@onready var _glow_light: OmniLight3D = $Visual/GlowLight


## Prompt and banner defaults live here, next to meta_stat_id and
## complete_sound (Interactable's convention). The scene only overrides
## them when one placed instance has to say something different.
func _init() -> void:
	prompt_text = "[E] Escuchar el cráneo zumbante"
	awaken_text = "El zumbido era un cebo: ¡la arena vomita un cofre!"


func _ready() -> void:
	super()
	_idle_prompt = prompt_text
	_glow_base_energy = _glow_light.light_energy


func _physics_process(delta: float) -> void:
	_time += delta
	# The glow breathes slowly while dormant and flutters during a listen.
	var rate := GLOW_LISTEN_HZ if listening else GLOW_IDLE_HZ
	_glow_light.light_energy = _glow_base_energy * (1.0 + GLOW_SWING * sin(_time * rate))
	if not listening:
		return
	_listen_age += delta
	# The LISTENER's stillness, not the nearest body's: measuring the
	# closest raider made the secret impossible in co-op, because a
	# team-mate jogging past (without even entering the ring) cancelled it.
	if not is_instance_valid(_listener):
		_cancel_listen()
		return
	var player := _listener as CharacterBody3D
	if player == null or not player.is_in_group("player") \
			or not _players_in_range.has(player):
		_cancel_listen()
		return
	if Vector2(player.velocity.x, player.velocity.z).length() > still_speed_limit:
		if _listen_age > start_grace:
			_cancel_listen()
		return
	progress += delta
	set_prompt("Escuchando... %d%%" % roundi(clampf(progress / listen_time, 0.0, 1.0) * 100.0))
	if progress >= listen_time:
		_complete_listen()


func _interact(player: Node) -> void:
	if listening:
		return
	listening = true
	_listener = player as Node3D
	progress = 0.0
	_listen_age = 0.0
	_hold_loop(hum_loop)
	_emit_started()


func _on_range_exited() -> void:
	if listening:
		_cancel_listen()


## Moving (or leaving the ring) wipes the channel entirely — unlike the
## Charge Shrine there is no resume; listening restarts from silence.
func _cancel_listen() -> void:
	listening = false
	_listener = null
	progress = 0.0
	_drop_loop()
	set_prompt(cancel_prompt)
	_emit_cancelled()


func _complete_listen() -> void:
	listening = false
	_listener = null
	_drop_loop()
	set_prompt(_idle_prompt)
	set_physics_process(false)
	_awaken()
