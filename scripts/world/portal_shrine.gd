class_name PortalShrine
extends Interactable
## Portal altar (iteration 41): the WorldDirector drops portals around the
## map at run start and links them in random PAIRS. Pressing E inside
## one teleports the raider to its twin; both then recharge for
## `cooldown` seconds (Cosmic Worm copies on the traveller shorten it).
## Built entirely in code (ring, pillar of light, detection shape), so
## the director can spawn any number without a scene per portal.

@export var cooldown: float = 30.0
@export var worm_cooldown_per_copy: float = 0.25
@export var ring_radius: float = 1.6
## How far past the twin's ring the traveller lands (so the arrival does
## not immediately re-trigger the portal they just came out of).
@export var exit_margin: float = 1.2

## Idle presentation of the built-in-code visual.
const RING_SPIN: float = 0.8
const IDLE_PULSE_HZ: float = 3.0
const IDLE_PULSE_AMOUNT: float = 0.05
const PILLAR_HEIGHT: float = 6.0
const PILLAR_TOP_RADIUS: float = 0.9
## Detection cylinder = ring + this, so the prompt shows a step early.
const DETECT_MARGIN: float = 0.6
## Exit angles tried around the twin before giving up and landing on it.
const EXIT_ANGLE_TRIES: int = 8
## Height the traveller is placed at, clear of the floor plate.
const EXIT_LIFT: float = 0.2

var twin: PortalShrine = null
var pair_color: Color = Color(0.5, 0.9, 1.0)
var _cooldown_left: float = 0.0
var _pillar: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _time: float = 0.0


func _init() -> void:
	prompt_text = "[E] Atravesar"
	prompt_height = 3.0
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	# Detection ring BEFORE super(), which wires body_entered on this Area3D.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = ring_radius + DETECT_MARGIN
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	add_child(shape)
	super()
	_build_visual()


func _build_visual() -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - 0.12
	torus.outer_radius = ring_radius + 0.12
	_ring.mesh = torus
	_ring.position.y = 0.06
	_ring.material_override = _glow_material(0.9)
	add_child(_ring)
	_pillar = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = PILLAR_TOP_RADIUS
	mesh.bottom_radius = ring_radius
	mesh.height = PILLAR_HEIGHT
	_pillar.mesh = mesh
	_pillar.position.y = PILLAR_HEIGHT * 0.5
	_pillar.material_override = _glow_material(0.28, true)
	add_child(_pillar)
	var light := OmniLight3D.new()
	light.light_color = pair_color
	light.light_energy = 1.8
	light.omni_range = 7.0
	light.position.y = 1.5
	add_child(light)


func _glow_material(alpha: float, additive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(pair_color, alpha)
	material.emission_enabled = true
	material.emission = pair_color
	material.emission_energy_multiplier = 1.4
	return material


func is_ready() -> bool:
	return _cooldown_left <= 0.0 and twin != null and is_instance_valid(twin)


func _physics_process(delta: float) -> void:
	_time += delta
	if _ring != null:
		_ring.rotate_y(delta * RING_SPIN)
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		var fraction := 1.0 - _cooldown_left / maxf(cooldown, 0.01)
		if _pillar != null:
			_pillar.scale = Vector3(0.3 + 0.7 * fraction, 1.0, 0.3 + 0.7 * fraction)
		if player_in_range:
			set_prompt(_recharging_text())
	elif _pillar != null:
		_pillar.scale = Vector3.ONE * (1.0 + sin(_time * IDLE_PULSE_HZ) * IDLE_PULSE_AMOUNT)


func _recharging_text() -> String:
	return "Recargando... %d s" % ceili(_cooldown_left)


func _on_range_entered() -> void:
	set_prompt("[E] Atravesar" if is_ready() else _recharging_text())


func _interact(player: Node) -> void:
	if not is_ready():
		Sfx.play(&"dodge")
		return
	var body := player as Node3D
	if body == null:
		return
	var worms := 0
	var bag := ItemBag.find_in(player)
	if bag != null:
		worms = bag.count("cosmic_worm")
	var recharge := cooldown / (1.0 + worm_cooldown_per_copy * float(worms))
	body.global_position = _exit_position()
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	start_cooldown(recharge)
	twin.start_cooldown(recharge)
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	Juice.sparkle(twin.global_position + Vector3.UP * 1.0)
	Sfx.play(&"burrow_pop")
	SaveData.bump("portals_used")
	print("Portal used: %s -> %s (recharge %.0fs)" % [name, twin.name, recharge])


## Landing spot just outside the twin's ring (so the arrival does not
## re-trigger it), on a WALKABLE cell: the irregular arena mask can seal
## a whole 10 m cell right next to a portal, and a blind random angle used
## to drop the traveller inside the mask wall's collider — encased in
## rock, with both portals already on a 30 s cooldown. Falls back to the
## twin's own spot, whose cell is open by construction.
func _exit_position() -> Vector3:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	var start := randf() * TAU
	for i in EXIT_ANGLE_TRIES:
		var angle := start + TAU * float(i) / float(EXIT_ANGLE_TRIES)
		var candidate := twin.global_position \
				+ Vector3.FORWARD.rotated(Vector3.UP, angle) * (ring_radius + exit_margin) \
				+ Vector3.UP * EXIT_LIFT
		if bounds == null or not bounds.has_method("is_walkable") \
				or bool(bounds.call("is_walkable", Vector2(candidate.x, candidate.z))):
			return candidate
	return twin.global_position + Vector3.UP * EXIT_LIFT


func start_cooldown(seconds: float) -> void:
	_cooldown_left = seconds
	if player_in_range:
		set_prompt(_recharging_text())
