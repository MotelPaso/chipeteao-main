class_name BloodPoolFx
extends Node3D
## Visual del pool para el charco del Vial de sangre: disco carmesí con un
## anillo de borde más oscuro y burbujas lentas que suben, latiendo suave
## mientras está activo. Solo visual: blood_vial.gd maneja los pulsos de daño
## y llama a play() al formarse el charco y a expire() tras su último pulso.
## El radio escala el DISCO Y EL BORDE, nunca la raíz: las burbujas cuelgan
## del mismo nodo, y una escala no uniforme en la raíz las aplastaría en
## manchas que laten con el charco.

@export_group("Animación")
## Segundos de cada mitad del latido (hincharse o volver).
@export var throb_time: float = 0.35
## Segundos que tarda el charco en desvanecerse al expirar.
@export var fade_time: float = 0.3
## Radio de la esfera de burbujas como fracción del radio del charco (0.85 cae dentro del disco).
@export var bubble_emission_ratio: float = 0.85
## Ensanche del charco en lo más alto del latido (multiplicador del radio; 1.06 = +6 %).
@export var throb_spread: float = 1.06
## Escala Y del disco y del borde en lo más alto del latido (en reposo es 1).
@export var throb_height: float = 1.4

@onready var _disc: MeshInstance3D = $Disc
@onready var _rim: MeshInstance3D = $Rim
@onready var _bubbles: GPUParticles3D = $Bubbles

var _throb: Tween = null
var _fade: Tween = null
## True entre expire() y la liberación al pool: expire() tiene dos llamadores
## posibles (fin de partida, evolución del arma) y un segundo tween de
## desvanecido encolaría otra liberación para un nodo quizá ya readquirido.
var _expiring: bool = false


## Contrato del pool: mata los tweens viejos para que el reuso empiece limpio.
func pool_reset() -> void:
	_kill_tweens()
	_expiring = false
	_disc.transparency = 0.0
	_rim.transparency = 0.0
	_disc.scale = Vector3.ONE
	_rim.scale = Vector3.ONE
	_bubbles.emitting = false


## Forma el charco en `center` (plano del suelo) con el radio de daño dado.
func play(center: Vector3, radius: float) -> void:
	_expiring = false
	global_position = center
	_disc.transparency = 0.0
	_rim.transparency = 0.15
	_scale_ground(radius)
	# Las burbujas mantienen escala 1 y agrandan su esfera de emisión, así cada
	# burbuja sigue redonda sea cual sea el radio del charco.
	var bubble_material := _bubbles.process_material as ParticleProcessMaterial
	if bubble_material != null:
		bubble_material.emission_sphere_radius = radius * bubble_emission_ratio
	_bubbles.restart()
	_bubbles.emitting = true
	var rest := Vector3(radius, 1.0, radius)
	var swollen := Vector3(radius * throb_spread, throb_height, radius * throb_spread)
	_throb = create_tween().set_loops()
	_throb.set_parallel(true)
	_throb.tween_property(_disc, "scale", swollen, throb_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_throb.tween_property(_rim, "scale", swollen, throb_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_throb.chain().tween_property(_disc, "scale", rest, throb_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_throb.parallel().tween_property(_rim, "scale", rest, throb_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Desvanece el charco y lo devuelve al pool.
func expire() -> void:
	if _expiring:
		return
	_expiring = true
	_kill_tweens()
	_bubbles.emitting = false
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(_disc, "transparency", 1.0, fade_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.tween_property(_rim, "transparency", 1.0, fade_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.chain().tween_callback(_release)


func _scale_ground(radius: float) -> void:
	var ground := Vector3(radius, 1.0, radius)
	_disc.scale = ground
	_rim.scale = ground


func _release() -> void:
	Pools.release(self)


func _kill_tweens() -> void:
	if _throb != null and _throb.is_valid():
		_throb.kill()
	if _fade != null and _fade.is_valid():
		_fade.kill()
