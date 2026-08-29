extends WeaponBase
## Bramble's starting weapon: cracks a thorned lash along a narrow strip
## from the wielder toward the target, damaging every "enemies"-group body
## inside it and briefly slowing the EnemyBase ones (refresh, not stack —
## see EnemyBase.apply_slow). The visual is a stretched thin mesh flashed
## along the strip for one crack.

## Full width of the lash strip; the strip's length is attack_range. Both
## scale with area tomes.
@export var strip_width: float = 1.2
## Percent of move speed removed from lashed enemies (30 = they keep 70%).
@export var slow_percent: float = 30.0
@export var slow_duration: float = 1.5
@export var crack_time: float = 0.16

var _crack_mesh: BoxMesh


func _ready() -> void:
	# One shared 1m box for every crack; per-instance scale stretches it to
	# the strip and MeshInstance3D.transparency fades it out.
	_crack_mesh = BoxMesh.new()
	_crack_mesh.size = Vector3(0.14, 0.14, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.45, 0.72, 0.3)
	material.emission_enabled = true
	material.emission = Color(0.4, 0.8, 0.25)
	material.emission_energy_multiplier = 2.0
	_crack_mesh.material = material


func fire(target: Node3D) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	# Degenerate case (target directly above/below): lash where we face.
	var lash_dir := to_target.normalized() if to_target.length_squared() > 0.0001 \
			else -global_transform.basis.z
	lash_dir.y = 0.0
	lash_dir = lash_dir.normalized() if lash_dir.length_squared() > 0.0001 else Vector3.FORWARD
	var length := attack_range * area_scale()
	_lash_strip(lash_dir, length)
	_spawn_crack_visual(lash_dir, length)


## Hits every enemy whose flat position falls inside the strip: within
## `length` along lash_dir and half the (area-scaled) width off its axis.
func _lash_strip(lash_dir: Vector3, length: float) -> void:
	var half_width := strip_width * 0.5 * area_scale()
	var slow_mult := 1.0 - clampf(slow_percent, 0.0, 95.0) / 100.0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_enemy := body.global_position - global_position
		to_enemy.y = 0.0
		var along := to_enemy.dot(lash_dir)
		if along < 0.0 or along > length:
			continue
		if (to_enemy - lash_dir * along).length() > half_width:
			continue
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		if enemy != null:
			enemy.apply_slow(slow_mult, slow_duration)


func _spawn_crack_visual(lash_dir: Vector3, length: float) -> void:
	var crack := MeshInstance3D.new()
	crack.mesh = _crack_mesh
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_tree().root
	# Scene-root parent so the crack stays put while the player moves on.
	parent_node.add_child(crack)
	var mid := global_position + lash_dir * length * 0.5 + Vector3.UP * 0.9
	crack.global_transform = Transform3D(Basis.looking_at(lash_dir, Vector3.UP), mid)
	crack.scale = Vector3(0.4, 0.4, length)
	var tween := crack.create_tween()
	tween.set_parallel(true)
	tween.tween_property(crack, "scale:x", 1.0, crack_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(crack, "transparency", 1.0, crack_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(crack.queue_free)
