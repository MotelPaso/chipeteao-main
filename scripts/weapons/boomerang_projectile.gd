class_name BoomerangProjectile
extends Area3D
## Otto's spinning blade: flies out to a fixed turn point, then swings back
## and chases the (moving) player until caught. Damages each enemy at most
## once per leg — the per-leg hit set clears at the turn, and a body the
## blade passes through re-enters the hitbox on the way back for its second
## hit. Frees on catch, on a lost player, or after max_lifetime.

@export var speed: float = 14.0
## Radians/sec of the purely visual spin on the Spinner rig.
@export var spin_speed: float = 14.0
## Distance to the player's catch point that counts as caught.
@export var catch_radius: float = 1.0
## Hard lifetime cap so a stranded blade can never linger forever.
@export var max_lifetime: float = 8.0
## Height above the player's origin the return leg homes to.
@export var catch_height: float = 0.9

var _source: WeaponBase = null
var _out_point: Vector3 = Vector3.ZERO
var _returning: bool = false
var _life_left: float = 0.0
## Instance ids damaged on the CURRENT leg (cleared at the turn point).
var _hit_ids_this_leg: Dictionary[int, bool] = {}

@onready var _spinner: Node3D = $Spinner


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_life_left = max_lifetime


## Called by the firing weapon right after parenting the blade: sets the
## throw origin and the point where the out leg turns around.
func launch(source: WeaponBase, from: Vector3, direction: Vector3, distance: float) -> void:
	_source = source
	global_position = from
	_out_point = from + direction * distance


func _physics_process(delta: float) -> void:
	_spinner.rotate_y(spin_speed * delta)
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()
		return
	var step := speed * delta
	if not _returning:
		var to_out := _out_point - global_position
		if to_out.length() <= step:
			global_position = _out_point
			_returning = true
			_hit_ids_this_leg.clear()
		else:
			global_position += to_out.normalized() * step
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		queue_free()
		return
	var to_catch := player.global_position + Vector3.UP * catch_height - global_position
	if to_catch.length() <= maxf(step, catch_radius):
		queue_free()
	else:
		global_position += to_catch.normalized() * step


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemies"):
		return
	var body_id := body.get_instance_id()
	if _hit_ids_this_leg.has(body_id):
		return
	_hit_ids_this_leg[body_id] = true
	var health := Health.find_in(body)
	if health != null and _source != null and is_instance_valid(_source):
		_source.deal_damage(health)
