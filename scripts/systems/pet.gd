class_name Pet
extends Node3D
## A companion (iteration 43): child of the Player node (so its weapon's
## carrier_player() walk finds the raider and reads THEIR stats) but
## top_level, so it follows with its own smoothing instead of riding the
## body rigidly. Immortal: no Health, not in any targetable group. Built
## from a PetCatalog row: body mesh, hover height, weapon child.
##
## One per raider (iteration 54): Player.set_pet() frees the old one before
## spawning the new one, so a swap is a swap and not a menagerie.

## Follow/turn stiffness, in "1/seconds" of exponential smoothing (see
## _physics_process): higher is snappier, and the shape is independent of
## the physics tick rate.
@export var follow_speed: float = 6.0
@export var turn_speed: float = 6.0
@export var follow_offset: Vector3 = Vector3(-1.4, 0.0, 1.2)
var pet_id: String = ""
var _row: Dictionary = {}
var _weapon: WeaponBase = null
var _body: MeshInstance3D = null
var _time: float = 0.0
## Row fields read every frame / twice per build, resolved once in _ready.
var _hover: float = 1.0
var _body_color: Color = Color.WHITE


func setup(row: Dictionary) -> void:
	_row = row
	pet_id = String(row.id)
	name = "Pet_" + pet_id


func _ready() -> void:
	top_level = true
	_hover = float(_row.get("hover", 1.0))
	_body_color = _row.get("color", Color.WHITE)
	var owner_body := get_parent() as Node3D
	if owner_body != null:
		global_position = owner_body.global_position + follow_offset
	_build_body()
	_build_weapon()


func _build_body() -> void:
	_body = MeshInstance3D.new()
	var size := float(_row.get("size", 0.5))
	match String(_row.get("shape", "sphere")):
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = size * 0.6
			capsule.height = size * 2.2
			_body.mesh = capsule
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(size * 1.6, size, size * 2.2)
			_body.mesh = box
		_:
			var sphere := SphereMesh.new()
			sphere.radius = size
			sphere.height = size * 2.0
			_body.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = _body_color
	material.emission_enabled = true
	material.emission = _body_color
	material.emission_energy_multiplier = 0.35
	_body.material_override = material
	add_child(_body)
	# Two beady eyes so it reads as a creature, not a prop.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = size * 0.14
		eye_mesh.height = size * 0.28
		eye.mesh = eye_mesh
		var eye_material := StandardMaterial3D.new()
		eye_material.albedo_color = Color(0.05, 0.05, 0.08)
		eye.material_override = eye_material
		eye.position = Vector3(side * size * 0.35, size * 0.25, -size * 0.8)
		add_child(eye)


func _build_weapon() -> void:
	var path := String(_row.get("weapon_scene", ""))
	if path.is_empty():
		return
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Pet: bad weapon scene '%s'" % path)
		return
	_weapon = scene.instantiate() as WeaponBase
	if _weapon == null:
		return
	_weapon.name = "PetWeapon"
	# The one scale there is (iteration 54: copies are gone). The weapon is
	# never registered in used_weapon_<id> — it belongs to the PET, not to
	# the raider, and the Collection page must not unlock an arsenal entry
	# nobody earned. Only Player._apply_character and the UpgradePool grant
	# bump that counter, and neither is reachable from here.
	_weapon.damage *= float(_row.get("weapon_damage_scale", 0.5))
	add_child(_weapon)


func _physics_process(delta: float) -> void:
	_time += delta
	var owner_body := get_parent() as Node3D
	if owner_body == null:
		return
	var target := owner_body.global_position \
			+ follow_offset.rotated(Vector3.UP, owner_body.rotation.y)
	target.y = owner_body.global_position.y + _hover + sin(_time * 3.0) * 0.12
	# Exponential smoothing (1 - e^-kt), the project convention: a linear
	# delta * speed factor changes the pet's stiffness with the physics tick
	# rate, and teleports it outright once delta * speed passes 1.
	global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))
	var to_owner := owner_body.global_position - global_position
	to_owner.y = 0.0
	if to_owner.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-to_owner.x, -to_owner.z),
				1.0 - exp(-turn_speed * delta))
