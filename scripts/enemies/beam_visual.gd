class_name BeamVisual
extends MeshInstance3D
## Segmento de rayo: una caja unitaria estirada entre dos puntos del mundo,
## sin sombreado y emisiva. Lo usan las líneas de aviso y los láseres
## (Sunspitter, barrido del Sarcognath). Es top_level: cuelga del enemigo y
## se libera con él, pero sus extremos son coordenadas globales. Solo es
## visual: el raycast, el impacto y el daño los resuelve quien lo usa.

var default_thickness: float = 0.1


## Crea un rayo oculto bajo `host` con `color`. Quien lo usa anima el grosor
## (la línea de aviso que engorda como cuenta regresiva) con span().
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


## Muestra el rayo de `from` a `to`; thickness < 0 usa default_thickness.
## Se llama cada frame mientras un extremo se mueve.
func span(from: Vector3, to: Vector3, thickness: float = -1.0) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		visible = false
		return
	visible = true
	var girth := default_thickness if thickness < 0.0 else thickness
	var direction := (to - from) / length
	# Los rayos son casi horizontales, pero safe_up cubre el caso colineal con
	# UP de Basis.looking_at (el mismo umbral que toda puntería del juego).
	var look := Basis.looking_at(direction, WeaponBase.safe_up(direction))
	global_transform = Transform3D(
			look * Basis.from_scale(Vector3(girth, girth, length)),
			(from + to) * 0.5)


func clear() -> void:
	visible = false
