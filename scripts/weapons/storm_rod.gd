extends WeaponBase
## Storm Rod (iteration 37): zaps the nearest foe, then the bolt forks to
## the closest not-yet-hit enemies in a chain. Every link goes through
## deal_damage (crit/lifesteal apply per link). The visual is a self-freeing
## emissive beam per link — no pooled projectile, the hit is instant.
##   damage       — per link
##   cooldown     — time between casts
##   attack_range — first-target acquisition range
##   chain_count  — extra links after the first hit (+1 chain card; the
##                  evolution adds three)

@export var chain_count: int = 2
## A link can fork to an enemy at most this far from the previous one.
@export var chain_range: float = 6.5
## Radius of one bolt segment; the length lives in the node's Y scale so a
## single mesh can serve every link.
@export var beam_radius: float = 0.05
## Seconds a segment takes to thin out and vanish.
@export var beam_fade_time: float = 0.22
## Fraction of its radius a fading segment shrinks to.
@export var beam_fade_scale: float = 0.3
## Below this span a link is not worth drawing (two bodies on one spot).
@export var min_beam_length: float = 0.05

const BEAM_COLOR := Color(0.55, 0.75, 1.0)
## Sides of the bolt cylinder: it is a thin streak seen for a fifth of a
## second, so six is plenty.
const BEAM_SEGMENTS: int = 6

## Seconds between the bolts a Tome of Multitude adds. Staggered rather
## than simultaneous: two casts in the same frame would fork through the
## same nearest bodies and draw both chains on top of each other.
const EXTRA_BOLT_STAGGER: float = 0.1
## The whole staggered chain has to end inside this fraction of one
## cooldown, or the last bolt of a volley would land after the next cast.
const BOLT_CHAIN_WINDOW: float = 0.6

## One mesh and one material for every bolt ever drawn. Building a
## CylinderMesh plus a StandardMaterial3D per link (six links a cast, several
## casts a second once Tempest Crown lands) was the per-spawn resource churn
## the pools exist to avoid — and it never showed up in Pools.stats_line().
var _beam_mesh: CylinderMesh = null


func _ready() -> void:
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = beam_radius
	_beam_mesh.bottom_radius = beam_radius
	# Unit height: _spawn_beam encodes the real span in scale.y.
	_beam_mesh.height = 1.0
	_beam_mesh.radial_segments = BEAM_SEGMENTS
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = BEAM_COLOR
	material.emission_enabled = true
	material.emission = BEAM_COLOR
	material.emission_energy_multiplier = 2.4
	_beam_mesh.material = material


func fire(target: Node3D) -> void:
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_BOLT_STAGGER,
			effective_cooldown() * BOLT_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	_zap(target)
	for i: int in range(1, count):
		# Pausable and stepped in physics: an extra bolt must not fire while
		# the upgrade UI holds the tree, and damage belongs on the same tick
		# the rest of the combat runs on.
		get_tree().create_timer(step * float(i), false, true).timeout \
				.connect(_refork)


## A follow-up bolt from a Tome of Multitude. It picks its OWN first target
## instead of reusing the one the volley started on: by now the opening
## chain may have killed it, and re-acquiring is what makes the extra bolt
## fork through a different part of the horde. Lands a beat after fire(),
## when this weapon may already have left the tree with a removed raider.
func _refork() -> void:
	if not is_inside_tree():
		return
	var target := acquire_target()
	if target != null:
		_zap(target)


## One bolt: the first strike plus its chain_count forks.
func _zap(target: Node3D) -> void:
	var previous_point := global_position + Vector3.UP * 1.1
	var current := target
	var hit_ids: Dictionary[int, bool] = {}
	var links := 1 + chain_count
	var fork_range := chain_range * area_scale()
	for link in links:
		if current == null:
			return
		hit_ids[current.get_instance_id()] = true
		var strike_point := current.global_position + Vector3.UP * 0.8
		_spawn_beam(previous_point, strike_point)
		var health := Health.find_in(current)
		if health != null and not health.is_dead:
			deal_damage(health)
		previous_point = strike_point
		current = _next_link(current, hit_ids, fork_range)


## Nearest living enemy to `from` within `fork_range` not already struck.
func _next_link(from: Node3D, hit_ids: Dictionary[int, bool],
		fork_range: float) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist_sq := fork_range * fork_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if hit_ids.has(body.get_instance_id()):
			continue
		var dist_sq := from.global_position.distance_squared_to(body.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = body
	return nearest


## One emissive bolt segment between two points that flashes and fades out
## on its own. The span rides in scale.y so every segment can share the one
## unit-height mesh built in _ready; the fade runs on the node's own
## transparency, because the material is shared and animating its alpha
## would dim every other live bolt with it.
func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var length := span.length()
	if length < min_beam_length:
		return
	var beam := spawn_fx_mesh(_beam_mesh)
	beam.global_position = (from + to) * 0.5
	# Cylinder axis is Y: aim -Z at the far point, then fold Y onto it (the
	# same degenerate-up guard the skirmisher's bolt aim uses).
	var direction := span / length
	beam.look_at(to, safe_up(direction))
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(1.0, length, 1.0)
	beam.transparency = 0.0
	var tween := beam.create_tween()
	tween.tween_property(beam, "transparency", 1.0, beam_fade_time)
	tween.parallel().tween_property(beam, "scale",
			Vector3(beam_fade_scale, length, beam_fade_scale), beam_fade_time)
	tween.tween_callback(beam.queue_free)
