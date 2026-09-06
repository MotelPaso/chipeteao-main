extends WeaponBase
## Slime Trail ("Baba", iteration 43): the carrier leaves a line of caustic
## slime puddles behind them while moving; every enemy standing in a
## puddle takes a damage tick each tick_interval. No target needed — the
## weapon "fires" on its own cadence whenever the carrier has moved.
## Knob mapping onto the WeaponBase contract:
##   damage        — per tick (through deal_damage)
##   cooldown      — seconds between puddle drops while moving
##   attack_range  — unused (Long Reach still widens puddles via area)
## Puddles are SlimePuddle records ticked here (no pooled scene): the visual
## is a flat emissive disc built per puddle and faded out on expiry.

@export var puddle_radius: float = 1.4
## Seconds a puddle lasts (Tome of Lingering / "Thicker Slime" stretch it).
@export var puddle_life: float = 3.0
@export var tick_interval: float = 0.5
## Carrier must have moved at least this far since the last drop.
@export var min_drop_distance: float = 0.8
@export var slime_color: Color = Color(0.45, 0.95, 0.3)
## Enemies farther than this above/below the puddle are unaffected.
@export var height_window: float = 1.6
## How far above the carrier's feet the disc sits — just enough to clear
## the arena floor's top face without floating.
@export var puddle_ground_offset: float = 0.05

## Seconds a puddle takes to fade out once its life runs out.
const FADE_TIME: float = 0.3
## Seconds the drop animation takes to swell to full radius.
const GROW_TIME: float = 0.2
## Radius fraction a puddle starts at before swelling.
const GROW_FROM: float = 0.3
## Distance from the drop point to each puddle a Tome of Multitude adds, in
## puddle radii. Just over 1.0: the extras ring the main puddle and touch
## it, widening the trail into a smear the horde has to wade through,
## instead of stacking discs on one spot where they would be invisible and
## just tick the same enemies several times.
const EXTRA_PUDDLE_SPACING: float = 1.2


## One live slime puddle. A record instead of a loose Dictionary: the
## `visual` is a node crossing frames, and typed fields let the compiler
## catch a mistyped key that used to fail silently at runtime.
class SlimePuddle extends RefCounted:
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	var life_left: float = 0.0
	var tick_timer: float = 0.0
	var visual: MeshInstance3D = null


var _puddles: Array[SlimePuddle] = []
var _last_drop: Vector3 = Vector3.INF
var _drop_timer: float = 0.0
var _puddle_mesh: CylinderMesh = null


func _ready() -> void:
	_puddle_mesh = CylinderMesh.new()
	_puddle_mesh.top_radius = 1.0
	_puddle_mesh.bottom_radius = 1.0
	_puddle_mesh.height = 0.06
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(slime_color, 0.55)
	material.emission_enabled = true
	material.emission = slime_color
	material.emission_energy_multiplier = 0.8
	_puddle_mesh.material = material


func _physics_process(delta: float) -> void:
	_drop_timer = maxf(_drop_timer - delta, 0.0)
	# The trail follows whatever rig carries this weapon — a pet leaves ITS
	# own trail instead of painting one under the player it follows.
	var carrier := carrier_node()
	if carrier != null and _drop_timer <= 0.0:
		var feet := carrier.global_position
		if _last_drop == Vector3.INF or feet.distance_to(_last_drop) >= min_drop_distance:
			_drop_timer = effective_cooldown()
			_last_drop = feet
			# This weapon never calls fire(), so the Tome of Multitude has to
			# be read here: it is the drop that is the attack.
			_drop_cluster(feet, maxi(effective_projectile_count(), 1))
	_tick_puddles(delta)


## Puddle visuals live under the scene root, not under this weapon, so
## nothing frees them when the weapon goes: drop them by hand. Freed on the
## spot rather than faded — the fade tween would have to be created on a
## node that may already be leaving the tree with us.
func _exit_tree() -> void:
	for puddle: SlimePuddle in _puddles:
		if puddle.visual != null and is_instance_valid(puddle.visual):
			puddle.visual.queue_free()
		puddle.visual = null
	_puddles.clear()


## One drop: the puddle under the carrier's feet plus, once a Tome of
## Multitude is in play, `count - 1` more evenly ringed around it at
## EXTRA_PUDDLE_SPACING radii, so the trail gets wider instead of thicker.
func _drop_cluster(center: Vector3, count: int) -> void:
	_spawn_puddle(center)
	var extras := count - 1
	if extras <= 0:
		return
	var offset := puddle_radius * area_scale() * EXTRA_PUDDLE_SPACING
	for i: int in extras:
		var angle := TAU * float(i) / float(extras)
		_spawn_puddle(center + Vector3(cos(angle), 0.0, sin(angle)) * offset)


func _spawn_puddle(center: Vector3) -> void:
	var radius := puddle_radius * area_scale()
	var visual := spawn_fx_mesh(_puddle_mesh)
	visual.global_position = center + Vector3.UP * puddle_ground_offset
	visual.scale = Vector3(radius * GROW_FROM, 1.0, radius * GROW_FROM)
	var grow := visual.create_tween()
	grow.tween_property(visual, "scale", Vector3(radius, 1.0, radius), GROW_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var puddle := SlimePuddle.new()
	puddle.center = center
	puddle.radius = radius
	puddle.life_left = puddle_life * duration_scale()
	puddle.tick_timer = tick_interval * 0.5
	puddle.visual = visual
	_puddles.append(puddle)


func _tick_puddles(delta: float) -> void:
	for i in range(_puddles.size() - 1, -1, -1):
		var puddle := _puddles[i]
		puddle.life_left -= delta
		puddle.tick_timer -= delta
		if puddle.tick_timer <= 0.0:
			puddle.tick_timer = tick_interval
			_pulse(puddle)
		if puddle.life_left <= 0.0:
			_expire(puddle)
			_puddles.remove_at(i)


func _pulse(puddle: SlimePuddle) -> void:
	damage_all(enemies_in_disc(puddle.center, puddle.radius, height_window))


func _expire(puddle: SlimePuddle) -> void:
	var visual := puddle.visual
	puddle.visual = null
	if visual == null or not is_instance_valid(visual):
		return
	var fade := visual.create_tween()
	fade.tween_property(visual, "transparency", 1.0, FADE_TIME)
	fade.tween_callback(visual.queue_free)


## Never targets: the trail drops wherever the carrier walks.
func acquire_target() -> Node3D:
	return null
