class_name Vendor
extends Interactable
## A stall that shows up mid-run (iteration 54) and leaves after ONE sale.
##
## Three kinds, one table: the animal trafficker sells a choice of three
## companions, the power-up vendor sells one rolled power-up at a price
## that climbs run-wide, and the item vendor sells four items at chest
## prices. The kind is rolled hidden by the WorldDirector and announced
## only as "a vendor arrived" — walking over to find out which one is the
## point, and a beacon that named the kind would answer the question from
## across the map.
##
## The stall owns the ECONOMY (what is charged, what is granted, the log,
## and the one-sale rule); VendorUi owns the moment (what is on the shelf,
## what a card says, what happens between the press and the goodbye).
##
## It persists until it sells something: a vendor that timed out would be
## a 240 m walk the party can lose by arriving late.

## Row fields: id (identifier, also `kind`), display_name and prompt
## (player text), color (beacon, panel accent and the marker). A fourth
## kind is a row here plus one branch in VendorUi._build_offers and one in
## buy() — never a special case keyed on an id somewhere else.
const VENDOR_LIBRARY: Array[Dictionary] = [
	{
		"id": "animals", "display_name": "Traficante de animales",
		"prompt": "[E] Ver los animales",
		"color": Color(0.55, 0.9, 0.6),
	},
	{
		"id": "powerups", "display_name": "Vendedor de power-ups",
		"prompt": "[E] Ver el power-up",
		"color": Color(0.5, 0.8, 1.0),
	},
	{
		"id": "items", "display_name": "Vendedor de objetos",
		"prompt": "[E] Ver la mercancía",
		"color": Color(1.0, 0.82, 0.35),
	},
]

## Which stall this is; set by the WorldDirector before it enters the tree.
@export var kind: String = "items"
## Flat price of any companion at the trafficker. Deliberately not a chest
## price: a pet is a slot, not a rarity, and pricing it by tier would
## imply one of them is the good one.
@export var pet_price: int = 120
## After a menu closes with no sale, the stall ignores `interact` for this
## long. The soak re-fires interact every 0.75 s while it lingers, and
## without this the panel would reopen the instant it closed, forever.
@export var retry_cooldown: float = 20.0
@export var sink_time: float = 0.6

const VENDOR_UI_SCRIPT := preload("res://scripts/ui/vendor_ui.gd")

## The power-up price multiplies by this with every purchase, run-wide.
const POWERUP_PRICE_GROWTH: float = 1.5

var _sold: bool = false
var _cooldown_left: float = 0.0
var _ui: CanvasLayer = null
var _time: float = 0.0
var _sign: MeshInstance3D = null


func _init() -> void:
	marker_kind = &"vendor"
	prompt_height = 3.0
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.4
	cylinder.height = 3.5
	shape.shape = cylinder
	shape.position.y = 1.75
	add_child(shape)
	super()
	# NOT the "altars" group: the WorldDirector's altar cap counts that one,
	# and a stall standing around would starve the altar cadence.
	add_to_group(&"vendors")
	set_prompt(String(row().get("prompt", "[E] Comerciar")))
	_build_visual()


## This stall's VENDOR_LIBRARY row (the first row if `kind` is unknown, so
## a bad export still draws something instead of crashing).
func row() -> Dictionary:
	for entry: Dictionary in VENDOR_LIBRARY:
		if String(entry.id) == kind:
			return entry
	push_warning("Vendor: unknown kind '%s'" % kind)
	return VENDOR_LIBRARY[0]


func _build_visual() -> void:
	var tint: Color = row().get("color", Color.WHITE)
	var stall := MeshInstance3D.new()
	var counter := BoxMesh.new()
	counter.size = Vector3(2.2, 1.0, 0.8)
	stall.mesh = counter
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.26, 0.18)
	stall.material_override = wood
	stall.position.y = 0.5
	add_child(stall)
	# The figure behind the counter: a capsule in the stall's own colour,
	# which is the only thing that hints at the kind before the prompt.
	var figure := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.5
	figure.mesh = body
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = tint
	cloth.emission_enabled = true
	cloth.emission = tint
	cloth.emission_energy_multiplier = 0.5
	figure.material_override = cloth
	figure.position = Vector3(0.0, 1.15, -0.7)
	add_child(figure)
	_sign = MeshInstance3D.new()
	var awning := BoxMesh.new()
	awning.size = Vector3(2.4, 0.12, 1.2)
	_sign.mesh = awning
	var awning_material := StandardMaterial3D.new()
	awning_material.albedo_color = tint
	awning_material.emission_enabled = true
	awning_material.emission = tint
	awning_material.emission_energy_multiplier = 1.1
	_sign.material_override = awning_material
	_sign.position.y = 2.2
	add_child(_sign)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.5
	light.omni_range = 7.0
	light.position.y = 2.0
	add_child(light)


func _physics_process(delta: float) -> void:
	_time += delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _sign != null and available:
		_sign.position.y = 2.2 + sin(_time * 1.6) * 0.04


func _interact(player: Node) -> void:
	if _sold or not available or _cooldown_left > 0.0:
		return
	if _ui != null and is_instance_valid(_ui):
		return
	var ui := VENDOR_UI_SCRIPT.new() as CanvasLayer
	ui.call("setup", self, player)
	# Stage-scoped like every other spawned node, so a stage swap takes the
	# panel with the stall instead of leaving a paused tree behind.
	RunRoot.stage_parent(get_tree()).add_child(ui)
	_ui = ui
	ui.tree_exited.connect(_on_menu_closed)


## The menu is gone. If nothing was bought the stall stays, but goes quiet
## for a while — otherwise the soak's repeated interact would reopen it on
## the very next frame.
func _on_menu_closed() -> void:
	_ui = null
	if not _sold:
		_cooldown_left = retry_cooldown


## THE purchase. Charges, grants, logs, and closes the stall. Returns
## false ONLY when the raider cannot pay, which is what lets the panel
## keep itself open and say so.
func buy(offer: Dictionary, player: Node) -> bool:
	if _sold:
		return false
	var price := int(offer.get("price", 0))
	if not player.has_method("spend_points") or not bool(player.call("spend_points", price)):
		return false
	_sold = true
	# One-line log (RunManager convention), printed BEFORE the grant so the
	# soak reads cause then effect — this line, then whatever the payout
	# announces itself ("Pet joined:", "Power-up picked:").
	print("Vendor sold: %s %s %d" % [kind, _payload_id(offer), price])
	match String(offer.get("kind", "")):
		"animals":
			if player.has_method("set_pet"):
				player.call("set_pet", String(offer.get("pet_id", "")))
		"powerups":
			var powerups := PowerUps.find_in(player)
			if powerups != null:
				powerups.apply(String(offer.get("powerup_id", "")))
			# Run-wide, and only on a SALE: a shelf somebody looked at and
			# walked away from must not make the next one dearer.
			RunState.powerup_vendor_price = roundi(
					float(RunState.powerup_vendor_price) * POWERUP_PRICE_GROWTH)
		"items":
			var bag := ItemBag.find_in(player)
			if bag != null:
				bag.add_item(String(offer.get("item_id", "")))
			# The item shelf IS chest stock at chest prices, so it feeds the
			# same inflation counter — otherwise a vendor would be a way to
			# buy Legendaries while keeping chests cheap.
			RunState.register_chest_opened()
	consume()
	_emit_completed()
	_leave()
	return true


## The stall's own colour on the map, so the three read apart ONCE found.
## The marker itself is fog-gated like every other POI, so this never
## spoils which vendor arrived before somebody walks there.
func map_marker_color() -> Color:
	return row().get("color", Color.WHITE)


## What the offer actually handed over, for the log.
static func _payload_id(offer: Dictionary) -> String:
	for key: String in ["pet_id", "powerup_id", "item_id"]:
		var value: Variant = offer.get(key)
		if value != null and not String(value).is_empty():
			return String(value)
	return "?"


func _leave() -> void:
	get_tree().call_group("hud", "announce", "El vendedor recoge el puesto.")
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, sink_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
