class_name SpringShrine
extends Interactable
## Spring altar (iteration 41): a pool of clear water that, for a FIXED
## price in run points, heals the raider to full and grants a timed
## power-up (PlayerStats.add_timed_boon). Vanishes after one use. The
## WorldDirector spawns springs now and then; they also time out.

@export var price: int = 40
@export var powerup_duration: float = 30.0
## {stat, amount} boons active for powerup_duration seconds.
@export var powerup_boons: Array[Dictionary] = [
	{"stat": "damage", "amount": 30.0},
	{"stat": "move_speed", "amount": 15.0},
	{"stat": "cooldown", "amount": 15.0},
]
## Seconds an unused spring waits before drying up (0 = forever).
@export var idle_lifetime: float = 0.0

## Surface ripple: the water plate breathes on two slightly detuned
## frequencies so the pool never looks like it is pulsing on a metronome.
const RIPPLE_X_HZ: float = 1.7
const RIPPLE_Z_HZ: float = 1.3
const RIPPLE_AMOUNT: float = 0.03

var _idle_left: float = 0.0
var _time: float = 0.0
var _water: MeshInstance3D = null
## Set by _dry_up: without it a second exit path (timeout racing a use)
## would stack two scale tweens and queue_free the node twice.
var _drying: bool = false


func _init() -> void:
	meta_stat_id = "shrines_used"
	marker_kind = &"spring"
	complete_sound = &"heal"


func _ready() -> void:
	super()
	_water = get_node_or_null("Visual/Water") as MeshInstance3D
	_idle_left = idle_lifetime
	_refresh_price_prompt()


func _physics_process(delta: float) -> void:
	_time += delta
	if _water != null:
		_water.scale = Vector3(
				1.0 + sin(_time * RIPPLE_X_HZ) * RIPPLE_AMOUNT, 1.0,
				1.0 + cos(_time * RIPPLE_Z_HZ) * RIPPLE_AMOUNT)
	if available and player_in_range:
		_refresh_price_prompt()
	if idle_lifetime > 0.0 and available and not player_in_range:
		_idle_left -= delta
		if _idle_left <= 0.0:
			_dry_up()


func _refresh_price_prompt() -> void:
	set_prompt("[E] Beber — %d pts (cura + power-up)" % price)


func _interact(player: Node) -> void:
	if not player.has_method("spend_points") or not bool(player.call("spend_points", price)):
		Sfx.play(&"dodge")
		return
	_emit_started()
	consume()
	var health := Health.find_in(player)
	if health != null:
		health.heal_full()
	var stats := PlayerStats.find_in(player)
	if stats != null:
		for boon: Dictionary in powerup_boons:
			stats.add_timed_boon(String(boon.stat), float(boon.amount), powerup_duration)
	get_tree().call_group("hud", "announce",
			"El manantial te restaura — potenciado por %d s" % roundi(powerup_duration))
	print("Spring used: heal + %d s power-up" % roundi(powerup_duration))
	_emit_completed()
	_dry_up()


## Sink-and-free exit, shared by "used up" and "timed out". Re-entrant on
## purpose: the two paths can race.
func _dry_up() -> void:
	if _drying:
		return
	_drying = true
	available = false
	_refresh_prompt()
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
