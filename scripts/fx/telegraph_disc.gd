class_name TelegraphDisc
extends MeshInstance3D
## Pooled ground-telegraph disc: the center-out fill/glow-ramp/fade cue the
## old Telegraph factory built from scratch per cast, now reused through
## Pools. The unit-radius cylinder is scaled by the requested radius, so
## the animation reads exactly like the old radius-sized mesh growing from
## scale 0.2 to 1. The override material is local-to-scene, so every pooled
## instance tweens its own alpha/emission copy.

var _tween: Tween = null


## Pooled-node contract: no stale grow/fade from the previous cast.
func pool_reset() -> void:
	_kill_tween()


## Plays one telegraph (same parameters and timings as the old
## Telegraph.spawn_disc); the node releases itself after the fade.
func show_disc(center: Vector3, radius: float, duration: float, color: Color) -> void:
	var material := material_override as StandardMaterial3D
	if material == null:
		# The node came out of the pool, so bailing without releasing would
		# strand it in the scene forever — the only exit here that used to
		# skip the pool contract.
		Pools.release(self)
		return
	material.albedo_color = Color(color.r, color.g, color.b, 0.45)
	material.emission = color
	material.emission_energy_multiplier = 1.2
	global_position = center + Vector3.UP * 0.04
	scale = Vector3(0.2 * radius, 1.0, 0.2 * radius)
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector3(radius, 1.0, radius), duration)
	_tween.tween_property(material, "emission_energy_multiplier", 2.6, duration)
	_tween.chain().tween_property(material, "albedo_color:a", 0.0, 0.15)
	_tween.chain().tween_callback(_on_disc_done)


func _on_disc_done() -> void:
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
