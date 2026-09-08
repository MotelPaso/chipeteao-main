class_name BeltBolt
extends WeaponBase
## The Cinturón eléctrico's damage arm (iteration 56). It is a WeaponBase
## purely to borrow `deal_damage`: crit, lifesteal and the on-hit/on-kill
## item hooks all come free that way, and an item that rolled its own
## damage would be the one source in the game where a crit could not land.
##
## It is a child of the ITEM BAG, never of the Player's "Weapons" mount.
## Everything that enumerates weapons — the HUD loadout strip, the
## five-weapon cap, the level-up pool — walks that mount, so a bolt parked
## there would show up as a weapon the raider never picked and would count
## against the cap.
##
## It never fires itself: `fire()` is empty and processing is off. The bag
## calls `zap_chain()` when the raider dashes, which is the whole trigger.

## Damage of the first hit, before copies. Each further copy adds 35%.
@export var belt_damage: float = 25.0
@export var damage_per_extra_copy: float = 0.35
## Bounces past the first target: 2 + copies.
@export var base_bounces: int = 2
## How far the first target can be from the raider, and how far each bounce
## can reach from the last body hit.
@export var first_range: float = 10.0
@export var bounce_range: float = 8.0

## Beam look, mirroring storm_rod.gd's fade (that one's _spawn_beam is
## private, so the pattern is reproduced here rather than reached into).
@export var beam_radius: float = 0.05
@export var beam_fade_time: float = 0.22
@export var beam_fade_scale: float = 3.0
const BEAM_COLOR := Color(1.0, 0.95, 0.45)
## Below this a beam is a dot: skip it rather than draw a degenerate mesh.
const MIN_BEAM_LENGTH: float = 0.2
## Height the beam is drawn at, so it reads as chest-level lightning
## instead of a line scraping the floor.
const BEAM_HEIGHT: float = 0.9

var _beam_mesh: CylinderMesh = null


func _ready() -> void:
	# Never on its own clock: WeaponBase._physics_process would acquire a
	# target every cooldown and call fire(), and this weapon only exists to
	# be triggered by a dash.
	set_physics_process(false)
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = beam_radius
	_beam_mesh.bottom_radius = beam_radius
	_beam_mesh.height = 1.0
	_beam_mesh.radial_segments = 6
	_beam_mesh.rings = 0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = BEAM_COLOR
	material.emission_enabled = true
	material.emission = BEAM_COLOR
	material.emission_energy_multiplier = 2.4
	_beam_mesh.material = material


## WeaponBase contract. Deliberately empty: see the class comment.
func fire(_target: Node3D) -> void:
	pass


## THE trigger, called by ItemBag on every dash. Returns how many bodies
## the chain actually hit, so the bag can log one line per dash.
##
## `origin` is passed in because ItemBag extends Node and has NO transform:
## a Node3D child of it sits at the world origin, and reading this node's
## own position would aim every chain from the middle of the map.
func zap_chain(origin: Vector3, copies: int) -> int:
	var hits := 0
	var struck: Array[Node3D] = []
	var from := origin
	var reach := first_range
	var remaining := base_bounces + copies + 1
	damage = belt_damage * (1.0 + damage_per_extra_copy * float(maxi(copies - 1, 0)))
	while remaining > 0:
		var target := _nearest_unstruck(from, reach, struck)
		if target == null:
			break
		struck.append(target)
		_spawn_beam(from, target.global_position)
		var health := Health.find_in(target)
		if health != null and not health.is_dead:
			# Through deal_damage, so the belt crits, leeches and feeds the
			# kill hooks exactly like a real weapon.
			deal_damage(health)
			hits += 1
		from = target.global_position
		reach = bounce_range
		remaining -= 1
	return hits


## Nearest live enemy within `reach` of `from` that this chain has not hit
## yet. Group-based like every other targeting scan here, so possessed
## bodies (which leave the "enemies" group) are never zapped by the party.
func _nearest_unstruck(from: Vector3, reach: float, struck: Array[Node3D]) -> Node3D:
	var best: Node3D = null
	var best_distance := reach * reach
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree() or struck.has(body):
			continue
		var distance := from.distance_squared_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	return best


## One lightning segment, faded out and freed. Same shape as the Storm
## Rod's beam: cylinder axis is Y, so aim -Z at the far point and then fold
## Y onto it, with the shared degenerate-up guard.
func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var start := from + Vector3.UP * BEAM_HEIGHT
	var end := to + Vector3.UP * BEAM_HEIGHT
	var span := end - start
	var length := span.length()
	if length < MIN_BEAM_LENGTH:
		return
	var beam := spawn_fx_mesh(_beam_mesh)
	beam.global_position = (start + end) * 0.5
	var direction := span / length
	beam.look_at(end, safe_up(direction))
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(1.0, length, 1.0)
	beam.transparency = 0.0
	var tween := beam.create_tween()
	tween.tween_property(beam, "transparency", 1.0, beam_fade_time)
	tween.parallel().tween_property(beam, "scale",
			Vector3(beam_fade_scale, length, beam_fade_scale), beam_fade_time)
	tween.tween_callback(beam.queue_free)
