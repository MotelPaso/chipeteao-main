class_name RouletteShrine
extends Interactable
## Roulette altar (iteration 41): a wheel of fortune that costs run points
## per spin and opens a menu (RouletteUi) where the raider spins for one of
## the outcomes below — from a Legendary item to a temporary curse. The
## wheel is reusable, but since iteration 46 every spin DOUBLES the price
## for the rest of the run (RunState.roulette_price_multiplier, run-wide
## like chest prices), so `price` is the base, never what you pay.

@export var price: int = 60

## Outcomes: {id, label, weight}. The id is the LOGIC key (apply_outcome
## matches on it, and the four item rows carry a rarity id in their
## suffix); the label is the only part the player reads.
const OUTCOMES: Array[Dictionary] = [
	{"id": "item_legendary", "label": "Objeto legendario", "weight": 3.0, "color": Color(1.0, 0.78, 0.2)},
	{"id": "item_epic", "label": "Objeto épico", "weight": 7.0, "color": Color(0.68, 0.32, 0.95)},
	{"id": "item_rare", "label": "Objeto raro", "weight": 14.0, "color": Color(0.3, 0.55, 1.0)},
	{"id": "item_common", "label": "Objeto común", "weight": 18.0, "color": Color(0.62, 0.65, 0.68)},
	{"id": "all_stats", "label": "Todas las stats +10%", "weight": 9.0, "color": Color(0.3, 0.82, 0.76)},
	{"id": "all_weapons", "label": "Todas las armas +1 nivel", "weight": 9.0, "color": Color(0.3, 0.82, 0.76)},
	{"id": "jackpot", "label": "Premio mayor: +120 pts", "weight": 6.0, "color": Color(1.0, 0.78, 0.2)},
	{"id": "heal", "label": "Curación total", "weight": 8.0, "color": Color(0.36, 0.8, 0.42)},
	{"id": "debuff", "label": "Maldición: lento y débil 20 s", "weight": 12.0, "color": Color(0.92, 0.28, 0.24)},
	{"id": "difficulty", "label": "Dificultad +15%", "weight": 8.0, "color": Color(0.92, 0.28, 0.24)},
	{"id": "enemy_frenzy", "label": "Enemigos más fuertes 30 s", "weight": 6.0, "color": Color(0.92, 0.28, 0.24)},
]

const RouletteUiScript := preload("res://scripts/ui/roulette_ui.gd")

var _wheel: MeshInstance3D = null
var _time: float = 0.0
var _ui: CanvasLayer = null


## Idle spin of the wheel prop, in radians per second.
const WHEEL_SPIN: float = 0.6


func _init() -> void:
	meta_stat_id = ""
	prompt_text = "[E] Girar la ruleta"


func _ready() -> void:
	super()
	_wheel = get_node_or_null("Visual/Wheel") as MeshInstance3D
	_refresh_prompt_text()


## The price grows with every spin this run, so the prompt is re-read
## rather than baked once at ready.
func current_price() -> int:
	return RunState.roulette_price(price)


func _refresh_prompt_text() -> void:
	set_prompt("[E] Girar la ruleta — %d pts" % current_price())


func _physics_process(delta: float) -> void:
	_time += delta
	if _wheel != null:
		_wheel.rotate_y(delta * WHEEL_SPIN)


func _interact(player: Node) -> void:
	var cost := current_price()
	if int(player.get("points")) < cost:
		Sfx.play(&"dodge")
		set_prompt("Girar cuesta %d pts (tienes %d)" % [cost, int(player.get("points"))])
		return
	if _ui != null and is_instance_valid(_ui):
		return
	_ui = RouletteUiScript.new()
	_ui.setup(self, player)
	# Under the CURRENT SCENE, never under /root: this layer holds the
	# whole tree paused, and a CanvasLayer parented to root survives
	# change_scene_to_file — leaving the next arena frozen behind an
	# orphan panel with nothing left to close it.
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(_ui)


## Pure weighted pick over OUTCOMES for a uniform roll in [0, 1).
static func outcome_for(roll: float) -> Dictionary:
	var total := 0.0
	for outcome: Dictionary in OUTCOMES:
		total += float(outcome.weight)
	var pick := roll * total
	for outcome: Dictionary in OUTCOMES:
		pick -= float(outcome.weight)
		if pick <= 0.0:
			return outcome
	return OUTCOMES[OUTCOMES.size() - 1]


## Charges the price and rolls; returns the outcome (empty if unaffordable).
func spin(player: Node) -> Dictionary:
	if not player.has_method("spend_points") or not bool(player.call("spend_points", current_price())):
		return {}
	# Charge first, THEN raise the price: the next spin (this altar or any
	# other) costs double, and the prompt re-reads it on the next refresh.
	RunState.register_roulette_spin()
	_refresh_prompt_text()
	SaveData.bump("shrines_used")
	SaveData.bump("roulette_spins")
	var outcome := outcome_for(randf())
	apply_outcome(String(outcome.id), player)
	print("Roulette spun: %s" % String(outcome.id))
	return outcome


## Applies one outcome to `player` (and the run, for the shared ones).
func apply_outcome(outcome_id: String, player: Node) -> void:
	var stats := PlayerStats.find_in(player)
	var bag := ItemBag.find_in(player)
	match outcome_id:
		"item_legendary", "item_epic", "item_rare", "item_common":
			# The id half is the RARITY KEY (ItemCatalog.roll_id and the
			# chest prices index on it, so it stays English); only the
			# banner goes through rarity_display.
			var rarity := outcome_id.trim_prefix("item_").capitalize()
			var item_id := ItemCatalog.roll_id(rarity)
			if bag != null and not item_id.is_empty():
				bag.add_item(item_id)
				get_tree().call_group("hud", "announce", "%s: %s" % [
						UpgradePool.rarity_display(rarity),
						String(ItemCatalog.by_id(item_id).display_name)])
		"all_stats":
			if stats != null:
				for stat: String in ["damage", "cooldown", "area", "move_speed", "max_hp"]:
					stats.add_altar_boon(stat, 10.0)
		"all_weapons":
			var mount := player.get_node_or_null("Weapons")
			if mount != null:
				for child: Node in mount.get_children():
					var weapon := child as WeaponBase
					if weapon != null:
						weapon.damage *= 1.15
						weapon.upgrade_level += 1
						EvolutionCatalog.try_advance_by_level(weapon, player)
		"jackpot":
			player.call("add_points", 120)
		"heal":
			var health := Health.find_in(player)
			if health != null:
				health.heal_full()
		"debuff":
			if stats != null:
				stats.add_timed_boon("move_speed", -30.0, 20.0)
				stats.add_timed_boon("damage", -25.0, 20.0)
		"difficulty":
			RunState.add_difficulty(0.15, "roulette")
		"enemy_frenzy":
			get_tree().call_group("enemy_spawner", "apply_temp_enemy_buff", 1.5, 30.0)
		_:
			push_warning("RouletteShrine: unknown outcome '%s'" % outcome_id)
