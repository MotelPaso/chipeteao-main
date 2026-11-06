class_name SlashArc
extends MeshInstance3D
## Medialuna de tajo del pool (el arco de la Espada corta, los cortes de las
## Dagas gemelas): una medialuna plana construida por código (borde exterior
## lleno que se afina en punta en los dos extremos con alfa por vértice) que
## barre el arco del golpe y se desvanece. Un ArrayMesh y un material por
## instancia se construyen en _ready y se reusan; play() solo anima
## transformada y transparencia.

## Apertura de la medialuna en la malla, en grados; el giro de play() completa
## visualmente el resto del arco del ataque.
const ARC_DEG: float = 110.0
const SEGMENTS: int = 14
## Grosor máximo de la medialuna a mitad del arco (fracción del radio exterior unitario).
const THICKNESS: float = 0.55
## Alfa máximo por vértice (moderado, para que los telégrafos se lean a través).
const PEAK_ALPHA: float = 0.7

var _material: StandardMaterial3D = null
var _tween: Tween = null


func _ready() -> void:
	# cast_shadow vive en SlashArc.tscn con el resto de las reglas de
	# geometría de efectos (un efecto emisivo no proyecta sombra).
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _material
	mesh = _build_crescent()


## Contrato del pool: mata un barrido viejo para que el reuso empiece limpio.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	transparency = 0.0


## Hace pasar la medialuna por un arco centrado en `center_dir` (plano, XZ del
## mundo) en `at`, escalada a `radius`. sweep_deg es el giro total durante el
## tajo; mirror invierte el sentido para que los cortes alternos de las dagas
## se lean izquierda y derecha.
func play(at: Vector3, center_dir: Vector3, radius: float, color: Color,
		sweep_deg: float = 120.0, duration: float = 0.22, mirror: bool = false) -> void:
	_material.albedo_color = color
	var flat := Vector3(center_dir.x, 0.0, center_dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), at)
	scale = Vector3.ONE * radius
	var sweep := deg_to_rad(sweep_deg) * (-1.0 if mirror else 1.0)
	rotate_object_local(Vector3.UP, sweep * 0.5)
	transparency = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "rotation:y", rotation.y - sweep, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "transparency", 1.0, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)


## Medialuna plana en el plano XZ, centrada en -Z, de radio exterior unitario:
## una tira de triángulos cuyo radio interior sube hacia la mitad del arco
## (el afinado de la medialuna) con alfa por vértice que llega a cero en las
## dos puntas.
func _build_crescent() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var half := deg_to_rad(ARC_DEG) * 0.5
	for i: int in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var angle := -half + t * half * 2.0
		# Afinado en seno: grosor completo a mitad del arco, puntas en los extremos.
		var taper := sin(t * PI)
		var inner := 1.0 - THICKNESS * taper
		var dir := Vector3(sin(angle), 0.0, -cos(angle))
		vertices.append(dir * inner)
		vertices.append(dir)
		var alpha := PEAK_ALPHA * taper
		colors.append(Color(1, 1, 1, alpha * 0.35))  # borde interior, más suave
		colors.append(Color(1, 1, 1, alpha))
	return FxMesh.strip(vertices, colors)
