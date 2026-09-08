class_name SpringShrine
extends Interactable
## Spring altar (iteration 41, reworked in 53): a pool of clear water
## that, for a FIXED price in run points, heals the raider to full and
## hands them ONE RANDOM POWER-UP. Vanishes after one use.
##
## It no longer rolls its own little bundle of boons: since iteration 53
## there is a power-up roster, and a spring that granted +30% damage while
## a Furia pickup granted +100% would have been two systems for one idea.
## The star is excluded — it is found roaming, never bought.
##
## It never times out, and only ONE is alive at a time (the WorldDirector
## weights its event row to zero while group `springs` is occupied): a
## spring the party never walked to is a promise, not litter.

@export var price: int = 40

## Surface ripple: the water plate breathes on two slightly detuned
## frequencies so the pool never looks like it is pulsing on a metronome.
const RIPPLE_X_HZ: float = 1.7
const RIPPLE_Z_HZ: float = 1.3
const RIPPLE_AMOUNT: float = 0.03

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
	# The director counts live springs through this group to keep exactly
	# one on the field; RunRoot frees them with the rest of the stage.
	add_to_group(&"springs")
	_water = get_node_or_null("Visual/Water") as MeshInstance3D
	_refresh_price_prompt()


func _physics_process(delta: float) -> void:
	_time += delta
	if _water != null:
		_water.scale = Vector3(
				1.0 + sin(_time * RIPPLE_X_HZ) * RIPPLE_AMOUNT, 1.0,
				1.0 + cos(_time * RIPPLE_Z_HZ) * RIPPLE_AMOUNT)
	if available and player_in_range:
		_refresh_price_prompt()


func _refresh_price_prompt() -> void:
	set_prompt("[E] Beber — %d pts (cura + power-up al azar)" % price)


func _interact(player: Node) -> void:
	if not player.has_method("spend_points") or not bool(player.call("spend_points", price)):
		Sfx.play(&"dodge")
		return
	_emit_started()
	consume()
	var health := Health.find_in(player)
	if health != null:
		health.heal_full()
	# One random power-up, never the star: PowerUps owns the toast, the
	# announce and the "Power-up picked:" line, so the spring says only
	# what the spring does.
	var powerup_id := PowerUpCatalog.roll_id(true)
	var powerups := PowerUps.find_in(player)
	if powerups != null:
		powerups.apply(powerup_id)
	get_tree().call_group("hud", "announce", "El manantial te restaura y te potencia")
	print("Spring used: heal + %s" % powerup_id)
	_emit_completed()
	_dry_up()


## Sink-and-free exit. Only one path reaches it now that springs never
## time out, but the guard stays: two raiders drinking on the same frame
## would otherwise stack two tweens and queue_free the node twice.
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
