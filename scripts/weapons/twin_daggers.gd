extends WeaponBase
## Nyx's starting weapon: very fast single-target melee — quick stabs on
## the nearest enemy in short range, alternating the left and right blade
## every hit. Each fire lands exactly one hit through the shared damage
## funnel; the matching blade mesh flicks at the target (cheap tween).

## Seconds one blade flick takes (lunge out plus recover).
@export var stab_time: float = 0.12
## How far a blade lunges from its rest position during a stab.
@export var stab_reach: float = 0.55

@onready var _left_pivot: Node3D = $LeftPivot
@onready var _right_pivot: Node3D = $RightPivot
@onready var _left_blade: Node3D = $LeftPivot/Blade
@onready var _right_blade: Node3D = $RightPivot/Blade

## True when the NEXT stab comes from the left blade (alternates per hit).
var _stab_left: bool = true
var _left_tween: Tween
var _right_tween: Tween
## Rest z of a blade inside its pivot, captured from the scene layout.
var _blade_rest_z: float = 0.0


func _ready() -> void:
	_blade_rest_z = _left_blade.position.z


func fire(target: Node3D) -> void:
	var health := Health.find_in(target)
	if health != null:
		deal_damage(health)
	if _stab_left:
		_left_tween = _play_stab(target, _left_pivot, _left_blade, _left_tween)
	else:
		_right_tween = _play_stab(target, _right_pivot, _right_blade, _right_tween)
	_stab_left = not _stab_left


## Flicks one blade at the target; returns the fresh tween so the caller
## can store it per side (a re-stab kills the previous flick mid-motion).
func _play_stab(target: Node3D, pivot: Node3D, blade: Node3D, active: Tween) -> Tween:
	if active != null and active.is_valid():
		active.kill()
	var aim := target.global_position - pivot.global_position
	aim.y = 0.0
	# Degenerate case (target directly above/below): stab where we face.
	if aim.length_squared() > 0.0001:
		pivot.look_at(pivot.global_position + aim, Vector3.UP)
	blade.position.z = _blade_rest_z
	var tween := create_tween()
	tween.tween_property(blade, "position:z", _blade_rest_z - stab_reach, stab_time * 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(blade, "position:z", _blade_rest_z, stab_time * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tween
