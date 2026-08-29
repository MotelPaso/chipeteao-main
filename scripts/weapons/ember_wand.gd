extends WeaponBase
## Ash's starting weapon: on cooldown, detonates a fire burst at the target's
## position, damaging every "enemies"-group body within burst_radius. The
## visual is a one-shot expanding emissive sphere (cheap, headless-safe).

@export var burst_radius: float = 2.5
@export var burst_effect_time: float = 0.35

var _burst_mesh: SphereMesh


func _ready() -> void:
	# One shared unit sphere for every burst; MeshInstance3D.transparency does
	# the per-instance fade so no material duplication is needed.
	_burst_mesh = SphereMesh.new()
	_burst_mesh.radius = 1.0
	_burst_mesh.height = 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.45, 0.15)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.1)
	material.emission_energy_multiplier = 2.5
	_burst_mesh.material = material


func fire(target: Node3D) -> void:
	var center := target.global_position
	# Area tomes grow the burst; the visual expands to the same radius.
	var radius := burst_radius * area_scale()
	var radius_sq := radius * radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if center.distance_squared_to(body.global_position) > radius_sq:
			continue
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
	_spawn_burst_visual(center, radius)


func _spawn_burst_visual(center: Vector3, radius: float) -> void:
	var burst := MeshInstance3D.new()
	burst.mesh = _burst_mesh
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_tree().root
	# Scene-root parent so the effect stays put even if this weapon is freed.
	parent_node.add_child(burst)
	burst.global_position = center + Vector3.UP * 0.9
	burst.scale = Vector3.ONE * 0.2
	var tween := burst.create_tween()
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector3.ONE * radius, burst_effect_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(burst, "transparency", 1.0, burst_effect_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(burst.queue_free)
