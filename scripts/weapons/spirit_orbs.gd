extends WeaponBase
## Spirit Orbs (iteration 37): a ring of glowing familiars that orbit the
## carrier and burn whatever they touch. No firing — the whole weapon is a
## persistent contact aura, so it overrides _physics_process instead of
## fire(). It deliberately does NOT call super(): there is no cooldown tick
## and no acquire_target()/fire() cycle here, the ring simply always runs.
## Knob mapping onto the shared WeaponBase contract:
##   damage           — per touch (through deal_damage: crit/lifesteal apply)
##   cooldown         — per-ENEMY re-hit interval (haste tomes tighten it)
##   attack_range     — orbit radius (Long Reach widens the ring)
##   projectile_count — number of orbs (+1 orb card; evolution adds one)

## Contact distance from an orb's center to an enemy body.
@export var hit_radius: float = 1.1
## Ring angular speed, radians per second.
@export var orbit_speed: float = 2.6
## Height of the ring above the carrier's feet.
@export var orb_height: float = 1.0

## Vertical wobble that keeps the ring from reading as a flat decal.
const BOB_HEIGHT: float = 0.15
const ORB_RADIUS: float = 0.22

var _angle: float = 0.0
var _orbs: Array[MeshInstance3D] = []
## Where the ring is centered this frame (the carrier rig's feet); kept so
## the contact pass can bound its search around the same point.
var _ring_center: Vector3 = Vector3.ZERO
## Per-enemy re-hit timers, keyed by instance id.
var _rehit: Dictionary[int, float] = {}
## Scratch list for _tick_rehit: the keys whose timer ran out this frame.
## A member so the countdown allocates nothing on the frames where no
## timer expires (it used to copy the whole key set every frame).
var _rehit_expired: Array[int] = []
## Scratch list for _touch_enemies: every orb's world position this frame.
var _orb_positions: PackedVector3Array = PackedVector3Array()
## One mesh (with its material) shared by every orb, for the life of the
## weapon: _rebuild_orbs runs whenever an upgrade changes the orb count, and
## it used to mint a fresh SphereMesh and StandardMaterial3D each time.
var _orb_mesh: SphereMesh = null


func _ready() -> void:
	_orb_mesh = SphereMesh.new()
	_orb_mesh.radius = ORB_RADIUS
	_orb_mesh.height = ORB_RADIUS * 2.0
	# Explicit tessellation: the engine default (64 x 32, ~4.2k triangles
	# per orb) for a 44 cm unshaded glow ball.
	_orb_mesh.radial_segments = 12
	_orb_mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.6, 0.95, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.45, 0.9, 1.0)
	material.emission_energy_multiplier = 2.2
	_orb_mesh.material = material


func _physics_process(delta: float) -> void:
	if _orbs.size() != effective_projectile_count():
		_rebuild_orbs()
	_update_ring(delta)
	_tick_rehit(delta)
	_touch_enemies()


## Presentation: walks the orbit clock and places the orbs in world space.
func _update_ring(delta: float) -> void:
	_angle = wrapf(_angle + orbit_speed * delta, 0.0, TAU)
	var radius := attack_range
	# World-space ring around the carrier's feet: the orbit angle is its own
	# clock, so turning or strafing the seal never drags the ring around with
	# the body (the orbs are children, hence global_position). The center
	# follows the rig that carries the weapon, so a pet's ring orbits the pet.
	_ring_center = global_position
	var carrier := carrier_node()
	if carrier != null:
		_ring_center = carrier.global_position
	for i in _orbs.size():
		var orb_angle := _angle + TAU * float(i) / float(_orbs.size())
		_orbs[i].global_position = _ring_center + Vector3(
				cos(orb_angle) * radius,
				orb_height + sin(orb_angle * 2.0) * BOB_HEIGHT,
				sin(orb_angle) * radius)


## Simulation: counts down the per-enemy immunity left by the last touch.
## Same arithmetic as before (one subtraction per frame per key), but it
## walks the dictionary in place: writing a value under an existing key
## is safe mid-iteration, erasing is not, so the erases wait for the loop.
func _tick_rehit(delta: float) -> void:
	for key: int in _rehit:
		var left := _rehit[key] - delta
		_rehit[key] = left
		if left <= 0.0:
			_rehit_expired.append(key)
	if _rehit_expired.is_empty():
		return
	for key: int in _rehit_expired:
		_rehit.erase(key)
	_rehit_expired.clear()


## Simulation: burns every enemy an orb is currently overlapping.
func _touch_enemies() -> void:
	if get_tree().get_first_node_in_group("enemies") == null:
		return
	var reach := hit_radius * area_scale()
	var reach_sq := reach * reach
	# Broad phase around the ring center. No orb sits farther from it than
	# attack_range horizontally plus orb_height + BOB_HEIGHT vertically, and
	# no contact reaches past `reach` from an orb, so this sphere is a strict
	# superset of what the per-orb test below can accept.
	var search := attack_range + orb_height + BOB_HEIGHT + reach
	# Each orb's world position, read ONCE per frame instead of once per
	# (body, orb) pair. Read back through the getter, not taken from what
	# _update_ring wrote, so the value is bit-for-bit the one the old
	# per-pair read returned; nothing a hit triggers moves the carrier.
	_orb_positions.resize(_orbs.size())
	for i: int in _orbs.size():
		_orb_positions[i] = _orbs[i].global_position
	var aim_lift := Vector3.UP * orb_height * 0.5
	for body: Node3D in enemies_in_sphere(_ring_center, search):
		if _rehit.has(body.get_instance_id()):
			continue
		# Once per body: the orb loop below damages at most once and then
		# breaks, so the body cannot move between two of these reads.
		var aim := body.global_position + aim_lift
		for orb_position: Vector3 in _orb_positions:
			if orb_position.distance_squared_to(aim) > reach_sq:
				continue
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				deal_damage(health)
				_rehit[body.get_instance_id()] = effective_cooldown()
			break


## Rebuilds the orb rig after an upgrade changed the count. Only the
## MeshInstance3D nodes are new; the mesh and material are shared.
func _rebuild_orbs() -> void:
	for orb: MeshInstance3D in _orbs:
		orb.queue_free()
	_orbs.clear()
	for i in effective_projectile_count():
		var orb := MeshInstance3D.new()
		orb.mesh = _orb_mesh
		# A glowing familiar casting a speck of a shadow under itself read
		# as noise, and cost a draw in every shadow cascade; every other
		# FX already opts out (spawn_fx_mesh).
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(orb)
		_orbs.append(orb)
