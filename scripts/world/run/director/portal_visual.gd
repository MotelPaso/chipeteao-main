class_name PortalVisual
extends Node3D
## Aspecto de un portal: un anillo que gira en el suelo, un pilar de luz
## que late, una luz y un círculo de piedras paradas con runas del color del
## portal sobre un anillo de losas (con dinteles en el de salida). Lo
## comparten ExitPortal.tscn, que ajusta estos valores en su nodo Visual, y
## PortalShrine.tscn, que usa los de este script. El portal llama a build()
## desde su _ready con el radio de su anillo y su color.
##
## Las piedras tienen colisión (un cuerpo aparte, `FrameStones`) y quedan
## más afuera que el punto donde aparece quien llega por un portal de pareja.

@export_group("Anillo")
## Medio grosor (metros) del tubo del anillo.
@export var ring_half_thickness: float = 0.12
## Altura (metros) del anillo sobre el suelo.
@export var ring_height: float = 0.06
## Opacidad del anillo (0-1).
@export var ring_alpha: float = 0.9
## Giro del anillo (radianes por segundo).
@export var ring_spin: float = 0.8

@export_group("Pilar")
## Altura (metros) del pilar de luz; su base mide lo que el anillo.
@export var pillar_height: float = 6.0
## Radio (metros) de la punta del pilar.
@export var pillar_top_radius: float = 0.9
## Opacidad del pilar (0-1).
@export var pillar_alpha: float = 0.28
## Velocidad del latido del pilar en reposo (radianes por segundo).
@export var idle_pulse_speed: float = 3.0
## Cuánto crece el pilar en el latido (0.05 = 5 %).
@export var idle_pulse_amount: float = 0.05
## Ancho del pilar al empezar a recargar (0-1 del ancho normal); crece
## hasta 1 cuando el portal vuelve a estar listo.
@export var recharge_min_width: float = 0.3

@export_group("Brillo")
## Energía de la luz (multiplicador).
@export var light_energy: float = 1.8
## Alcance (metros) de la luz.
@export var light_range: float = 7.0
## Altura (metros) de la luz sobre el suelo.
@export var light_height: float = 1.5

@export_group("Marco de piedra")
## Piedras paradas alrededor del anillo (0 = sin marco).
@export_range(0, 16) var frame_stones: int = 6
## Metros entre el borde del anillo y el centro de las piedras. En un portal
## de pareja tiene que pasar su exit_margin más el ancho de un raider.
@export var frame_gap: float = 2.1
## Alto mínimo y máximo de cada piedra, en metros (bajo 10: la horda trepa 10).
@export var frame_height_min: float = 1.6
@export var frame_height_max: float = 2.2
## Ancho de cada piedra, en metros.
@export var frame_width: float = 0.6
## Con dinteles: une las piedras de a pares con una losa arriba.
@export var frame_lintels: bool = false
## Piedra, losas y musgo del marco.
@export var frame_stone_color: Color = Color(0.56, 0.57, 0.56)
@export var frame_paving_color: Color = Color(0.66, 0.65, 0.6)
@export var frame_moss_color: Color = Color(0.36, 0.5, 0.3)

## Progreso de la recarga (0-1) que el portal escribe cada frame;
## negativo = en reposo, con el latido.
var recharge_fraction: float = -1.0

var _ring: MeshInstance3D = null
var _pillar: MeshInstance3D = null
var _time: float = 0.0


## Construye el anillo, el pilar y la luz alrededor de `ring_radius`
## (metros) con el color del portal.
func build(ring_radius: float, color: Color) -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - ring_half_thickness
	torus.outer_radius = ring_radius + ring_half_thickness
	# Teselado explícito (el del motor es 64 x 32): 32 cortes mantienen
	# redondo el anillo y 8 lados bastan para el tubo.
	torus.rings = 32
	torus.ring_segments = 8
	_ring.mesh = torus
	_ring.position.y = ring_height
	_ring.material_override = _glow_material(color, ring_alpha, false)
	add_child(_ring)
	_pillar = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = pillar_top_radius
	mesh.bottom_radius = ring_radius
	mesh.height = pillar_height
	# Teselado explícito: un cono recto no necesita anillos en altura.
	mesh.radial_segments = 24
	mesh.rings = 1
	_pillar.mesh = mesh
	_pillar.position.y = pillar_height * 0.5
	_pillar.material_override = _glow_material(color, pillar_alpha, true)
	add_child(_pillar)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = light_energy
	light.omni_range = light_range
	light.position.y = light_height
	add_child(light)
	if frame_stones > 0:
		# Las piedras se apoyan en el suelo de su lugar: se arman cuando el
		# portal ya está en su sitio.
		_build_frame.call_deferred(ring_radius, color)


func _physics_process(delta: float) -> void:
	_time += delta
	if _ring != null:
		_ring.rotate_y(delta * ring_spin)
	if _pillar == null:
		return
	if recharge_fraction >= 0.0:
		# Recargando: el pilar se estrecha y vuelve a su ancho.
		var width := recharge_min_width + (1.0 - recharge_min_width) * recharge_fraction
		_pillar.scale = Vector3(width, 1.0, width)
	else:
		_pillar.scale = Vector3.ONE * (1.0 + sin(_time * idle_pulse_speed) * idle_pulse_amount)


## Material propio de esta instancia: así el latido y el color no pasan a
## otro portal. Sin sombreado solo se ve albedo_color (color y opacidad),
## así que no lleva emisión.
func _glow_material(color: Color, alpha: float, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color, alpha)
	return material


## El círculo de piedras con runas del color `color` alrededor de un anillo
## de `ring_radius` metros, sobre su anillo de losas, y sus colisiones.
func _build_frame(ring_radius: float, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 37, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(rng.seed))
	var glow := LowPolyMesh.new(int(rng.seed) + 1)
	var reach := ring_radius + frame_gap
	_frame_paving(stone, reach, rng)
	var body := StaticBody3D.new()
	body.name = "FrameStones"
	add_child(body)
	var tops: Array[Vector3] = []
	var turn := rng.randf() * TAU
	for index in frame_stones:
		var angle := turn + TAU * float(index) / float(frame_stones)
		var foot := Vector3(cos(angle), 0.0, sin(angle)) * reach
		foot.y = ShrineKit.ground_offset(self, foot)
		var tall := rng.randf_range(frame_height_min, frame_height_max)
		ShrineKit.rune_stone(stone, glow, foot, Vector3(0.0, foot.y, 0.0), tall, frame_width,
				frame_stone_color, frame_moss_color, color, rng)
		tops.append(foot + Vector3.UP * (tall - 0.2))
		var shape := CylinderShape3D.new()
		shape.radius = frame_width * 0.45
		shape.height = tall
		var holder := CollisionShape3D.new()
		holder.shape = shape
		holder.position = foot + Vector3.UP * tall * 0.5
		body.add_child(holder)
	if frame_lintels:
		for index in range(0, frame_stones - 1, 2):
			var a := tops[index]
			var b := tops[index + 1]
			var y := minf(a.y, b.y) + 0.22
			ShrineKit.strut(stone, Vector3(a.x, y, a.z), Vector3(b.x, y, b.z), 0.5,
					frame_stone_color.lightened(0.05))
	ShrineKit.hang(self, stone, glow)


## Un anillo de losas bajo las piedras, cada vértice apoyado en el suelo.
func _frame_paving(stone: LowPolyMesh, reach: float, rng: RandomNumberGenerator) -> void:
	var sides := 18
	var inner := reach - frame_width * 1.1
	var outer := reach + frame_width * 1.1
	for index in sides:
		var a := TAU * float(index) / float(sides)
		var b := TAU * float(index + 1) / float(sides)
		var corners := PackedVector3Array()
		for spot: Vector3 in [Vector3(cos(a) * outer, 0.0, sin(a) * outer),
				Vector3(cos(b) * outer, 0.0, sin(b) * outer), Vector3(cos(b) * inner, 0.0, sin(b) * inner),
				Vector3(cos(a) * inner, 0.0, sin(a) * inner)]:
			corners.append(spot + Vector3.UP * (ShrineKit.ground_offset(self, spot) + 0.04))
		var tone := frame_paving_color.lerp(frame_moss_color, 0.4) if rng.randf() < 0.3 \
				else frame_paving_color.darkened(rng.randf_range(0.0, 0.12))
		stone.plate(corners[0], corners[1], corners[2], corners[3], tone,
				(corners[0] + corners[2]) * 0.5 + Vector3.DOWN)
