class_name EmberBurst
extends Node3D
## Detonación de la Vara de brasas, del pool: la cáscara que se
## expande (la lectura del estallido), un disco de quemadura en el suelo que
## dura y se desvanece, y una ráfaga de brasas que suben. Mallas y materiales
## son recursos compartidos de la escena; cada instancia se desvanece con
## MeshInstance3D.transparency.
## Las bolas de fuego de Mythos estallan con este mismo efecto: avisan que es
## fuego del jefe (boss_fire) y en su segunda fase la cáscara y las brasas
## salen con los colores del grupo «Fuego renacido».

@export_group("Tiempos")
## Segundos que tarda la cáscara en crecer hasta el radio y desvanecerse.
@export var shell_time: float = 0.35
## Segundos que tarda en desvanecerse la quemadura del suelo.
@export var scorch_time: float = 1.1

@export_group("Brasas")
## Radio de estallido para el que está pensada la ráfaga de brasas de la
## escena; las brasas se escalan contra él, así una detonación de 6 m de un
## build de área no es una burbuja hueca con un soplo de chispas en el centro.
@export var embers_reference_radius: float = 2.5

@export_group("Fuego renacido")
## Color de la cáscara cuando estalla fuego de la segunda fase de Mythos.
@export var reborn_shell_color: Color = Color(0.3, 0.72, 1.0)
## Color de las brasas en ese caso.
@export var reborn_ember_color: Color = Color(0.6, 0.9, 1.0)

@onready var _shell: MeshInstance3D = $Shell
@onready var _scorch: MeshInstance3D = $Scorch
@onready var _embers: GPUParticles3D = $Embers

var _tween: Tween = null
## Copias propias de los materiales de la escena, con los colores renacidos.
var _reborn_shell: StandardMaterial3D = null
var _reborn_embers: StandardMaterial3D = null


func _ready() -> void:
	_reborn_shell = _recolored(_shell.mesh.surface_get_material(0), reborn_shell_color)
	_reborn_embers = _recolored(_embers.draw_pass_1.surface_get_material(0), reborn_ember_color)


## Contrato del pool: mata un estallido viejo para que el reuso empiece limpio.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_shell.transparency = 0.0
	_scorch.transparency = 0.0
	_embers.scale = Vector3.ONE
	_embers.emitting = false


## Detona en `center` (el origen del enemigo golpeado) con el radio de daño
## dado: la cáscara crece hasta ese radio y la quemadura marca el suelo.
## `boss_fire` avisa que es fuego de Mythos: toma el color de su fase.
func play(center: Vector3, radius: float, boss_fire: bool = false) -> void:
	var reborn := boss_fire and FireTint.amount() >= 0.5
	_shell.material_override = _reborn_shell if reborn else null
	_embers.material_override = _reborn_embers if reborn else null
	global_position = center
	_shell.transparency = 0.0
	_shell.scale = Vector3.ONE * 0.2
	_scorch.transparency = 0.35
	_scorch.scale = Vector3(radius * 0.8, 1.0, radius * 0.8)
	_embers.scale = Vector3.ONE * maxf(radius / maxf(embers_reference_radius, 0.01), 0.2)
	_embers.restart()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_shell, "scale", Vector3.ONE * radius, shell_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_shell, "transparency", 1.0, shell_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_scorch, "transparency", 1.0, scorch_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_interval(0.2)
	_tween.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)


func _recolored(source: Material, color: Color) -> StandardMaterial3D:
	var copy := source.duplicate() as StandardMaterial3D
	copy.albedo_color = color
	return copy
