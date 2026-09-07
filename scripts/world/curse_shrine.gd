class_name CurseShrine
extends ChargeShrine
## Demonic altar (iteration 41; keeps the Curse name): charges exactly like
## a charge altar — proximity, pause on leaving, sinks once spent — but its
## payoff is a PACT, not a blessing (iteration 47). Completing offers three
## pacts, each one a BENEFIT paired with a COST that the card spells out:
## a bigger boon, run points or a free chest, bought with permanent run
## difficulty, more elites, longer sky events, more sky events, or the
## disasters of a later wave. Demon Blood copies enlarge both halves of the
## bargain, bosses keep dropping an extra chest per use
## (BossBase reads RunState.demonic_uses) and difficulty XP flows.

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")

## Difficulty added by a pact whose cost is difficulty, as a percentage
## (the row's own amount); kept as an export so an arena can soften it.
@export var difficulty_per_use: float = 15.0
## Demon Blood: each copy held by the charger adds this fraction to the
## boon AND to the difficulty step (the bargain scales both ways).
@export var demon_blood_per_copy: float = 0.25
## Where the "free chest" benefit drops, in meters from the obelisk.
@export var chest_drop_distance: float = 2.4

## Pacts: each row is one card. `benefit` and `cost` are both {kind, ...}
## rows resolved by the two match statements below — a new pact is a new
## row, and a new KIND is one branch in each, never a special case per id.
## Benefit kinds: "boon" (a flat party-wide stat, ~2x an ALTAR_BOONS
## amount), "points" (run points to the raider who held the ring), "chest"
## (a free chest at the altar). Cost kinds write RunState knobs.
## `label` carries exactly the markers its kind fills (the chest benefit
## fills none).
const PACT_LIBRARY: Array[Dictionary] = [
	{
		"id": "pact_fury", "name": "Pacto de furia",
		"benefit": {"kind": "boon", "stat": "damage", "amount": 20.0,
			"label": "daño +%d%%"},
		"cost": {"kind": "difficulty", "amount": 15.0, "label": "dificultad +%d%%"},
	},
	{
		"id": "pact_rhythm", "name": "Pacto del pulso",
		"benefit": {"kind": "boon", "stat": "cooldown", "amount": 12.0,
			"label": "velocidad de ataque +%d%%"},
		"cost": {"kind": "elites", "amount": 6.0, "label": "prob. de shiny +%d%%"},
	},
	{
		"id": "pact_hide", "name": "Pacto de la coraza",
		"benefit": {"kind": "boon", "stat": "armor", "amount": 4.0,
			"label": "armadura +%d"},
		"cost": {"kind": "sky_duration", "amount": 40.0,
			"label": "las lunas duran %d%% más"},
	},
	{
		"id": "pact_flesh", "name": "Pacto de carne",
		"benefit": {"kind": "boon", "stat": "max_hp", "amount": 40.0,
			"label": "HP máx. +%d"},
		"cost": {"kind": "events", "amount": 10.0,
			"label": "prob. de luna +%d%%"},
	},
	{
		"id": "pact_swarm", "name": "Pacto del enjambre",
		"benefit": {"kind": "boon", "stat": "projectiles", "amount": 2.0,
			"label": "+%d proyectil(es)"},
		"cost": {"kind": "difficulty", "amount": 20.0, "label": "dificultad +%d%%"},
	},
	{
		"id": "pact_greed", "name": "Pacto de codicia",
		"benefit": {"kind": "points", "amount": 150.0, "label": "+%d pts"},
		"cost": {"kind": "elites", "amount": 8.0, "label": "prob. de shiny +%d%%"},
	},
	{
		"id": "pact_hoard", "name": "Pacto del arcón",
		"benefit": {"kind": "chest", "amount": 0.0, "label": "un cofre gratis aquí mismo"},
		"cost": {"kind": "difficulty", "amount": 25.0, "label": "dificultad +%d%%"},
	},
	{
		"id": "pact_omen", "name": "Pacto del augurio",
		"benefit": {"kind": "boon", "stat": "luck", "amount": 20.0,
			"label": "suerte +%d"},
		"cost": {"kind": "disasters", "amount": 15.0,
			"label": "prob. de desastre +%d%%"},
	},
]

## Card text: benefit first, cost underneath. Two lines, never one — a cost
## folded into the same sentence as its benefit is a cost nobody reads.
const PACT_TEXT: String = "Ganas: %s\nPagas: %s"


func _init() -> void:
	super()
	boon_scale = 1.6
	completed_text = "El obelisco bebe hondo: %s — la horda se pone más hambrienta"
	choice_title = "El obelisco ofrece un trato"
	choice_tag = "Pacto"


func _accent_color() -> Color:
	return Color(1.0, 0.3, 0.25)


func _demon_blood_in_ring() -> int:
	return best_item_count_in_range("demon_blood")


## Demon Blood enlarges both halves of the bargain (boon and difficulty),
## so both read it from here instead of from a mutated export.
func _blood_scale() -> float:
	return 1.0 + demon_blood_per_copy * float(_demon_blood_in_ring())


func _effective_boon_scale() -> float:
	return boon_scale * _blood_scale()


## Three distinct pacts, drawn from the library and priced with the
## charger's Master Keys and Demon Blood.
func _reward_options(keys: int) -> Array[Dictionary]:
	var pool := PACT_LIBRARY.duplicate()
	pool.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(ALTAR_CHOICE_COUNT, pool.size()):
		var pact: Dictionary = pool[i]
		options.append({
			"title": String(pact.name),
			"description": PACT_TEXT % [_benefit_text(pact.benefit, keys),
					_cost_text(pact.cost)],
			"color": _accent_color(),
			"pact": pact,
		})
	return options


## What one pact's benefit reads as on the card, at THIS altar's scaling.
func _benefit_text(benefit: Dictionary, keys: int) -> String:
	var label := String(benefit.label)
	if String(benefit.kind) == "chest":
		return label
	return label % roundi(_benefit_amount(benefit, keys))


## What one pact's cost reads as. Difficulty is the only cost Demon Blood
## enlarges (it is the half of the bargain the blood feeds), so it is the
## only one whose card number moves with the raider's bag.
func _cost_text(cost: Dictionary) -> String:
	return String(cost.label) % roundi(_cost_amount(cost))


## A benefit's size: stat boons ride the altar's boon scale and Master
## Keys like any other altar boon; points and chests are flat.
func _benefit_amount(benefit: Dictionary, keys: int) -> float:
	if String(benefit.kind) == "boon":
		return boon_amount(float(benefit.amount), keys)
	return float(benefit.amount)


func _cost_amount(cost: Dictionary) -> float:
	var amount := float(cost.amount)
	if String(cost.kind) == "difficulty":
		return amount * _blood_scale() * (difficulty_per_use / 15.0)
	return amount


## Pays the chosen pact: benefit first, then its cost. Returns the benefit
## text, which is what the banner and the `Altar charged:` log announce —
## the cost has its own logs below.
func _grant_choice(option: Dictionary, keys: int, recipient: Node) -> String:
	var pact: Dictionary = option.pact
	var benefit: Dictionary = pact.benefit
	var gained := _benefit_text(benefit, keys)
	_pay_benefit(benefit, keys, recipient)
	var difficulty_step := _pay_cost(pact.cost)
	RunState.demonic_uses += 1
	# One-line logs (RunManager convention) for headless soaks. The second
	# one is kept verbatim from iteration 41: a pact that costs something
	# other than difficulty simply reports a step of 0.
	print("Demonic pact: %s" % String(pact.id))
	print("Demonic altar used: difficulty +%d%% (total +%d%%)" % [
			roundi(difficulty_step * 100.0), roundi(RunState.difficulty_bonus * 100.0)])
	return gained


## One branch per benefit kind (project convention: a new kind is a branch,
## never a special case per pact id).
func _pay_benefit(benefit: Dictionary, keys: int, recipient: Node) -> void:
	match String(benefit.kind):
		"boon":
			grant_boon(String(benefit.stat), _benefit_amount(benefit, keys))
		"points":
			if recipient != null and is_instance_valid(recipient) \
					and recipient.has_method("add_points"):
				recipient.call("add_points", roundi(float(benefit.amount)))
		"chest":
			_drop_free_chest()
		_:
			push_warning("CurseShrine: unknown benefit kind '%s'" % benefit.kind)


## One branch per cost kind. Returns the DIFFICULTY fraction added (0 for
## every other kind), which is what the iteration-41 log reports.
func _pay_cost(cost: Dictionary) -> float:
	var fraction := _cost_amount(cost) / 100.0
	match String(cost.kind):
		"difficulty":
			RunState.add_difficulty(fraction, "altars")
			return fraction
		"elites":
			RunState.elite_chance_bonus += fraction
		"sky_duration":
			RunState.sky_duration_multiplier *= 1.0 + fraction
		"events":
			RunState.event_chance_bonus += fraction
		"disasters":
			# Stored, with no consumer until the disasters of part C — the
			# same forward hook RunState documents.
			RunState.disaster_chance_bonus += fraction
		_:
			push_warning("CurseShrine: unknown cost kind '%s'" % cost.kind)
	return 0.0


## The "free chest" benefit: a chest that costs nothing and rolls its
## rarity when it is opened, dropped beside the obelisk. Parented to the
## scene root, not to this altar — the obelisk sinks and frees itself a few
## seconds after paying, and it would take the prize down with it.
func _drop_free_chest() -> void:
	var parent := RunRoot.stage_parent(get_tree())
	if parent == null:
		parent = get_parent()
	if parent == null:
		return
	var chest := CHEST_SCENE.instantiate() as Chest
	if chest == null:
		push_warning("CurseShrine: Chest scene root is not a Chest.")
		return
	chest.free_open = true
	parent.add_child(chest)
	var angle := randf() * TAU
	chest.global_position = global_position \
			+ Vector3(cos(angle), 0.0, sin(angle)) * chest_drop_distance
