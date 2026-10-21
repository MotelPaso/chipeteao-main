class_name XpGem
extends MagnetPickup
## XP gem dropped by enemies: the shared MagnetPickup chassis (idle
## spin/bob, sticky magnet homing, level-up vacuum, lifetime despawn,
## pooled release) plus the one thing that is gem-specific — collecting
## credits RunState.add_xp scaled by the COLLECTOR's XP multiplier.
## pool_reset also restores xp_value, which droppers scale per gem on top
## of the scene default. Live gems sit in LIVE_GROUP; the scene's separate
## persistent "xp_gems" group is what the perf probe counts.

## Group every live (dropped, uncollected) gem belongs to; the vacuum
## reaches gems through it. Distinct from the scene's persistent
## "xp_gems" group, which the perf probe counts.
const LIVE_GROUP: StringName = &"gems"

@export var xp_value: int = 1

var _default_xp_value: int = 1


func _ready() -> void:
	super()
	_default_xp_value = xp_value


func live_group() -> StringName:
	return LIVE_GROUP


func _reset_extra() -> void:
	xp_value = _default_xp_value


## XP is party-wide, but the COLLECTOR's XP multiplier (Tome of Wisdom)
## and the run-wide difficulty share scale the pickup (iteration 39).
func _on_collected(collector: Node3D) -> void:
	Sfx.play(&"gem_pickup")
	var multiplier := RunState.difficulty_xp_multiplier()
	var stats := PlayerStats.find_in(collector) if collector != null else null
	if stats != null:
		multiplier *= stats.xp_multiplier
	RunState.add_xp(maxi(roundi(float(xp_value) * multiplier), 1))
