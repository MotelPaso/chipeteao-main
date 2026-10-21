class_name PetBox
extends Interactable
## A crate with a paw on it (iteration 54): free, one use, and the first
## of the two doors a companion comes through (the other is the animal
## trafficker). Rolls ONE pet that is not the one already following the
## raider, and either hands it over or — when there is already a
## companion — asks, because a pet slot holds exactly one and taking the
## new one throws away the old.
##
## Free on purpose. The trafficker sells a CHOICE of three for points; the
## box is the version you find, so its price is having walked to it.

## Sink-out after use, same shape as a spent altar.
@export var sink_time: float = 0.55
@export var paw_color: Color = Color(0.7, 0.95, 0.6)

## Card titles. Option 0 is the SWAP: the soak harness always presses the
## first option, so the interesting branch has to be the one it exercises.
const SWAP_TITLE: String = "Cambiar por %s"
const KEEP_TITLE: String = "Quedarme con %s"
const CHOICE_TITLE: String = "La caja se abre sola"
const NO_PET_LINE: String = "Sin mascota"

var _spent: bool = false
var _lid: MeshInstance3D = null
var _time: float = 0.0


func _init() -> void:
	prompt_text = "[E] Abrir la caja"
	marker_kind = &"pet_box"
	prompt_height = 2.6
	# No meta counter of its own: what the quests count is the companion,
	# and that is bumped where the pet actually changes hands.
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	# Detection ring BEFORE super(), which wires body_entered on this Area3D.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.0
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	add_child(shape)
	super()
	add_to_group(&"pet_boxes")
	_build_visual()


func _build_visual() -> void:
	var crate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 1.0, 1.3)
	crate.mesh = box
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	crate.material_override = wood
	crate.position.y = 0.5
	add_child(crate)
	_lid = MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.42, 0.16, 1.42)
	_lid.mesh = lid_mesh
	var lid_material := StandardMaterial3D.new()
	lid_material.albedo_color = paw_color
	lid_material.emission_enabled = true
	lid_material.emission = paw_color
	lid_material.emission_energy_multiplier = 0.8
	_lid.material_override = lid_material
	_lid.position.y = 1.05
	add_child(_lid)
	var paw := Label3D.new()
	paw.text = "●"
	paw.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	paw.no_depth_test = true
	paw.font_size = 44
	paw.outline_size = 10
	paw.modulate = paw_color
	paw.position.y = 1.5
	add_child(paw)


func _physics_process(delta: float) -> void:
	_time += delta
	if _lid != null and available:
		_lid.position.y = 1.05 + sin(_time * 2.2) * 0.05


func _interact(player: Node) -> void:
	if _spent or not available:
		return
	var pet_id := _roll_pet(player)
	if pet_id.is_empty():
		# Every pet in the catalog is already the one following: nothing to
		# offer, and a box that swapped a pet for itself would read as broken.
		get_tree().call_group("hud", "announce", "La caja está vacía.")
		return
	_spent = true
	_emit_started()
	consume()
	var current: Variant = player.get("pet_id")
	if current == null or String(current).is_empty():
		_grant(player, pet_id)
		return
	# A companion already follows: this is a TRADE, so it is asked, not
	# done. open_choice is the one blocking-pick contract in the project,
	# and the soak answers it by pressing option 0.
	var offered := PetCatalog.by_id(pet_id)
	var held := PetCatalog.by_id(String(current))
	var options: Array[Dictionary] = [
		{
			"title": SWAP_TITLE % String(offered.display_name),
			"description": _pet_lines(offered),
			"color": offered.get("color", Color.WHITE),
			"pet_id": pet_id,
		},
		{
			"title": KEEP_TITLE % String(held.display_name),
			"description": _pet_lines(held),
			"color": held.get("color", Color.WHITE),
			"pet_id": String(current),
		},
	]
	get_tree().call_group("upgrade_ui", "open_choice", CHOICE_TITLE, options,
			player, _on_choice.bind(player), "pet_box")


func _on_choice(option: Dictionary, player: Node) -> void:
	_grant(player, String(option.get("pet_id", "")))


## Hands the companion over. Player.set_pet owns the swap, the toasts and
## the "Pet joined:" line, so this only reports the box.
func _grant(player: Node, pet_id: String) -> void:
	# Logged BEFORE the grant so the soak reads cause then effect: this
	# line, then the "Pet joined:" that set_pet prints.
	print("Pet box opened: %s" % pet_id)
	if not pet_id.is_empty() and player.has_method("set_pet"):
		player.call("set_pet", pet_id)
	Juice.sparkle(global_position + Vector3.UP * 1.2)
	_emit_completed()
	_sink()


## Weapon and stat on two lines: the two things that actually differ
## between companions, and the whole basis for the trade.
static func _pet_lines(row: Dictionary) -> String:
	if row.is_empty():
		return NO_PET_LINE
	return "%s\n%s" % [PetCatalog.weapon_display_name(row),
			String(row.get("stat_label", ""))]


## A catalog pet that is not the one already following `player`.
func _roll_pet(player: Node) -> String:
	var current: Variant = player.get("pet_id")
	var held := String(current) if current != null else ""
	var candidates: Array[String] = []
	for row: Dictionary in PetCatalog.PET_LIBRARY:
		if String(row.id) != held:
			candidates.append(String(row.id))
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]


func _sink() -> void:
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, sink_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
