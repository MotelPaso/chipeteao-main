class_name NecroStaff
extends WeaponBase
## Báculo de nigromante (iteration 56): a slow soul bolt that homes on the
## nearest enemy, and whatever it KILLS gets back up on your side.
##
## The corpse dies completely first — XP gem, run points, health orbs, the
## elite chest roll and the bestiary counter all pay out, because
## `Health.died` is synchronous and `EnemyBase._on_died` has already run by
## the time `deal_damage` returns. The possessed body is a fresh copy of
## the same scene spawned at the corpse, so the kill is a kill AND a
## servant, never one instead of the other.
##
## A possessed servant pays NOTHING when it expires: it already paid once
## as a corpse, and a weapon that could farm the same body twice would make
## every other weapon a rounding error.
##
## Only contact fighters can be possessed (EnemyBase.possessable): a
## possessed caster would need its bolts and beams to change sides too, and
## those are wired to the "player" group all the way down.

@export var possess_duration: float = 8.0
## Servants alive at once per carrier. The oldest expires early to make
## room — a cap that refused new ones instead would make the weapon feel
## broken at exactly the moment it is working.
@export var max_possessed: int = 12
@export var bolt_speed: float = 9.0
@export var bolt_lifetime: float = 2.5
@export var bolt_radius: float = 0.28
## Seconds between the extra bolts a Tome of Multitude adds. Staggered like
## every other multi-shot here: bolts fired on the same frame share one
## flight path and hit the same body twice.
@export var extra_bolt_stagger: float = 0.1

const BOLT_COLOR := Color(0.65, 0.35, 0.95)
## How close a bolt has to get to count as a hit.
const BOLT_HIT_RADIUS: float = 0.9
## Live servants, so the carrier's cap is readable from outside (the soak
## prints possessed=a/b off this).
const POSSESSED_GROUP: StringName = &"possessed"

var _bolt_mesh: SphereMesh = null
## One in-flight soul bolt. A record instead of a loose Dictionary: its
## `visual` crosses frames, and with fields the compiler catches a typo.
class SoulBolt extends RefCounted:
	var visual: MeshInstance3D = null
	var target: Node3D = null
	var left: float = 0.0

var _bolts: Array[SoulBolt] = []


func _ready() -> void:
	_bolt_mesh = SphereMesh.new()
	_bolt_mesh.radius = bolt_radius
	_bolt_mesh.height = bolt_radius * 2.0
	_bolt_mesh.radial_segments = 8
	_bolt_mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(BOLT_COLOR, 0.9)
	material.emission_enabled = true
	material.emission = BOLT_COLOR
	material.emission_energy_multiplier = 2.2
	_bolt_mesh.material = material


func fire(target: Node3D) -> void:
	var shots := effective_projectile_count()
	_launch(target)
	for i in range(1, shots):
		# Staggered, and each one re-acquires: by the time the third bolt
		# leaves, the first may have already killed what it was aimed at.
		var delay := extra_bolt_stagger * float(i)
		get_tree().create_timer(delay, false).timeout.connect(_launch_at_fresh_target)


func _launch_at_fresh_target() -> void:
	if not is_inside_tree():
		return
	_launch(acquire_target())


func _launch(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var bolt := SoulBolt.new()
	bolt.visual = spawn_fx_mesh(_bolt_mesh)
	bolt.visual.global_position = global_position + Vector3.UP * 1.0
	bolt.target = target
	bolt.left = bolt_lifetime
	_bolts.append(bolt)


func _physics_process(delta: float) -> void:
	super(delta)
	_tick_bolts(delta)


## Bolts home on their target and resolve on contact. Walked backwards so
## a bolt can be removed inside the loop, and every target is re-checked:
## the body can be freed mid-flight (something else killed it) or possessed
## by another bolt of ours.
func _tick_bolts(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var bolt := _bolts[i]
		bolt.left -= delta
		var target_gone := bolt.target == null or not is_instance_valid(bolt.target) \
				or not bolt.target.is_inside_tree()
		if bolt.left <= 0.0 or target_gone:
			_kill_bolt(i)
			continue
		var aim := bolt.target.global_position + Vector3.UP * 0.8
		var span := aim - bolt.visual.global_position
		var step := bolt_speed * delta
		if span.length() <= maxf(step, BOLT_HIT_RADIUS):
			_strike(bolt.target)
			_kill_bolt(i)
			continue
		bolt.visual.global_position += span.normalized() * step


## One bolt lands. The kill and the possession are two separate facts: the
## body dies normally (paying out everything it owes) and only THEN, if it
## actually died to this hit and is allowed to be raised, does a servant
## get up in its place.
func _strike(target: Node3D) -> void:
	var health := Health.find_in(target)
	if health == null or health.is_dead:
		return
	var enemy := target as EnemyBase
	# Read BEFORE the blow: _on_died runs synchronously inside take_damage
	# and leaves the corpse mid-teardown, but its exports and transform are
	# still readable for the 0.3 s its death tween lasts.
	var scene_path := enemy.get_scene_file_path() if enemy != null else ""
	var at := target.global_position
	var can_raise := enemy != null and enemy.possessable and not scene_path.is_empty()
	if deal_damage(health) <= 0.0:
		return
	if not health.is_dead or not can_raise:
		return
	_raise_servant(scene_path, at, enemy)


func _raise_servant(scene_path: String, at: Vector3, corpse: EnemyBase) -> void:
	var carrier := carrier_player()
	if carrier == null:
		return
	_trim_servants()
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var servant := scene.instantiate() as EnemyBase
	if servant == null:
		return
	# Carried over from the corpse so a possessed tank still hits like a
	# tank; everything else is the scene's own defaults, which is what
	# keeps this from having to know each enemy's exports.
	var contact: Variant = corpse.get("contact_damage")
	if contact != null:
		servant.set("contact_damage", contact)
	servant.move_speed = corpse.move_speed
	RunRoot.stage_parent(get_tree()).add_child(servant)
	servant.global_position = at
	servant.make_possessed(carrier, possess_duration * duration_scale())


## The oldest servant goes when the cap is full. Oldest and not newest:
## the one you just raised is the one standing where the fight is.
func _trim_servants() -> void:
	var mine: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(POSSESSED_GROUP):
		var servant := node as EnemyBase
		if servant != null and servant.possession_carrier() == carrier_player():
			mine.append(servant)
	while mine.size() >= max_possessed:
		var oldest := mine.pop_front() as EnemyBase
		if oldest != null and is_instance_valid(oldest):
			oldest.end_possession()


## Servants this carrier currently holds, and the cap — the soak prints
## both as possessed=a/b, and a>b would mean the cap is not being kept.
func possessed_count() -> int:
	var mine := 0
	for node: Node in get_tree().get_nodes_in_group(POSSESSED_GROUP):
		var servant := node as EnemyBase
		if servant != null and servant.possession_carrier() == carrier_player():
			mine += 1
	return mine


func _kill_bolt(index: int) -> void:
	var bolt := _bolts[index]
	if bolt.visual != null and is_instance_valid(bolt.visual):
		bolt.visual.queue_free()
	_bolts.remove_at(index)


## The bolts are parented to the arena, not to this weapon, so they survive
## the raider dying mid-flight — but they must not survive the WEAPON being
## freed (evolution, run teardown) with nobody left to tick them.
func _exit_tree() -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		_kill_bolt(i)
