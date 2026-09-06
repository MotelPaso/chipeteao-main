class_name Chest
extends Interactable
## Treasure chest (iteration 40 economy): a rarity-tiered lockbox that
## costs run points to open and pays out ONE ItemCatalog item of its own
## rarity (never cards, never weapons). Prices come from RunState
## (base per rarity x a global multiplier that grows with every chest
## anyone opens), so early chests are cheap and each one taxes the rest.
## The rarity is either fixed on the instance or rolled at ready with the
## card-rarity weights tilted by luck_bonus (supply chests) and floored by
## min_rarity. The band/lock/trim glow in the rarity color so a
## Legendary chest reads from across the field. One use; the chest stays
## open afterwards.

## Fixed rarity name ("" = rolled at ready).
@export var rarity: String = ""
## Rarity-tilt luck for the ready-time roll (WorldDirector supply chests).
@export var luck_bonus: float = 0.0
## Rolled rarities are floored to this tier ("" = no floor).
@export var min_rarity: String = ""
## Seconds the lid swing takes; the item lands once it finishes.
@export var open_duration: float = 0.45
## Lid pivot X rotation when fully open (hinged at the back edge).
@export var lid_open_angle: float = -1.75

## Lid-swing choreography: the chest hops this high, spending this share
## of open_duration going up and the rest bouncing back down.
const OPEN_HOP_HEIGHT: float = 0.3
const OPEN_HOP_UP_SHARE: float = 0.4

@onready var _lid_pivot: Node3D = $Visual/LidPivot

## The raider who opened this chest (co-op: the loot lands on THEM).
var _opener: Node = null


func _init() -> void:
	meta_stat_id = "chests_opened"
	complete_sound = &"chest_open"
	prompt_text = "[E] Abrir el cofre"


func _ready() -> void:
	super()
	# A fixed rarity needs no roll; `rarity` is the single source every
	# reader (price, tint, prompt, loot roll) already goes through, so the
	# rolled tier is stored back into it and nothing else is kept.
	if rarity.is_empty():
		var floor_index := UpgradePool.rarity_index(min_rarity)
		# Luck tilts the rarity of an item the same way it tilts a card —
		# that is what Tome of Fortune, Lucky Coin and Gilded Whisker
		# promise. A chest seals its rarity when it appears, so the party's
		# luck AT THAT MOMENT is what counts: relic luck for the chests an
		# arena ships with, the run's accumulated luck for the supply
		# chests the WorldDirector drops mid-run.
		var row := UpgradePool.roll_rarity(luck_bonus + _party_luck(), floor_index)
		rarity = String(row.name)
	_tint_by_rarity()
	_refresh_price_prompt()


## Best luck in the party at roll time (the party shares one field of
## chests, so the luckiest raider sets the tilt).
func _party_luck() -> float:
	var best := 0.0
	for node: Node in get_tree().get_nodes_in_group("player"):
		var stats := PlayerStats.find_in(node)
		if stats != null:
			best = maxf(best, stats.luck)
	return best


func rarity_name() -> String:
	return rarity


func price() -> int:
	return RunState.chest_price(rarity)


func _physics_process(_delta: float) -> void:
	# Prices move with every chest opened anywhere, and the raider's
	# points move with every kill: keep the prompt honest while in range.
	if available and player_in_range:
		_refresh_price_prompt()


func _refresh_price_prompt() -> void:
	var cost := price()
	var purse := _points_of_nearest()
	var shown := UpgradePool.rarity_display(rarity)
	if purse >= cost:
		set_prompt("[E] Abrir cofre %s — %d pts" % [shown, cost])
	else:
		set_prompt("Cofre %s — %d pts (tienes %d)" % [shown, cost, purse])


## Point balance of the raider standing CLOSEST to the chest — the one
## about to press. The prompt used to quote the richest body in the ring
## while _interact charged whoever actually pressed, so in co-op it
## promised an open to a raider who could not pay for it. Downed bodies
## are skipped: they cannot press anything.
func _points_of_nearest() -> int:
	var body := nearest_live_player()
	if body == null:
		return 0
	var purse: Variant = body.get("points")
	return int(purse) if purse != null else 0


func _interact(player: Node) -> void:
	var cost := price()
	if not player.has_method("spend_points") or not bool(player.call("spend_points", cost)):
		# Can't afford: a dull thunk and the prompt already says why.
		Sfx.play(&"dodge")
		return
	_opener = player
	RunState.register_chest_opened()
	_emit_started()
	consume()
	var rest_y := position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_lid_pivot, "rotation:x", lid_open_angle, open_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", rest_y + OPEN_HOP_HEIGHT,
			open_duration * OPEN_HOP_UP_SHARE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "position:y", rest_y,
			open_duration * (1.0 - OPEN_HOP_UP_SHARE)) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_pop_reward)


func _pop_reward() -> void:
	# The lid swing runs for open_duration before the loot lands: by then
	# the opener may be gone (a co-op slot dropped, a respawn by
	# reinstantiation). ItemBag.find_in only guards against null, and a
	# freed Object is not null.
	if _opener == null or not is_instance_valid(_opener):
		_emit_completed()
		return
	var item_id := ItemCatalog.roll_id(rarity)
	var bag := ItemBag.find_in(_opener)
	if item_id.is_empty() or bag == null:
		push_warning("Chest: no item to grant (rarity %s)" % rarity)
		_emit_completed()
		return
	bag.add_item(item_id)
	var row := ItemCatalog.by_id(item_id)
	get_tree().call_group("boss_ui", "announce", "Cofre %s: %s — %s" % [
			UpgradePool.rarity_display(rarity), String(row.display_name),
			String(row.description)])
	# One-line log (RunManager convention) for headless soaks.
	print("Chest opened: %s -> %s (next prices x%.2f)" % [
			rarity, item_id, RunState.chest_price_multiplier])
	_emit_completed()


## Band, lock and lid trim take the rarity color (emissive so it reads at
## night); the wood stays wood.
func _tint_by_rarity() -> void:
	var color := ItemCatalog.rarity_color(rarity)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.9 if rarity != "Common" else 0.3
	for path: String in ["Visual/Band", "Visual/Lock", "Visual/LidPivot/LidTrim"]:
		var mesh_instance := get_node_or_null(path) as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = material
	if rarity == "Epic" or rarity == "Legendary":
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.6
		light.omni_range = 5.0
		light.position = Vector3.UP * 1.2
		add_child(light)
