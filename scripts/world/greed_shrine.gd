class_name GreedShrine
extends Interactable
## Greed Shrine (GDD 4): a skull-adorned altar that takes an HP gamble.
## Interacting pays hp_cost_fraction of CURRENT HP (via Health.pay — armor
## ignored, never lethal, at least min_hp_left stays) and rolls the payout:
## gem_chance -> a ring of high-value XP gems, card_chance -> a free
## rarity-floored card pick, remainder -> nothing but a flavor line.
## One use, then the altar dims. outcome_for() is a pure classifier so a
## test harness can drive the roll and prove the distribution.

@export_range(0.0, 1.0) var hp_cost_fraction: float = 0.25
## The payment can never drop the player below this much HP.
@export var min_hp_left: float = 1.0
@export_group("Payout")
@export_range(0.0, 1.0) var gem_chance: float = 0.6
@export_range(0.0, 1.0) var card_chance: float = 0.3
@export var gem_count: int = 12
@export var gem_value: int = 4
@export var xp_gem_scene: PackedScene
@export var card_title: String = "The altar yields a prize"
## Every rolled card rarity is floored to this tier ("Rare+" payout).
@export var card_min_rarity: String = "Rare"
@export var flavor_text: String = "The altar is pleased."


func _init() -> void:
	meta_stat_id = "shrines_used"


func _interact(player: Node) -> void:
	var health := Health.find_in(player)
	if health == null:
		return
	_emit_started()
	health.pay(health.current_hp * hp_cost_fraction, min_hp_left)
	consume()
	dim_visuals()
	_grant(outcome_for(randf()))
	_emit_completed()


## Pure payout classifier for a uniform [0,1) roll: "gems" | "card" |
## "nothing", split gem_chance / card_chance / remainder.
func outcome_for(roll: float) -> String:
	if roll < gem_chance:
		return "gems"
	if roll < gem_chance + card_chance:
		return "card"
	return "nothing"


func _grant(outcome: String) -> void:
	match outcome:
		"gems":
			_burst_gems()
		"card":
			get_tree().call_group(
					"upgrade_ui", "open_bonus_pick", card_title, 0.0, card_min_rarity)
		_:
			get_tree().call_group("hud", "announce", flavor_text)


## Ring of high-value gems around the altar; the magnet does the rest.
func _burst_gems() -> void:
	if xp_gem_scene == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in gem_count:
		var drop := xp_gem_scene.instantiate()
		var gem := drop as XpGem
		if gem == null:
			drop.free()
			return
		gem.xp_value = gem_value
		scene_root.add_child(gem)
		var angle := TAU * float(i) / float(gem_count)
		gem.global_position = global_position + Vector3.UP * 0.8 \
				+ Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.1, 1.9)
