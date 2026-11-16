class_name SplashBurst
extends Node3D
## Salpicón del pool: terrones y gotas que saltan de un golpe de la Langosta
## Azul (un pinzazo, la caída del Salto, la salida de la Emboscada). No daña a
## nadie. `size` agranda todo el estallido (1 = el de la escena). Vuelve solo
## al pool cuando terminó.
## Los dos emisores son los nodos Clods (tierra) y Spray (agua) de
## SplashBurst.tscn: cantidad, colores y velocidades se ajustan ahí.
## Grupo "splash_bursts".

const GROUP := &"splash_bursts"

@export_group("Salpicón")
## Segundos tras los que vuelve al pool (algo más que la vida de sus partículas).
@export var return_seconds: float = 1.3

var _left: float = 0.0

@onready var _clods: CPUParticles3D = $Clods
@onready var _spray: CPUParticles3D = $Spray


func _ready() -> void:
	set_process(false)


## Contrato de nodo del pool: sin partículas del estallido anterior.
func pool_reset() -> void:
	_clods.emitting = false
	_spray.emitting = false
	set_process(false)


## Saca del pool un salpicón y lo hace estallar en `at` con tamaño `size`.
static func spawn(scene: PackedScene, at: Vector3, size: float = 1.0) -> SplashBurst:
	var burst := Pools.acquire_scene(scene) as SplashBurst if scene != null else null
	if burst != null:
		burst.burst(at, size)
	return burst


## Hace estallar ESTE salpicón en `at` con tamaño `size`.
func burst(at: Vector3, size: float) -> void:
	global_position = at
	scale = Vector3.ONE * maxf(size, 0.1)
	add_to_group(GROUP)
	_clods.restart()
	_clods.emitting = true
	_spray.restart()
	_spray.emitting = true
	_left = return_seconds
	set_process(true)


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	set_process(false)
	remove_from_group(GROUP)
	Pools.release(self)
