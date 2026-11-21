class_name MythosNova
extends MeshInstance3D
## La bola de luz del fénix (nodo Nova de Mythos.tscn, bajo Visual/Hover).
## Crece a su alrededor mientras carga el Amanecer (charge) y da un fogonazo
## cuando un golpe lo pide (pop). El rig la maneja con MythosRig.set_nova() y
## pop_nova().

@export_group("Tamaño")
## Radio de la bola al empezar a cargar, en unidades del modelo.
@export var start_radius: float = 2.0
## Radio de la bola con la carga completa, en unidades del modelo.
@export var full_radius: float = 6.0

## Carga actual (0-1); -1 con la bola apagada.
var charge_amount: float = -1.0

var _tween: Tween = null


func _ready() -> void:
	visible = false


## Carga del Amanecer: de 0 a 1 la bola crece alrededor del fénix; con un
## valor negativo se apaga.
func charge(amount: float) -> void:
	_kill_tween()
	charge_amount = amount
	visible = amount >= 0.0
	if amount < 0.0:
		return
	var shown := clampf(amount, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(start_radius, full_radius, shown)
	set_instance_shader_parameter(&"charge", shown)


## Un fogonazo: la bola crece de golpe hasta `radius` (unidades del modelo) y
## se apaga en `seconds`.
func pop(radius: float, seconds: float) -> void:
	_kill_tween()
	charge_amount = -1.0
	visible = true
	_tween = create_tween()
	_tween.tween_method(_pop_step.bind(radius), 0.0, 1.0, seconds)
	_tween.tween_callback(hide)


func _pop_step(t: float, radius: float) -> void:
	scale = Vector3.ONE * lerpf(start_radius, radius, 1.0 - pow(1.0 - t, 3.0))
	set_instance_shader_parameter(&"charge", 1.0 - t)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
