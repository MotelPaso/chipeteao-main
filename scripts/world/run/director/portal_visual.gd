class_name PortalVisual
extends Node3D
## Aspecto de un portal: un anillo que gira en el suelo, un pilar de luz
## que late y una luz. Lo comparten ExitPortal.tscn y PortalShrine.tscn;
## cada una ajusta estos valores en su nodo Visual. El portal llama a
## build() desde su _ready con el radio de su anillo y su color.

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
## Brillo de la emisión del anillo y el pilar.
@export var emission_energy: float = 1.4
## Energía de la luz.
@export var light_energy: float = 1.8
## Alcance (metros) de la luz.
@export var light_range: float = 7.0
## Altura (metros) de la luz sobre el suelo.
@export var light_height: float = 1.5

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
## otro portal.
func _glow_material(color: Color, alpha: float, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material
