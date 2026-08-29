class_name Telegraph
extends RefCounted
## Ground-telegraph factory: a flat emissive disc that grows from its
## center to full radius over the wind-up (the fill level reads as a
## countdown) while its glow ramps up, then fades and frees itself.
## Purely visual — attack timing and damage stay in the caller — so a
## missing scene root can never break combat logic.


static func spawn_disc(host: Node, center: Vector3, radius: float,
		duration: float, color: Color) -> void:
	var scene_root := host.get_tree().current_scene
	if scene_root == null:
		return
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.05
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.45)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	disc.material_override = material
	# Parented to the scene root so the cue survives its caster dying
	# mid-telegraph; the tween is bound to the disc and frees it.
	scene_root.add_child(disc)
	disc.global_position = center + Vector3.UP * 0.04
	disc.scale = Vector3(0.2, 1.0, 0.2)
	var tween := disc.create_tween()
	tween.set_parallel(true)
	tween.tween_property(disc, "scale", Vector3.ONE, duration)
	tween.tween_property(material, "emission_energy_multiplier", 2.6, duration)
	tween.chain().tween_property(material, "albedo_color:a", 0.0, 0.15)
	tween.chain().tween_callback(disc.queue_free)
