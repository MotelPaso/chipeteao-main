extends Node3D

var _ap: AnimationPlayer = null
var _anim_name: String = ""
var _player: CharacterBody3D = null

func _ready() -> void:
	_ap = find_child("AnimationPlayer", true, false)
	if _ap:
		var list = _ap.get_animation_list()
		if not list.is_empty():
			_anim_name = list[0]
			var anim := _ap.get_animation(_anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR

	# Buscar al CharacterBody3D (el Player) en los nodos padres
	var p: Node = get_parent()
	while p != null:
		if p is CharacterBody3D:
			_player = p as CharacterBody3D
			break
		p = p.get_parent()

func _process(delta: float) -> void:
	if _ap == null or _anim_name.is_empty():
		return

	var is_moving := false
	var speed := 0.0

	if _player != null:
		var horizontal_velocity := Vector2(_player.velocity.x, _player.velocity.z)
		speed = horizontal_velocity.length()
		is_moving = speed > 0.2

		# Si se está moviendo, girar el cuerpo hacia la dirección del movimiento
		if is_moving:
			var local_vel := _player.global_transform.basis.inverse() * _player.velocity
			var target_rot := atan2(-local_vel.x, -local_vel.z)
			rotation.y = lerp_angle(rotation.y, target_rot, 14.0 * delta)

	if is_moving:
		if not _ap.is_playing():
			_ap.play(_anim_name)
		_ap.speed_scale = clampf(speed / 4.5, 0.7, 1.8)
	else:
		if _ap.is_playing():
			_ap.stop()
			_ap.seek(0.0, true)
