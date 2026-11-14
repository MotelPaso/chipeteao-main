class_name MythosRebirthAct
extends Node3D
## El renacer de Mythos como cinemática (nodo Rebirth de
## MythosCinematic.tscn): lo que se ve entre su primera fase y la segunda,
## con el mundo congelado. La cinemática le pasa en cada frame cuánto avanzó
## (advance) y este nodo dispara cada momento a su tiempo:
##   BRASA    las cenizas se juntan y la brasa brilla cada vez más
##   COLUMNA  una columna de fuego sube de las cenizas: es el primer fuego
##            de la segunda fase, y desde ahí su color recorre el mapa
##            (HellTransformation.ascend)
##   FORMA    dentro de la columna toma su forma renacida
##   RENACE   la columna estalla: ondas de fuego, esquirlas y destello
##   GRITO    grita de frente a la cámara, con su nombre nuevo
## Los tiempos son fracciones del renacer (0-1) y van en el orden de arriba.
## Nada de aquí hace daño ni toca a nadie.

## Pide un temblor de cámara: `strength` en metros de pantalla, durante `seconds`.
signal shake_requested(strength: float, seconds: float)
## Pide un destello a pantalla completa de opacidad `alpha` (0-1).
signal flash_requested(alpha: float)

@export_group("Brasa")
## Gemido con que cae en cenizas (fila de Sfx.SOUND_LIBRARY).
@export var fall_sfx: StringName = &"phoenix_hurt"
## Fracción del renacer (0-1) desde la que la brasa empieza a brillar (antes termina de caer).
@export_range(0.0, 1.0) var glow_from: float = 0.1
## Carga de la brasa justo antes de estallar (0-1): cuánto llega a brillar.
@export_range(0.0, 1.0) var ember_glow: float = 0.9

@export_group("Columna de fuego")
## Fracción del renacer (0-1) en que sube la columna y el fuego empieza a cambiar de color.
@export_range(0.0, 1.0) var pillar_fraction: float = 0.28
## Escena de la columna (un FireTornado que no daña). Vacío = sin columna.
@export var pillar_scene: PackedScene = preload("res://scenes/fx/FireTornado.tscn")
## Radio de la columna, en metros.
@export var pillar_radius: float = 4.2
## Segundos que tarda en formarse.
@export var pillar_form_seconds: float = 0.6
## Grito mientras sube la columna (fila de Sfx.SOUND_LIBRARY).
@export var pillar_sfx: StringName = &"phoenix_ascend"
## Temblor de cámara mientras la columna arde, en metros de pantalla.
@export var pillar_shake: float = 0.12

@export_group("Forma")
## Fracción del renacer (0-1) en que toma su forma renacida dentro de la columna.
@export_range(0.0, 1.0) var form_fraction: float = 0.64

@export_group("Renace")
## Fracción del renacer (0-1) en que la columna estalla y abre las alas.
@export_range(0.0, 1.0) var burst_fraction: float = 0.8
## Radio del fogonazo, en unidades del modelo.
@export var burst_flash_radius: float = 13.0
## Segundos que dura ese fogonazo.
@export var burst_flash_seconds: float = 0.9
## Opacidad del destello a pantalla completa (0-1).
@export_range(0.0, 1.0) var burst_flash_alpha: float = 0.7
## Temblor de cámara del estallido, en metros de pantalla.
@export var burst_shake: float = 0.8
## Segundos que dura ese temblor.
@export var burst_shake_seconds: float = 1.1
## Sonido del estallido (fila de Sfx.SOUND_LIBRARY).
@export var burst_sfx: StringName = &"phoenix_rebirth"
## Escena de las ondas de fuego que salen del estallido (FireWave). Vacío = sin ondas.
@export var wave_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Ondas que salen, una tras otra.
@export var waves: int = 2
## Segundos entre una onda y la siguiente.
@export var wave_interval: float = 0.22
## Radio en metros con que nace cada onda y hasta el que llega.
@export var wave_start_radius: float = 3.0
@export var wave_radius: float = 60.0
## Metros por segundo a los que se abre.
@export var wave_speed: float = 34.0

@export_group("Grito")
## Fracción del renacer (0-1) en que grita y aparece su nombre.
@export_range(0.0, 1.0) var roar_fraction: float = 0.84
## Su grito (fila de Sfx.SOUND_LIBRARY).
@export var roar_sfx: StringName = &"phoenix_screech"
## Temblor de cámara del grito, en metros de pantalla.
@export var roar_shake: float = 0.3

var _boss: Mythos = null
var _transformation: HellTransformation = null
var _center: Vector3 = Vector3.ZERO
var _seconds: float = 8.0
var _live: bool = false
## Momentos ya disparados, en el orden de la lista de arriba.
var _done: int = 0
var _waves_sent: int = 0

@onready var _gather: CPUParticles3D = $Gather
@onready var _shards: CPUParticles3D = $Shards


## Empieza el renacer: las cenizas quedaron en `center`, el mapa es
## `transformation` (puede ser null) y el renacer dura `seconds`.
func begin(boss: Mythos, transformation: HellTransformation, center: Vector3,
		seconds: float) -> void:
	_boss = boss
	_transformation = transformation
	_center = center
	_seconds = maxf(seconds, 0.01)
	_live = true
	_done = 0
	_waves_sent = 0
	_gather.global_position = center
	_gather.restart()
	_gather.emitting = true
	Sfx.play(fall_sfx)
	advance(0.0)


## Un frame del renacer con el avance en `progress` (0-1).
func advance(progress: float) -> void:
	if not _live:
		return
	if progress >= glow_from and progress < burst_fraction:
		# La brasa brilla cada vez más hasta el estallido.
		_boss.rig.set_nova(ember_glow * (progress - glow_from)
				/ maxf(burst_fraction - glow_from, 0.01))
	if _done == 0 and progress >= pillar_fraction:
		_done = 1
		_raise_pillar()
	if _done == 1 and progress >= form_fraction:
		_done = 2
		_gather.emitting = false
		_boss.rig.ascend(true)
		_boss.rig.set_pose(MythosRig.Pose.WINDUP)
	if _done == 2 and progress >= burst_fraction:
		_done = 3
		_burst()
	# Las ondas salen una tras otra desde el estallido.
	while _done >= 3 and _waves_sent < waves and progress >= burst_fraction \
			+ wave_interval * float(_waves_sent) / _seconds:
		_waves_sent += 1
		_send_wave()
	if _done == 3 and progress >= roar_fraction:
		_done = 4
		_boss.rig.gesture(&"roar")
		Sfx.play(roar_sfx)
		shake_requested.emit(roar_shake, 1.0)


## Corta el renacer (terminó, alguien lo saltó o la arena se va) y apaga lo
## que quede encendido. Se puede llamar siempre.
func stop() -> void:
	if not _live:
		return
	_live = false
	_gather.emitting = false
	for child: Node in get_children():
		if child.is_inside_tree() and child.has_method(&"dissipate"):
			child.call(&"dissipate")


# --- momentos ---------------------------------------------------------------------

## La columna sube y el fuego de la segunda fase empieza a recorrer el mapa:
## llega a todo justo cuando Mythos estalla.
func _raise_pillar() -> void:
	var until_burst := (burst_fraction - pillar_fraction) * _seconds
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.ascend(_center, until_burst)
	Sfx.play(pillar_sfx)
	shake_requested.emit(pillar_shake, until_burst)
	var node := _spawn(pillar_scene)
	var pillar := node as FireTornado
	if pillar != null:
		pillar.start(_center, pillar_radius, pillar_form_seconds,
				maxf(until_burst - pillar_form_seconds, 0.1), 0.0, 0.0, false)
	elif node != null:
		node.queue_free()


## La columna estalla y Mythos renacido abre las alas.
func _burst() -> void:
	var rig := _boss.rig
	rig.set_pose(MythosRig.Pose.CAST)
	rig.gesture(&"flap")
	rig.burst()
	rig.pop_nova(burst_flash_radius, burst_flash_seconds)
	_shards.global_position = _center + Vector3.UP * 2.0
	_shards.restart()
	_shards.emitting = true
	Sfx.play(burst_sfx)
	shake_requested.emit(burst_shake, burst_shake_seconds)
	flash_requested.emit(burst_flash_alpha)


## Una onda de fuego que no daña, desde las cenizas.
func _send_wave() -> void:
	var node := _spawn(wave_scene)
	var wave := node as FireWave
	if wave != null:
		wave.open(_center, wave_start_radius, wave_radius, wave_speed, 0.0, 0.0, 0.0, null)
	elif node != null:
		node.queue_free()


## Una instancia propia de `scene`, colgada de este nodo. No sale del pool:
## lo del pool cuelga de la arena, que está congelada durante el renacer.
func _spawn(scene: PackedScene) -> Node:
	if scene == null:
		return null
	var node := scene.instantiate()
	add_child(node)
	return node
