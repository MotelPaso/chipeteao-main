extends CharacterBody3D
## Player controller: WASD movement relative to camera yaw, mouse-look,
## jump, and a Shift+move slide (speed burst + lowered collision).
## At spawn it applies the selected character's loadout (GameConfig ->
## CharacterCatalog row): starting weapon, capsule tint, per-level passive.

@export_group("Movement")
@export var move_speed: float = 6.0
@export var acceleration: float = 12.0
@export var air_acceleration: float = 4.0
@export var jump_velocity: float = 8.0

@export_group("Slide")
@export var slide_speed_multiplier: float = 1.8
@export var slide_duration: float = 0.6
@export var slide_cooldown: float = 0.8
@export var slide_collision_height: float = 0.9

@export_group("Combat")
## Cap on simultaneous weapons under the Weapons mount; the upgrade pool
## stops offering new-weapon cards once it is reached.
@export var max_weapons: int = 4

@export_group("Camera")
@export var mouse_sensitivity: float = 0.003
@export var initial_pitch_deg: float = -20.0
@export var min_pitch_deg: float = -80.0
@export var max_pitch_deg: float = 10.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var weapons_mount: Node3D = $Weapons
@onready var health: Health = $Health
@onready var _stats: PlayerStats = $Stats

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _default_collision_height: float = 1.8
var _default_collision_radius: float = 0.4

var _yaw: float = 0.0
var _pitch: float = 0.0

var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO

var _is_dead: bool = false


func _ready() -> void:
	_apply_character(CharacterCatalog.by_id_or_default(GameConfig.selected_character_id))
	health.died.connect(_on_health_died)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# The camera arm must ignore our own capsule or it pushes the camera in.
	spring_arm.add_excluded_object(get_rid())
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule != null:
		_default_collision_height = capsule.height
		_default_collision_radius = capsule.radius
	_yaw = rotation.y
	_pitch = deg_to_rad(clamp(initial_pitch_deg, min_pitch_deg, max_pitch_deg))
	spring_arm.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if _is_dead:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity,
				deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
		rotation.y = _yaw
		spring_arm.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir: Vector3 = transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO

	# Tome of Swiftness etc. scale on top of the exported base speed.
	var effective_speed: float = move_speed * _stats.move_speed_multiplier

	if _slide_cooldown_timer > 0.0:
		_slide_cooldown_timer -= delta

	if _is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0 or not is_on_floor():
			_end_slide()
	elif _can_start_slide(wish_dir, effective_speed):
		_start_slide(wish_dir)

	if _is_sliding:
		var slide_velocity: Vector3 = _slide_direction * effective_speed * slide_speed_multiplier
		velocity.x = slide_velocity.x
		velocity.z = slide_velocity.z
	else:
		var target: Vector3 = wish_dir * effective_speed
		var accel: float = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		if _is_sliding:
			_end_slide()
		velocity.y = jump_velocity

	move_and_slide()


## Applies a CharacterCatalog row: instances the starting weapon under the
## Weapons mount, tints the placeholder capsule, registers the passive.
func _apply_character(character: Dictionary) -> void:
	var scene := load(String(character.weapon_scene)) as PackedScene
	if scene == null:
		push_warning("Player: bad starting weapon scene '%s'" % character.weapon_scene)
	else:
		var weapon := scene.instantiate() as Node3D
		# The name must match the WEAPON_LIBRARY node_name so the upgrade
		# pool counts the starting weapon as owned.
		weapon.name = String(character.weapon_node_name)
		weapons_mount.add_child(weapon)
	# Fresh material instead of mutating the scene's shared one.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(character.tint)
	mesh_instance.set_surface_override_material(0, material)
	_stats.set_character_passive(String(character.passive_stat),
			float(character.passive_amount),
			String(character.get("passive_kind", "per_level")))


func _on_health_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	if _is_sliding:
		_end_slide()
	# Freeze control and physics; RunManager pauses the whole tree right
	# after this handler, so the fall-over tween must be pause-immune to
	# play out under the fading run-end screen.
	set_physics_process(false)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	# Face-plant: tip the capsule forward (-Z) with a comedic bounce and
	# drop its center to rest on the floor (capsule radius 0.4).
	tween.tween_property(mesh_instance, "rotation:x", -TAU * 0.25, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(mesh_instance, "position:y", 0.45, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _can_start_slide(wish_dir: Vector3, effective_speed: float) -> bool:
	if not Input.is_action_pressed("sprint") or wish_dir == Vector3.ZERO:
		return false
	if not is_on_floor() or _slide_cooldown_timer > 0.0:
		return false
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	return horizontal_speed > effective_speed * 0.5


func _start_slide(direction: Vector3) -> void:
	_is_sliding = true
	_slide_timer = slide_duration
	_slide_direction = direction
	_set_body_height(slide_collision_height)


func _end_slide() -> void:
	_is_sliding = false
	_slide_cooldown_timer = slide_cooldown
	_set_body_height(_default_collision_height)


func _set_body_height(height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	# Setting height below 2*radius makes Godot shrink the radius, so
	# re-apply the default radius (clamped) to keep restores lossless.
	capsule.height = height
	capsule.radius = minf(_default_collision_radius, height * 0.5)
	collision_shape.position.y = height * 0.5
	# Squash the placeholder mesh to match, keeping its base on the floor.
	mesh_instance.scale.y = height / _default_collision_height
	mesh_instance.position.y = height * 0.5
