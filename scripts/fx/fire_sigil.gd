class_name FireSigil
extends MeshInstance3D
## El aviso en el suelo de un golpe de Mythos, del pool: un aro que marca
## desde el primer momento hasta dónde llega el golpe, una rueda de marcas
## que gira y un relleno de brasas que crece desde el centro; cuando el
## relleno toca el aro, cae el golpe. Con `locked` se ve clavado (la Picada
## dejó de perseguir). Solo es visual: el momento del golpe y el daño los
## decide quien lo pide. El plano de radio 1 se escala al radio pedido; los
## colores viven en su material y pasan a los de la segunda fase con el
## resto del fuego (FireTint).

@export_group("Animación")
## Segundos que tarda en aparecer.
@export var appear_time: float = 0.12
## Segundos que tarda en desvanecerse cuando cae el golpe.
@export var fade_time: float = 0.2
## Metros sobre el suelo, para que no parpadee contra el terreno.
@export var lift: float = 0.07

var _tween: Tween = null


## Contrato de nodo del pool: sin la animación del aviso anterior.
func pool_reset() -> void:
	_kill_tween()
	visible = false


## Muestra un aviso de `radius` metros en `center` que se llena en
## `duration` segundos; vuelve solo al pool tras desvanecerse.
func show_disc(center: Vector3, radius: float, duration: float, locked: bool) -> void:
	global_position = center + Vector3.UP * lift
	scale = Vector3(radius, 1.0, radius)
	visible = true
	set_instance_shader_parameter(&"locked", 1.0 if locked else 0.0)
	set_instance_shader_parameter(&"fill", 0.0)
	set_instance_shader_parameter(&"fade", 0.0)
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_method(_set_fill, 0.0, 1.0, maxf(duration, 0.01))
	_tween.tween_method(_set_fade, 0.0, 1.0, minf(appear_time, maxf(duration, 0.01)))
	_tween.chain().tween_method(_set_fade, 1.0, 0.0, fade_time)
	_tween.chain().tween_callback(_on_done)


## Corre el aviso a `center` sin cortar su animación (un aviso que persigue).
func move_to(center: Vector3) -> void:
	global_position = center + Vector3.UP * lift


func _set_fill(value: float) -> void:
	set_instance_shader_parameter(&"fill", value)


func _set_fade(value: float) -> void:
	set_instance_shader_parameter(&"fade", value)


func _on_done() -> void:
	visible = false
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
