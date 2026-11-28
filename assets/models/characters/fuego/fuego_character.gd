extends Node3D

var _ap: AnimationPlayer = null
var _player: CharacterBody3D = null
var _current_anim: String = ""

func _ready() -> void:
	_ap = find_child("AnimationPlayer", true, false)
	if _ap:
		for anim_name in ["idle", "run"]:
			if _ap.has_animation(anim_name):
				var anim := _ap.get_animation(anim_name)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
		if _ap.has_animation("idle"):
			_play_anim("idle", 1.0)

	# Buscar al CharacterBody3D (el Player) en los nodos padres
	var p: Node = get_parent()
	while p != null:
		if p is CharacterBody3D:
			_player = p as CharacterBody3D
			break
		p = p.get_parent()

func _process(delta: float) -> void:
	if _ap == null:
		return

	var is_moving := false
	var speed := 0.0

	if _player != null:
		var horizontal_velocity := Vector2(_player.velocity.x, _player.velocity.z)
		speed = horizontal_velocity.length()
		is_moving = speed > 0.2

		# Si se está moviendo, rotar suavemente hacia la dirección del movimiento
		if is_moving:
			var local_vel := _player.global_transform.basis.inverse() * _player.velocity
			var target_rot := atan2(-local_vel.x, -local_vel.z)
			rotation.y = lerp_angle(rotation.y, target_rot, 14.0 * delta)

	if is_moving:
		_play_anim("run", clampf(speed / 4.5, 0.7, 1.8))
	else:
		_play_anim("idle", 1.0)

func _play_anim(anim_name: String, speed_scale: float) -> void:
	if not _ap.has_animation(anim_name):
		return
	if _current_anim != anim_name:
		_current_anim = anim_name
		_ap.play(anim_name, 0.2)
	_ap.speed_scale = speed_scale
