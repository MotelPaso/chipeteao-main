class_name AcidPool
extends Node3D
## Pooled acid puddle left by the radioactive rain (iteration 55): a green
## disc that hurts RAIDERS ONLY and fades out on its own.
##
## Unlike BloodPoolFx — which is purely cosmetic because blood_vial.gd owns
## its damage ticks — this one owns its own tick. There is no weapon behind
## it: the weather drops it and walks away, so a pool that needed an
## external ticker would need the director to keep a list of them, and that
## list would be the thing leaking across a stage swap.
##
## Never damages enemies. The rain is a hazard for the party, not free
## crowd control: acid that also melted the horde would make the worst
## weather in the game the best one to stand in.

## Ring the pool hurts inside, and how long it lasts. Both written by the
## caller through play(); these are only the fallbacks.
@export var radius: float = 2.0
@export var lifetime: float = 6.0
@export var damage_per_second: float = 4.0
## Seconds between damage applications. Not per frame: sixty tiny hits a
## second would bury the damage popups and the HP bar in noise.
@export var tick_interval: float = 0.5

const FADE_TIME: float = 0.35
const DISC_COLOR := Color(0.45, 0.95, 0.3)
## The disc is authored at radius 1 and scaled, so one mesh serves every
## pool size.
const BASE_RADIUS: float = 1.0

var _left: float = 0.0
var _tick_left: float = 0.0
var _disc: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _fade: Tween = null
## True between the fade starting and the pooled release, so a second
## expiry cannot queue a second release for a node that may already have
## been re-acquired.
var _expiring: bool = false


func _ready() -> void:
	# Grouped so the director can count live puddles against its cap and
	# space new ones off them, without keeping a list that a stage swap
	# would leave holding freed nodes.
	add_to_group(&"acid_pools")
	_build_visual()
	set_physics_process(false)


## Pooled-node contract: fresh puddle on every acquire.
func pool_reset() -> void:
	if not is_in_group(&"acid_pools"):
		add_to_group(&"acid_pools")
	_kill_fade()
	_expiring = false
	_left = 0.0
	_tick_left = 0.0
	scale = Vector3.ONE
	if _material != null:
		_material.albedo_color = Color(DISC_COLOR, 0.55)


func _build_visual() -> void:
	_disc = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = BASE_RADIUS
	mesh.bottom_radius = BASE_RADIUS
	mesh.height = 0.08
	_disc.mesh = mesh
	# Per-instance material: the fade writes alpha, and a shared resource
	# would fade every other puddle on the map with it.
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(DISC_COLOR, 0.55)
	_material.emission_enabled = true
	_material.emission = DISC_COLOR
	_material.emission_energy_multiplier = 1.2
	_disc.material_override = _material
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


## Forms the puddle at `center`. `pool_radius` and `seconds` come from the
## weather row so one export block tunes every pool it drops.
func play(center: Vector3, pool_radius: float, seconds: float, dps: float) -> void:
	global_position = center
	radius = pool_radius
	lifetime = seconds
	damage_per_second = dps
	_left = seconds
	_tick_left = tick_interval
	_expiring = false
	scale = Vector3(pool_radius, 1.0, pool_radius)
	if _material != null:
		_material.albedo_color = Color(DISC_COLOR, 0.55)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _expiring:
		return
	_left -= delta
	if _left <= 0.0:
		_expire()
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tick_interval
	_burn_raiders()


## Raiders standing in the puddle, standing or downed: a body lying in acid
## is still in acid, and a downed raider that healed out of it should have
## had to be dragged out.
func _burn_raiders() -> void:
	var amount := damage_per_second * tick_interval
	var radius_sq := radius * radius
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_inside_tree():
				continue
			var to_body := body.global_position - global_position
			to_body.y = 0.0
			if to_body.length_squared() > radius_sq:
				continue
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				# No attacker: acid has nobody for thorns to hit back.
				health.take_damage(amount)


func _expire() -> void:
	if _expiring:
		return
	_expiring = true
	set_physics_process(false)
	_fade = create_tween()
	_fade.tween_property(_material, "albedo_color", Color(DISC_COLOR, 0.0), FADE_TIME)
	_fade.tween_callback(_release)


func _release() -> void:
	Pools.release(self)


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
