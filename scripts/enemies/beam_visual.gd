class_name BeamVisual
extends MeshInstance3D
## Procedural beam segment: a unit box stretched between two world points,
## unshaded and emissive — the shared visual for aim-warning lines and
## live laser beams (Sunspitter, Sarcognath sweep). top_level, so it can
## be parented to a rotating/scaling enemy yet still span world-space
## endpoints exactly, and it frees together with its owner. Purely visual:
## raycasts, hit tests, and damage stay in the caller.

var default_thickness: float = 0.1


## Builds a hidden beam under `host` in `color`. Callers animate thickness
## (thin warning line thickening into a countdown) through span().
static func create(host: Node, color: Color, thickness: float) -> BeamVisual:
	var beam := BeamVisual.new()
	beam.top_level = true
	beam.visible = false
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	beam.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.8)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.2
	beam.material_override = material
	beam.default_thickness = thickness
	host.add_child(beam)
	return beam


## Shows the beam stretched from `from` to `to`; thickness < 0 uses the
## default. Call every frame while the beam tracks a moving endpoint.
func span(from: Vector3, to: Vector3, thickness: float = -1.0) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		visible = false
		return
	visible = true
	var girth := default_thickness if thickness < 0.0 else thickness
	var direction := (to - from) / length
	# Beams here are near-horizontal, but guard Basis.looking_at's
	# colinear-up case — one threshold for every aim in the game.
	var look := Basis.looking_at(direction, WeaponBase.safe_up(direction))
	global_transform = Transform3D(
			look * Basis.from_scale(Vector3(girth, girth, length)),
			(from + to) * 0.5)


func clear() -> void:
	visible = false
