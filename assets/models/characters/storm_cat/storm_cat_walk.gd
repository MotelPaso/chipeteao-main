extends Node3D
## Procedural walk cycle for the storm cat, attached to the root of
## storm_cat_character.tscn. SealRig animates the whole body (lean, bob,
## squash); this only swings the legs and tail pivots baked into
## storm_cat.glb (Pivot_FrontL/FrontR/BackL/BackR/Tail, each pivoting at
## the hip / tail base). Legs move as diagonal pairs and the stride follows
## DISTANCE travelled, so the feet never skate: faster = quicker steps.
## Outside a player (select screen preview) there is no body, so the cat
## just idles with a gentle tail sway.

## Max leg swing (radians) at full speed.
@export var swing_angle: float = 0.65
## Stride phase advanced per metre travelled (higher = busier legs).
@export var stride_per_meter: float = 2.6
## Speed treated as "full" for the swing amplitude (matches SealRig).
@export var reference_speed: float = 6.0
@export var tail_sway_angle: float = 0.28
@export var tail_sway_speed: float = 2.4
## How fast the swing fades in/out, as fraction closed per second.
const AMP_DAMP_RATE: float = 12.0

const LEG_NAMES: Array[StringName] = [
	&"Pivot_FrontL", &"Pivot_BackR", &"Pivot_FrontR", &"Pivot_BackL",
]
## Diagonal pairs move together: FrontL+BackR, then FrontR+BackL half a
## cycle later.
const LEG_PHASES: Array[float] = [0.0, 0.0, PI, PI]

var _legs: Array[Node3D] = []
var _tail: Node3D = null
var _body: CharacterBody3D = null
var _phase: float = 0.0
var _amp: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	for leg_name: StringName in LEG_NAMES:
		var leg := find_child(leg_name, true, false) as Node3D
		if leg == null:
			push_warning("StormCatWalk: missing node '%s'" % leg_name)
		_legs.append(leg)
	_tail = find_child("Pivot_Tail", true, false) as Node3D
	var ancestor := get_parent()
	while ancestor != null and ancestor is not CharacterBody3D:
		ancestor = ancestor.get_parent()
	_body = ancestor as CharacterBody3D


func _process(delta: float) -> void:
	_time += delta
	var speed := 0.0
	if _body != null and _body.is_on_floor():
		speed = Vector2(_body.velocity.x, _body.velocity.z).length()
	_phase += speed * stride_per_meter * delta
	var target_amp := clampf(speed / reference_speed, 0.0, 1.3)
	_amp = lerpf(_amp, target_amp, 1.0 - exp(-AMP_DAMP_RATE * delta))
	for i in _legs.size():
		var leg := _legs[i]
		if leg != null:
			leg.rotation.x = sin(_phase + LEG_PHASES[i]) * swing_angle * _amp
	if _tail != null:
		_tail.rotation.y = sin(_time * tail_sway_speed) * tail_sway_angle
