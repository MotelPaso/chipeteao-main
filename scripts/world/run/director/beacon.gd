extends Node3D
## Baliza de evento: pilar de luz alto y sin sombreado que se ve desde toda
## la arena, con un pulso suave para que se lea como invitación y no como
## amenaza. El WorldDirector la levanta sobre cada evento con el color de
## su fila de EVENT_LIBRARY. El tamaño del pilar (radios y `height` de su
## malla) y la luz están en los nodos Pillar y Light de Beacon.tscn; el
## pilar se apoya solo en el suelo según su altura. El color y la opacidad
## del material los pone este script (color, pillar_alpha).

## Color del pilar y de la luz; el director lo pone antes de añadirla.
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		if is_node_ready():
			_apply_color()
## Opacidad del pilar (0-1).
@export var pillar_alpha: float = 0.35

@export_group("Pulso")
## Ancho del pilar en lo más abierto del pulso (1 = sin cambio).
@export var pulse_width: float = 1.25
## Segundos que tarda cada mitad del pulso (abrir o cerrar).
@export var pulse_half_time: float = 0.8

@onready var _pillar: MeshInstance3D = $Pillar
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	# El cilindro crece hacia los dos lados de su centro: subirlo media
	# altura deja su base en el suelo con cualquier `height`.
	var mesh := _pillar.mesh as CylinderMesh
	if mesh != null:
		_pillar.position.y = mesh.height * 0.5
	_apply_color()
	var pulse := create_tween().set_loops()
	pulse.tween_property(_pillar, "scale", Vector3(pulse_width, 1.0, pulse_width),
			pulse_half_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_pillar, "scale", Vector3.ONE, pulse_half_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Pinta el pilar y la luz. El material es propio de cada baliza
## (resource_local_to_scene en Beacon.tscn), así un color no pasa a otra.
func _apply_color() -> void:
	var material := _pillar.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(color.r, color.g, color.b, pillar_alpha)
		material.emission = color
	_light.light_color = color
