class_name GreedShrine
extends Interactable
## Greed Shrine (GDD 4): a skull-adorned altar that takes an HP gamble.
## Interacting pays hp_cost_fraction of MAX HP (via Health.pay — armor
## ignored, never lethal, at least min_hp_left stays) and rolls the payout:
## gem_chance -> a ring of high-value XP gems, card_chance -> a free
## rarity-floored card pick, remainder -> nothing but a flavor line.
## The price is charged on the maximum, not on what is left in the bar:
## a fraction of CURRENT HP tends to zero as the bar empties, so walking
## in at 1 HP used to buy a Rare+ card for nothing and made "arrive hurt"
## the optimal play — the exact opposite of a gamble.
## One use, then the altar dims. outcome_for() is a pure classifier so a
## test harness can drive the roll and prove the distribution.

@export_range(0.0, 1.0) var hp_cost_fraction: float = 0.25
## The payment can never drop the player below this much HP.
@export var min_hp_left: float = 1.0
## Shown when the raider cannot cover the full toll.
@export var too_hurt_text: String = "No te alcanza la vida."
@export_group("Payout")
@export_range(0.0, 1.0) var gem_chance: float = 0.6
@export_range(0.0, 1.0) var card_chance: float = 0.3
@export var gem_count: int = 12
@export var gem_value: int = 4
@export var xp_gem_scene: PackedScene
@export var card_title: String = "El altar entrega un premio"
## Every rolled card rarity is floored to this tier ("Rare+" payout).
@export var card_min_rarity: String = "Rare"
@export var flavor_text: String = "El altar queda complacido."


## The offer line, kept so a refused toll can be re-armed (same pattern as
## the Humming Skull's cancel prompt).
var _idle_prompt: String


func _init() -> void:
	meta_stat_id = "shrines_used"
	prompt_text = "[E] Ofrendar sangre"


func _ready() -> void:
	super()
	_idle_prompt = prompt_text


## The altar stays unspent after a refused toll, so walking back in with
## a fuller bar has to show the offer again.
func _on_range_entered() -> void:
	if available:
		set_prompt(_idle_prompt)


func _interact(player: Node) -> void:
	var health := Health.find_in(player)
	if health == null:
		return
	var toll := health.max_hp * hp_cost_fraction
	# Health.pay clips at min_hp_left instead of killing, so a short pay
	# is exactly the "too hurt to bleed" case: refuse it and leave the
	# altar unspent rather than handing out a free Rare+ card.
	if health.current_hp - min_hp_left < toll:
		Sfx.play(&"dodge")
		set_prompt(too_hurt_text)
		return
	_emit_started()
	health.pay(toll, min_hp_left)
	consume()
	dim_visuals()
	var outcome := outcome_for(randf())
	_grant(outcome, player)
	# One-line log (shrine convention: "Altar charged:", "Spring used:"…)
	# so headless soaks can see this altar resolve at all.
	print("Greed shrine: paid %.0f HP -> %s" % [toll, outcome])
	_emit_completed()


## Pure payout classifier for a uniform [0,1) roll: "gems" | "card" |
## "nothing", split gem_chance / card_chance / remainder.
func outcome_for(roll: float) -> String:
	if roll < gem_chance:
		return "gems"
	if roll < gem_chance + card_chance:
		return "card"
	return "nothing"


func _grant(outcome: String, player: Node) -> void:
	match outcome:
		"gems":
			_burst_gems()
		"card":
			# The card goes to the raider who bled for it: without a
			# recipient the picker rotates round-robin through the party
			# and the prize lands on whoever happens to be next.
			get_tree().call_group(
					"upgrade_ui", "open_bonus_pick", card_title, 0.0, card_min_rarity, player)
		_:
			get_tree().call_group("hud", "announce", flavor_text)


## Ring of high-value gems around the altar; the magnet does the rest.
func _burst_gems() -> void:
	if xp_gem_scene == null:
		return
	var placed := 0
	for i in gem_count:
		var gem := Pools.acquire_scene(xp_gem_scene) as XpGem
		# One gem the pool could not hand over is not a reason to swallow
		# the other eleven the raider just paid blood for.
		if gem == null:
			continue
		gem.xp_value = gem_value
		var angle := TAU * float(i) / float(gem_count)
		gem.global_position = global_position + Vector3.UP * 0.8 \
				+ Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.1, 1.9)
		placed += 1
	if placed == 0:
		push_warning("GreedShrine: gem pool gave nothing; paying the flavor line instead")
		get_tree().call_group("hud", "announce", flavor_text)
