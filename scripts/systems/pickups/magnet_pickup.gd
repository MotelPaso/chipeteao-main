class_name MagnetPickup
extends Area3D
## Chasis compartido de los recolectables que caen (gemas de XP, orbes de
## curación). En reposo gira y flota; dentro del radio de imán (escalado por
## RunState.pickup_radius_multiplier, para que las mejoras de alcance lleguen
## a todo drop) persigue al raider en pie más cercano acelerando, se recoge
## al contacto y desaparece tras `lifetime`.
## Va en pool: aparece con Pools.acquire_scene, cada desaparición es un
## Pools.release y pool_reset() restaura el estado de recién soltado. Los
## vivos están en el LIVE_GROUP de su subclase (entran al adquirir y salen
## ANTES de liberar, así la aspiradora y el tope de orbes nunca ven un nodo
## guardado o de salida).
##
## Las subclases aportan tres cosas: el grupo vivo, qué hace recogerlo y
## cualquier floritura extra en reposo.

## Distancia al cuadrado (m²) a la que el acercamiento final cuenta como
## recogida: un último salto a máxima velocidad puede cruzar todo el área
## en un frame de física sin emitir body_entered.
const CATCH_RADIUS_SQ: float = 0.36
## Altura de puntería sobre el blanco, en metros: vuela al pecho y no a
## los pies.
const TARGET_HEIGHT: float = 0.9

## Radio de imán en metros (antes del multiplicador de alcance de la partida).
@export var magnet_radius: float = 4.0
## Aceleración de la persecución, en m/s².
@export var magnet_acceleration: float = 45.0
## Velocidad inicial de persecución, en m/s, cuando la aspiradora de subida
## de nivel agarra este recolectable.
@export var vacuum_speed: float = 26.0
## Segundos en el suelo antes de desaparecer sin recoger.
@export var lifetime: float = 60.0
## Giro en reposo, en radianes por segundo.
@export var spin_speed: float = 2.5
## Flotación en reposo: altura en metros y velocidad.
@export var bob_amplitude: float = 0.12
@export var bob_speed: float = 3.0

@onready var _visual: Node3D = $Visual

var _age: float = 0.0
var _visual_rest_y: float = 0.0
var _homing: bool = false
var _speed: float = 0.0
var _collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_rest_y = _visual.position.y


## Contrato de nodo en pool: vuelve al estado de recién soltado en cada acquire.
func pool_reset() -> void:
	_age = 0.0
	_homing = false
	_speed = 0.0
	_collected = false
	# El giro y el pulso se acumulan en el Visual: sin estas tres líneas un
	# recolectable reciclado saldría del pool con la orientación y la escala
	# con que terminó su vida anterior.
	_visual.position.y = _visual_rest_y
	_visual.rotation = Vector3.ZERO
	_visual.scale = Vector3.ONE
	_reset_extra()
	var group := live_group()
	if group != &"":
		add_to_group(group)


## Aspiradora de subida de nivel (llega por el grupo vivo): activa la
## persecución a vacuum_speed sin importar el radio de recogida.
func vacuum() -> void:
	if _collected:
		return
	_homing = true
	_speed = maxf(_speed, vacuum_speed)


func _physics_process(delta: float) -> void:
	_age += delta
	_visual.rotate_y(spin_speed * delta)
	_idle_visuals(delta)

	var player := Coop.nearest_player(get_tree(), global_position)
	# La expiración corre ANTES del retorno sin jugador y FUERA de la rama de
	# reposo: si no, un recolectable ya enganchado (o cualquiera con toda la
	# party derribada) envejecería para siempre, ocupando un lugar del pool y,
	# en los orbes, un asiento permanente bajo el tope.
	if _age > lifetime and (player == null or not _homing):
		_release_to_pool()
		return
	if player == null:
		return
	var target := player.global_position + Vector3.UP * TARGET_HEIGHT

	if not _homing:
		_visual.position.y = _visual_rest_y + sin(_age * bob_speed) * bob_amplitude
		var radius := magnet_radius * RunState.pickup_radius_multiplier
		if global_position.distance_squared_to(target) <= radius * radius:
			_homing = true  # pegajoso: sigue persiguiendo aunque el jugador se aleje
		return

	_speed += magnet_acceleration * delta
	global_position = global_position.move_toward(target, _speed * delta)
	if global_position.distance_squared_to(target) < CATCH_RADIUS_SQ:
		collect(player)


## Se recoge una sola vez y luego vuelve a su pool.
func collect(collector: Node3D) -> void:
	if _collected:
		return
	_collected = true
	_on_collected(collector)
	_release_to_pool()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		collect(body)


## Deja el grupo vivo ANTES de la liberación al pool, para que una
## aspiradora o un conteo del tope en la ventana diferida (el nodo sigue un
## frame más en el árbol) nunca toquen uno que ya se va.
func _release_to_pool() -> void:
	var group := live_group()
	if group != &"" and is_in_group(group):
		remove_from_group(group)
	Pools.release(self)


# --- Ganchos de subclase ----------------------------------------------------

## Grupo al que pertenece toda instancia viva (soltada y sin recoger).
func live_group() -> StringName:
	return &""


## Qué hace recogerlo para `collector` (nunca null por contacto; el
## acercamiento rápido pasa el jugador al que volaba).
func _on_collected(_collector: Node3D) -> void:
	pass


## Floritura extra por frame en reposo, sobre el giro y la flotación.
func _idle_visuals(_delta: float) -> void:
	pass


## Estado extra a restaurar al adquirir (valores que quien suelta escala
## DESPUÉS del reinicio).
func _reset_extra() -> void:
	pass
