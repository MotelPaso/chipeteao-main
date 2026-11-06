class_name EmberBurst
extends Node3D
## Detonación de la Vara de brasas, del pool: la cáscara emisiva que se
## expande (la lectura del estallido), un disco de quemadura en el suelo que
## dura y se desvanece, y una ráfaga de brasas que suben. Mallas y materiales
## son recursos compartidos de la escena; cada instancia se desvanece con
## MeshInstance3D.transparency.

const SHELL_TIME: float = 0.35
const SCORCH_TIME: float = 1.1

## Radio de estallido para el que está pensada la ráfaga de brasas de la
## escena; las brasas se escalan contra él, así una detonación de 6 m de un
## build de área no es una burbuja hueca con un soplo de chispas en el centro.
@export var embers_reference_radius: float = 2.5

@onready var _shell: MeshInstance3D = $Shell
@onready var _scorch: MeshInstance3D = $Scorch
@onready var _embers: GPUParticles3D = $Embers

var _tween: Tween = null


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
func play(center: Vector3, radius: float) -> void:
	global_position = center
	_shell.transparency = 0.0
	_shell.scale = Vector3.ONE * 0.2
	_scorch.transparency = 0.35
	_scorch.scale = Vector3(radius * 0.8, 1.0, radius * 0.8)
	_embers.scale = Vector3.ONE * maxf(radius / maxf(embers_reference_radius, 0.01), 0.2)
	_embers.restart()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_shell, "scale", Vector3.ONE * radius, SHELL_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_shell, "transparency", 1.0, SHELL_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_scorch, "transparency", 1.0, SCORCH_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_interval(0.2)
	_tween.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)
