class_name Pet
extends Node3D
## Una mascota: hija del nodo Player (así el carrier_player() de su arma
## encuentra al raider y lee SUS stats) pero top_level, para que lo siga con
## su propio suavizado en vez de ir pegada al cuerpo. Inmortal: sin Health y
## en ningún grupo atacable. Se arma con una fila de PetCatalog: malla del
## cuerpo, altura de vuelo y arma hija.
##
## Una por raider: Player.set_pet() libera la vieja antes de crear la nueva.

## Rigidez del seguimiento y del giro, en 1/segundos de suavizado
## exponencial (ver _physics_process): más alto es más rápido, y no depende
## de la frecuencia de física.
@export var follow_speed: float = 6.0
@export var turn_speed: float = 6.0
## Posición respecto del dueño, en metros (rota con él).
@export var follow_offset: Vector3 = Vector3(-1.4, 0.0, 1.2)
var pet_id: String = ""
var _row: Dictionary = {}
var _weapon: WeaponBase = null
var _body: MeshInstance3D = null
var _time: float = 0.0
## Campos de la fila que se leen cada frame o dos veces al armar; se
## resuelven una vez en _ready.
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
			# Teselado explícito (el motor usa 64 lados): 16 lados alcanzan a
			# tamaño de mascota; los 8 anillos mantienen los extremos redondos.
			capsule.radial_segments = 16
			capsule.rings = 8
			_body.mesh = capsule
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(size * 1.6, size, size * 2.2)
			_body.mesh = box
		_:
			var sphere := SphereMesh.new()
			sphere.radius = size
			sphere.height = size * 2.0
			# Teselado explícito (el motor usa 64 x 32, ~4.2k triángulos).
			sphere.radial_segments = 16
			sphere.rings = 8
			_body.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = _body_color
	material.emission_enabled = true
	material.emission = _body_color
	material.emission_energy_multiplier = 0.35
	_body.material_override = material
	add_child(_body)
	# Dos ojitos para que se lea como criatura y no como prop.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = size * 0.14
		eye_mesh.height = size * 0.28
		# Una cuenta de pocos centímetros: con 8 x 4 no se nota la diferencia.
		eye_mesh.radial_segments = 8
		eye_mesh.rings = 4
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
	# La única escala que hay. El arma nunca se registra en
	# used_weapon_<id>: es de la MASCOTA, no del raider, y la Colección no
	# debe desbloquear un arma que nadie ganó. Solo Player._apply_character
	# y la entrega de UpgradePool suben ese contador, y ninguno pasa por aquí.
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
	# Suavizado exponencial (1 - e^-kt), la convención del proyecto: un
	# factor lineal delta * speed cambiaría la rigidez con la frecuencia de
	# física y la teletransportaría cuando delta * speed pase de 1.
	global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))
	var to_owner := owner_body.global_position - global_position
	to_owner.y = 0.0
	if to_owner.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-to_owner.x, -to_owner.z),
				1.0 - exp(-turn_speed * delta))
