extends WeaponBase
## Aura (iteration 43): a standing ring of light around the carrier that
## damages every enemy inside it on each pulse. Knob mapping:
##   damage        — per pulse (through deal_damage)
##   cooldown      — pulse interval
##   attack_range  — ring radius (Long Reach + area tomes widen it)
## The visual is a translucent disc that breathes with the pulse.

@export var aura_color: Color = Color(1.0, 0.85, 0.4)
## Enemies farther than this above/below the carrier are unaffected.
@export var height_window: float = 2.2

## How fast the drawn disc chases the real radius, in "fraction closed per
## second" terms — used through the exponential form below so the smoothing
## reads the same at any physics tick rate.
const DISC_FOLLOW_RATE: float = 8.0

var _disc: MeshInstance3D = null
var _pulse_tween: Tween = null


func _ready() -> void:
	_disc = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.05
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(aura_color, 0.22)
	material.emission_enabled = true
	material.emission = aura_color
	material.emission_energy_multiplier = 0.9
	mesh.material = material
	_disc.mesh = mesh
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


func _physics_process(delta: float) -> void:
	var radius := reach()
	_disc.global_position = global_position + Vector3.DOWN * 1.0
	# Framerate-independent smoothing: a raw delta * rate lerp would close
	# at half the speed if physics_ticks_per_second were halved, showing a
	# small ring while the damage already covers the wide one.
	var follow := 1.0 - exp(-DISC_FOLLOW_RATE * delta)
	_disc.scale = _disc.scale.lerp(Vector3(radius, 1.0, radius), follow)
	super(delta)


## Ring radius: the damage area, the drawn disc and the pulse trigger all
## read this one number.
func reach() -> float:
	return attack_range * area_scale()


## The ring IS the hit area, so the pulse has to trigger on anything inside
## it. Leaving this at attack_range made the area-scaled outer band purely
## decorative: with a big area multiplier and every enemy in that band the
## aura simply never pulsed.
func targeting_range() -> float:
	return reach()


func fire(_target: Node3D) -> void:
	damage_all(enemies_in_disc(global_position, reach(), height_window))
	# Breath: the disc flares a touch on every pulse.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_disc.transparency = 0.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_disc, "transparency", 0.45, effective_cooldown() * 0.8)
