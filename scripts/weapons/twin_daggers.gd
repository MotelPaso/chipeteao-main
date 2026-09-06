extends WeaponBase
## Nyx's starting weapon: very fast single-target melee — quick stabs on
## the nearest enemy in short range. Each fire lands exactly one hit
## through the shared damage funnel. No held blades — every stab flashes
## a small pooled SlashArc crescent at the target, mirrored left/right on
## alternate hits so the double-dagger rhythm reads.

## Seconds one slash flash lasts (kept snappy for the fast cooldown).
@export var slash_time: float = 0.1
## Crescent radius of one dagger cut.
@export var slash_radius: float = 1.0
## Slash swipe tint (pale violet, matching the old blades' emission).
@export var slash_color: Color = Color(0.8, 0.65, 1.0)

## True when the NEXT stab is the left-hand cut (alternates per hit).
var _stab_left: bool = true


func fire(target: Node3D) -> void:
	var health := Health.find_in(target)
	if health != null:
		deal_damage(health)
	_play_slash(target)
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
