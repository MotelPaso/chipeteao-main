extends WeaponBase
## Kamehameha (iteration 43): a long-cooldown energy beam blasted toward
## the nearest enemy, hitting EVERY enemy inside a long, wide lane for
## heavy damage. Knob mapping:
##   damage        — per enemy caught in the beam (through deal_damage)
##   cooldown      — charge time between beams (long by design)
##   attack_range  — targeting reach; the beam itself is beam_length long
## Visual: a glowing cylinder laid along the lane that flares and fades,
## plus a shake and a short hit-stop on release.

@export var beam_length: float = 18.0
@export var beam_width: float = 2.4
@export var beam_color: Color = Color(0.45, 0.75, 1.0)
@export var flash_time: float = 0.45
@export var muzzle_height: float = 1.1

## The beam borrows the boss roar until the sfx catalog grows its own beam
## id; trimmed hard because that stinger is mixed for a once-a-run entrance
## and this weapon fires it every few seconds.
const BEAM_VOLUME_DB: float = -12.0

## Seconds between the beams a Tome of Multitude adds. Wider than the melee
## staggers on purpose: each blast is a heavy, readable event, and two of
## them overlapping in the same lane would just be one thicker beam.
const EXTRA_BEAM_STAGGER: float = 0.12
## Yaw between neighboring beams. The lane is long, so a narrow fan already
## separates the far ends by several meters.
const EXTRA_BEAM_FAN_DEG: float = 14.0
## The whole staggered chain has to end inside this fraction of one
## cooldown; with this weapon's long charge the clamp rarely bites, but a
## haste-stacked build would otherwise still be firing when it recharges.
const BEAM_CHAIN_WINDOW: float = 0.6

var _beam_mesh: CylinderMesh = null


func _ready() -> void:
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = 1.0
	_beam_mesh.bottom_radius = 1.0
	_beam_mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(beam_color, 0.85)
	material.emission_enabled = true
	material.emission = beam_color
	material.emission_energy_multiplier = 2.5
	_beam_mesh.material = material


func fire(target: Node3D) -> void:
	var origin := global_position + Vector3.UP * muzzle_height
	var center_dir := flat_dir_or(target.global_position + Vector3.UP * 0.8 - origin,
			-global_transform.basis.z)
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_BEAM_STAGGER,
			effective_cooldown() * BEAM_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_BEAM_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		var beam_dir := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			_blast(beam_dir)
		else:
			# Pausable and stepped in physics: an extra beam must not fire
			# while the upgrade UI holds the tree, and damage belongs on the
			# same tick the rest of the combat runs on.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_blast.bind(beam_dir))
	# Feedback belongs to the shot, not to the visual helper: a beam that
	# stopped calling _play_beam would otherwise go silent unnoticed. One
	# roar and one shake per volley, however many beams fan out — this
	# stinger is already trimmed hard for a once-every-few-seconds cast.
	Sfx.play(&"boss_roar_2", BEAM_VOLUME_DB)
	Juice.shake(0.2, 0.35)


## One beam down `direction`. The staggered extras land here a beat later,
## when this weapon may already have left the tree with a removed raider.
func _blast(direction: Vector3) -> void:
	if not is_inside_tree():
		return
	var origin := global_position + Vector3.UP * muzzle_height
	var length := beam_length * area_scale()
	var half_width := beam_width * 0.5 * area_scale()
	var hits := 0
	# The lane is measured from the body, not the muzzle: the beam sweeps
	# the ground line the player is standing on.
	for body: Node3D in enemies_in_lane(global_position, direction, length, half_width):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
			hits += 1
	_play_beam(origin, direction, length, half_width)
	if hits > 0:
		Juice.hit_stop(0.1, 0.05)


func _play_beam(origin: Vector3, direction: Vector3, length: float, half_width: float) -> void:
	var beam := spawn_fx_mesh(_beam_mesh)
	# Cylinder axis is Y: lay it along the lane, centered halfway out.
	beam.global_position = origin + direction * length * 0.5
	beam.look_at(beam.global_position + direction, safe_up(direction))
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(half_width * 0.3, length, half_width * 0.3)
	var tween := beam.create_tween()
	tween.set_parallel(true)
	tween.tween_property(beam, "scale", Vector3(half_width, length, half_width), flash_time * 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(beam, "transparency", 1.0, flash_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(beam.queue_free)
