extends WeaponBase
## Nyx's starting weapon: very fast single-target melee — quick stabs on
## the nearest enemy in short range. Each stab lands exactly one hit
## through the shared damage funnel (a Tome of Multitude adds staggered
## follow-up stabs, never a second cut on the same frame). No held blades —
## every stab flashes a small pooled SlashArc crescent at the target,
## mirrored left/right on alternate hits so the double-dagger rhythm reads.

## Seconds one slash flash lasts (kept snappy for the fast cooldown).
@export var slash_time: float = 0.1
## Crescent radius of one dagger cut.
@export var slash_radius: float = 1.0
## Slash swipe tint (pale violet, matching the old blades' emission).
@export var slash_color: Color = Color(0.8, 0.65, 1.0)

## Seconds between the stabs a Tome of Multitude adds. Staggered, not
## simultaneous: this weapon is a rhythm of single cuts, and two stabs on
## the same body in the same frame read as one hit with a doubled number.
const EXTRA_STAB_STAGGER: float = 0.07
## The staggered chain has to end inside this fraction of one cooldown —
## with the daggers' very short cooldown this clamp is what keeps a big
## Multitude stack from queueing stabs into the next volley.
const STAB_CHAIN_WINDOW: float = 0.6

## True when the NEXT stab is the left-hand cut (alternates per hit).
var _stab_left: bool = true


func fire(target: Node3D) -> void:
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_STAB_STAGGER,
			effective_cooldown() * STAB_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	_stab(target)
	for i: int in range(1, count):
		# Pausable and stepped in physics: an extra stab must not land while
		# the upgrade UI holds the tree, and damage belongs on the same tick
		# the rest of the combat runs on.
		get_tree().create_timer(step * float(i), false, true).timeout \
				.connect(_restab)


## A follow-up stab from a Tome of Multitude. It picks its OWN target rather
## than carrying the volley's: the opening cut may have killed that one, and
## a long chain outlives the corpse (which frees itself a third of a second
## after it dies). Lands a beat after fire(), when this weapon may already
## have left the tree with a removed raider.
func _restab() -> void:
	if not is_inside_tree():
		return
	var target := acquire_target()
	if target != null:
		_stab(target)


## One stab through the shared damage funnel, plus its crescent.
func _stab(target: Node3D) -> void:
	var health := Health.find_in(target)
	if health != null:
		deal_damage(health)
	_play_slash(target)
	# Left/right alternates per stab, so the extras of one volley mirror each
	# other instead of stacking the same crescent on the same body.
	_stab_left = not _stab_left


## Mini crescent at the struck enemy, sweeping the opposite way on
## alternating hits (left/right dagger feel).
func _play_slash(target: Node3D) -> void:
	var slash := Pools.acquire_scene(Pools.SLASH_ARC_SCENE) as SlashArc
	if slash == null:
		return
	var aim := flat_dir_or(target.global_position - global_position,
			-global_transform.basis.z)
	slash.play(target.global_position + Vector3.UP * 0.3, aim, slash_radius,
			slash_color, 100.0, slash_time, _stab_left)
