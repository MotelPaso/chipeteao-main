class_name ExitPortal
extends Interactable
## The way out of a stage (iteration 49). One per stage, raised by the
## WorldDirector the moment RunState.stage_cleared flips true — the stage
## goal is met and the stage boss is dead — somewhere far from the party.
## Built in code like PortalShrine, but taller, gold, and permanent: it
## never recharges and it is never consumed by anything except being used.
##
## Any live raider standing in the ring can take it, and the WHOLE party
## travels (downed bodies included): RunRoot.advance_stage() moves
## everyone, so a co-op run can never be split across two maps.
##
## Not a PortalShrine subclass: a paired in-map teleporter and a stage exit
## share only their looks. Inheriting would have dragged the twin, the
## cooldown and the Cosmic Worm discount into a portal that has none of
## them, and every one of those would have needed a special case.

## Radius of the ring the raider has to stand in.
@export var ring_radius: float = 2.2
@export var portal_color: Color = Color(1.0, 0.82, 0.35)

## Detection cylinder = ring + this, so the prompt shows a step early.
const DETECT_MARGIN: float = 0.8
## Deliberately taller than a PortalShrine's 6 m: this one has to read as
## "the way out" from across the arena, over the beacon that marks it.
const PILLAR_HEIGHT: float = 11.0
const PILLAR_TOP_RADIUS: float = 1.3
const RING_SPIN: float = 0.55
const IDLE_PULSE_HZ: float = 2.2
const IDLE_PULSE_AMOUNT: float = 0.08

var _pillar: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _time: float = 0.0
## True from the press until the swap owns the run: a second raider
## pressing on the same frame must not queue a second stage change.
var _taken: bool = false


func _init() -> void:
	prompt_text = "[E] Cruzar al siguiente mapa"
	marker_kind = &"exit"
	prompt_height = 4.2
	# No meta counter of its own: the stage counters live in RunState and
	# are folded once at the end of the run.
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	# Detection ring BEFORE super(), which wires body_entered on this Area3D.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = ring_radius + DETECT_MARGIN
	cylinder.height = 4.0
	shape.shape = cylinder
	shape.position.y = 2.0
	add_child(shape)
	super()
	_build_visual()


func _build_visual() -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - 0.16
	torus.outer_radius = ring_radius + 0.16
	_ring.mesh = torus
	_ring.position.y = 0.07
	_ring.material_override = _glow_material(0.95)
	add_child(_ring)
	_pillar = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = PILLAR_TOP_RADIUS
	mesh.bottom_radius = ring_radius
	mesh.height = PILLAR_HEIGHT
	_pillar.mesh = mesh
	_pillar.position.y = PILLAR_HEIGHT * 0.5
	_pillar.material_override = _glow_material(0.3, true)
	add_child(_pillar)
	var light := OmniLight3D.new()
	light.light_color = portal_color
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position.y = 2.0
	add_child(light)


## Per-instance material: these are built here, never shared from a scene
## sub-resource, so the idle pulse below cannot bleed into another portal.
func _glow_material(alpha: float, additive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(portal_color, alpha)
	material.emission_enabled = true
	material.emission = portal_color
	material.emission_energy_multiplier = 1.8
	return material


func _physics_process(delta: float) -> void:
	_time += delta
	if _ring != null:
		_ring.rotate_y(delta * RING_SPIN)
	if _pillar != null:
		_pillar.scale = Vector3.ONE * (1.0 + sin(_time * IDLE_PULSE_HZ) * IDLE_PULSE_AMOUNT)


func _interact(_player: Node) -> void:
	if _taken:
		return
	var root := get_tree().get_first_node_in_group("run_root")
	if root == null or not root.has_method("advance_stage"):
		push_warning("ExitPortal: no run root to advance the stage.")
		return
	_taken = true
	consume()
	_emit_completed()
	# Same prefix the in-map portals print, with the kind spelled out: the
	# soak's interaction counter deliberately ignores the exit one, since a
	# stage change is not "the party used a teleporter".
	print("Portal used: exit")
	root.call("advance_stage")
