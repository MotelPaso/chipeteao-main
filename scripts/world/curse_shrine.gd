class_name CurseShrine
extends ChargeShrine
## Demonic altar (iteration 41; keeps the Curse name): charges exactly
## like a charge altar — proximity, surges, forfeits on leaving — but
## every completion also raises the RUN-WIDE difficulty for the rest of
## the run (RunState.add_difficulty): tougher spawns and bosses, more
## elites, bigger hordes. In return the boon is larger, difficulty XP
## flows, bosses drop extra chests (BossBase reads RunState.demonic_uses)
## and Demon Blood copies enlarge every part of the bargain.

## Difficulty added per use, as a fraction (0.15 = +15% HP/damage).
@export var difficulty_per_use: float = 0.15
## Demon Blood: each copy held by the charger adds this fraction to the
## boon AND to the difficulty step (the bargain scales both ways).
@export var demon_blood_per_copy: float = 0.25


func _init() -> void:
	super()
	boon_scale = 1.6
	completed_text = "El obelisco bebe hondo: %s — la horda se pone más hambrienta"


func _accent_color() -> Color:
	return Color(1.0, 0.3, 0.25)


func _demon_blood_in_ring() -> int:
	return best_item_count_in_range("demon_blood")


## Demon Blood enlarges both halves of the bargain (boon and difficulty),
## so both read it from here instead of from a mutated export.
func _blood_scale() -> float:
	return 1.0 + demon_blood_per_copy * float(_demon_blood_in_ring())


func _effective_boon_scale() -> float:
	return boon_scale * _blood_scale()


func _grant_reward(keys: int) -> void:
	var blood_scale := _blood_scale()
	super(keys)
	var step := difficulty_per_use * blood_scale
	RunState.add_difficulty(step, "altars")
	RunState.demonic_uses += 1
	print("Demonic altar used: difficulty +%d%% (total +%d%%)" % [
			roundi(step * 100.0), roundi(RunState.difficulty_bonus * 100.0)])
