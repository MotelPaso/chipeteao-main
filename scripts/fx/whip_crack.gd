class_name WhipCrack
extends Node3D
## Visual del latigazo del Látigo de espinas, del pool: una franja verde
## plana que se afina, se estira por el carril de golpe y vuelve, más una
## ráfaga de partículas de espinas a lo largo de la franja. La malla y el
## material de la franja se construyen una vez por instancia; el material de
## proceso de las partículas es local a la escena, así cada instancia puede
## ajustar su caja de emisión al largo del latigazo.

## Ancho de la franja en la mano (se afina hacia la punta).
const BASE_WIDTH: float = 0.26
const TIP_WIDTH: float = 0.05
const EXTEND_TIME: float = 0.07
const SNAP_TIME: float = 0.13

@onready var _strip: MeshInstance3D = $Strip
@onready var _thorns: GPUParticles3D = $Thorns

var _material: StandardMaterial3D = null
var _tween: Tween = null


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_strip.material_override = _material
	_strip.mesh = _build_strip()


## Contrato del pool: mata un latigazo viejo para que el reuso empiece limpio.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_strip.transparency = 0.0
	_thorns.emitting = false


## Restalla el látigo desde `from` por `direction` (plana) durante `length`
## metros: extensión rápida, ráfaga breve de espinas por la franja y retroceso.
func play(from: Vector3, direction: Vector3, length: float, color: Color) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), from)
	_material.albedo_color = color
	_strip.transparency = 0.0
	_strip.scale = Vector3(1.0, 1.0, 0.1)
	var thorn_material := _thorns.process_material as ParticleProcessMaterial
	if thorn_material != null:
		# Espinas por toda la franja: caja centrada a mitad del latigazo.
		thorn_material.emission_box_extents = Vector3(0.25, 0.15, length * 0.5)
	_thorns.position = Vector3(0.0, 0.0, -length * 0.5)
	_thorns.restart()
	_tween = create_tween()
	_tween.tween_property(_strip, "scale:z", length, EXTEND_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# chain() + parallel(), NO set_parallel(true): set_parallel hace que los
	# tweeners siguientes corran JUNTO con el anterior, y el retroceso
	# competiría con la extensión desde el mismo valor inicial.
	_tween.chain().tween_property(_strip, "scale:z", length * 0.2, SNAP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_strip, "transparency", 1.0, SNAP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Espera lo suficiente para que terminen las espinas antes de volver al pool.
	_tween.chain().tween_interval(0.4)
	_tween.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)


## Franja plana que se afina en el plano XZ, del origen a z = -1 (largo
## unitario; play() estira scale.z al largo del latigazo).
func _build_strip() -> ArrayMesh:
	const SEGMENTS: int = 6
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for i: int in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var half_width := lerpf(BASE_WIDTH, TIP_WIDTH, t) * 0.5
		vertices.append(Vector3(-half_width, 0.0, -t))
		vertices.append(Vector3(half_width, 0.0, -t))
		var alpha := lerpf(0.8, 0.3, t)
		colors.append(Color(1, 1, 1, alpha))
		colors.append(Color(1, 1, 1, alpha))
	return FxMesh.strip(vertices, colors)
