class_name Chest
extends Interactable
## Treasure chest (iteration 40 economy, iteration 47 free mode): a lockbox
## that pays out ONE ItemCatalog item (never cards, never weapons).
##
## PAID chests seal their rarity when they appear: it is rolled at _ready
## with the card-rarity weights tilted by luck_bonus and floored by
## min_rarity, the band/lock/trim glow in that rarity color so a Legendary
## chest reads from across the field, and the price comes from RunState
## (base per rarity x a global multiplier that grows with every chest
## anyone opens). Each one taxes the rest.
##
## FREE chests (iteration 47: every boss and shiny drop, a share of the
## run-start chests, the demonic "free chest" pact) cost nothing, do NOT
## inflate the paid ones, and roll their rarity WHEN OPENED, with the
## opener's luck — so any tier is possible and luck actually tilts it.
## Having no sealed rarity, they carry their own white-gold tint instead
## of a rarity color, which is what makes "gratis" read at a distance.
##
## One use. Since iteration 47 EVERY chest sinks and frees itself once it
## has paid out, instead of leaving an open box on the field forever.

## Free mode: no price, no price inflation, rarity rolled at open time.
## Named free_open, not `free`: `free` is Object.free() and shadowing it
## with a property is how a node stops being able to delete itself.
@export var free_open: bool = false
## Fixed rarity name ("" = rolled at ready, or at open time when free).
@export var rarity: String = ""
## Rarity-tilt luck for the ready-time roll (WorldDirector supply chests).
@export var luck_bonus: float = 0.0
## Rolled rarities are floored to this tier ("" = no floor).
@export var min_rarity: String = ""
## Seconds the lid swing takes; the item lands once it finishes.
@export var open_duration: float = 0.45
## Lid pivot X rotation when fully open (hinged at the back edge).
@export var lid_open_angle: float = -1.75
## Seconds a paid-out chest stays on screen before sinking away.
@export var reward_linger: float = 1.4

## Lid-swing choreography: the chest hops this high, spending this share
## of open_duration going up and the rest bouncing back down.
const OPEN_HOP_HEIGHT: float = 0.3
const OPEN_HOP_UP_SHARE: float = 0.4
## Sink-and-shrink exit, shared by every chest once it has paid.
const SINK_TIME: float = 0.5
const SINK_DEPTH: float = 1.8
## Free chests have no rarity to wear at rest, so they wear this instead:
## warm white-gold, deliberately outside the four rarity colors.
const FREE_TINT: Color = Color(1.0, 0.93, 0.72)
## Prompt of a free chest. No price, no purse check — there is nothing to
## fail, so the line never has a "you can't afford it" variant.
const FREE_PROMPT: String = "[E] Abrir cofre — gratis"

@onready var _lid_pivot: Node3D = $Visual/LidPivot

## The raider who opened this chest (co-op: the loot lands on THEM).
var _opener: Node = null
## The rarity glow, kept so a re-tint (make_free) moves it instead of
## stacking a second light on the same box.
var _glow_light: OmniLight3D = null


func _init() -> void:
	meta_stat_id = "chests_opened"
	complete_sound = &"chest_open"
	prompt_text = "[E] Abrir el cofre"


func _ready() -> void:
	super()
	# A fixed rarity needs no roll; `rarity` is the single source every
	# reader (price, tint, prompt, loot roll) already goes through, so the
	# rolled tier is stored back into it and nothing else is kept.
	# A free chest rolls at OPEN time instead (see _pop_reward): its tier is
	# the opener's luck at that moment, not the party's luck when it landed.
	if rarity.is_empty() and not free_open:
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


## Turns an ALREADY READY chest free (the WorldDirector makes a share of
## the run-start chests free, and those are ready before it runs). Clears
## the sealed rarity so it rolls at open time, and repaints the box, which
## _ready had already given the paid look.
func make_free() -> void:
	if free_open:
		return
	free_open = true
	rarity = ""
	_tint_by_rarity()
	_refresh_price_prompt()


func rarity_name() -> String:
	return rarity


func price() -> int:
	return 0 if free_open else RunState.chest_price(rarity)


func _physics_process(_delta: float) -> void:
	# Prices move with every chest opened anywhere, and the raider's
	# points move with every kill: keep the prompt honest while in range.
	if available and player_in_range:
		_refresh_price_prompt()


func _refresh_price_prompt() -> void:
	if free_open:
		set_prompt(FREE_PROMPT)
		return
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
	if not free_open:
		var cost := price()
		if not player.has_method("spend_points") or not bool(player.call("spend_points", cost)):
			# Can't afford: a dull thunk and the prompt already says why.
			Sfx.play(&"dodge")
			return
		# Free chests deliberately do NOT tax the paid ones: bosses and
		# shinies drop them by the handful, and letting each one raise the
		# global price would price the paid chests out of the run.
		RunState.register_chest_opened()
	_opener = player
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
		_sink()
		return
	if free_open:
		# Rolled here, not at _ready: a free chest has no floor and no
		# sealed tier, so the opener's own luck decides what is inside.
		var stats := PlayerStats.find_in(_opener)
		var luck := (stats.luck if stats != null else 0.0) + luck_bonus
		rarity = String(UpgradePool.roll_rarity(luck).name)
	var item_id := ItemCatalog.roll_id(rarity)
	var bag := ItemBag.find_in(_opener)
	if item_id.is_empty() or bag == null:
		push_warning("Chest: no item to grant (rarity %s)" % rarity)
		_emit_completed()
		_sink()
		return
	bag.add_item(item_id)
	var row := ItemCatalog.by_id(item_id)
	get_tree().call_group("boss_ui", "announce", "Cofre %s: %s — %s" % [
			UpgradePool.rarity_display(rarity), String(row.display_name),
			String(row.description)])
	# One-line log (RunManager convention) for headless soaks.
	print("Chest opened: %s -> %s (next prices x%.2f)%s" % [
			rarity, item_id, RunState.chest_price_multiplier,
			" (free)" if free_open else ""])
	_emit_completed()
	_sink()


## A spent chest leaves the field (iteration 47). Nothing else may act on
## it from here: the WorldDirector's beacon tick reads `available`, which
## consume() already cleared, so a chest that sinks on its own can never be
## despawned a second time.
func _sink() -> void:
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_interval(reward_linger)
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - SINK_DEPTH, SINK_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, SINK_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## Band, lock and lid trim take the rarity color (emissive so it reads at
## night); the wood stays wood.
func _tint_by_rarity() -> void:
	var color := FREE_TINT if free_open else ItemCatalog.rarity_color(rarity)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.3 if (not free_open and rarity == "Common") else 0.9
	for path: String in ["Visual/Band", "Visual/Lock", "Visual/LidPivot/LidTrim"]:
		var mesh_instance := get_node_or_null(path) as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = material
	if free_open or rarity == "Epic" or rarity == "Legendary":
		if _glow_light == null:
			_glow_light = OmniLight3D.new()
			_glow_light.light_energy = 1.6
			_glow_light.omni_range = 5.0
			_glow_light.position = Vector3.UP * 1.2
			add_child(_glow_light)
		_glow_light.light_color = color
