class_name BoomerangProjectile
extends Area3D
## Hoja del Bumerán: vuela hasta un punto de giro fijo, da la vuelta y
## persigue al jugador (que se mueve) hasta que la atrapa. Daña a cada
## enemigo como máximo una vez por tramo: el registro de golpes se vacía al
## girar, y un cuerpo que la hoja atraviesa vuelve a entrar en el área a la
## vuelta para su segundo golpe. Vuelve a Pools al ser atrapada, si pierde al
## jugador o tras max_lifetime; pool_reset() rearma tramos y registro.

## Velocidad de vuelo, en metros por segundo.
@export var speed: float = 14.0
## Radianes por segundo del giro puramente visual del nodo Spinner.
@export var spin_speed: float = 14.0
## Distancia al punto de captura del jugador que cuenta como atrapada, en metros.
@export var catch_radius: float = 1.0
## Tope de vida en segundos, para que una hoja varada nunca quede para siempre.
@export var max_lifetime: float = 8.0
## Altura sobre el origen del jugador a la que vuelve la hoja, en metros.
@export var catch_height: float = 0.9

var _source: WeaponBase = null
var _out_point: Vector3 = Vector3.ZERO
var _returning: bool = false
var _life_left: float = 0.0
## IDs de instancia dañados en el tramo ACTUAL (se vacía al girar).
var _hit_ids_this_leg: Dictionary[int, bool] = {}
## True cuando la hoja ya volvió al pool. Pools.release() solo difiere el
## cambio de padre, así que el Area3D sigue reportando cuerpos el resto del
## paso de física; esto evita un golpe extra de una hoja ya atrapada.
var _spent: bool = false

@onready var _spinner: Node3D = $Spinner
@onready var _trail: GPUParticles3D = $Trail


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Contrato del pool: tramo de ida nuevo en cada adquisición. La estela se
## reinicia para que no queden bocanadas del vuelo anterior en la posición vieja.
func pool_reset() -> void:
	_source = null
	_out_point = Vector3.ZERO
	_returning = false
	_spent = false
	_life_left = max_lifetime
	_hit_ids_this_leg.clear()
	# También la orientación: launch() solo escribe la posición, y el Spinner
	# acumula giro todo el vuelo; sin esto una hoja reusada saldría a medio giro.
	rotation = Vector3.ZERO
	_spinner.rotation = Vector3.ZERO
	_trail.restart()


## Lo llama el arma justo después de colgar la hoja: fija el origen del
## lanzamiento y el punto donde el tramo de ida da la vuelta.
func launch(source: WeaponBase, from: Vector3, direction: Vector3, distance: float) -> void:
	_source = source
	global_position = from
	_out_point = from + direction * distance


func _physics_process(delta: float) -> void:
	_spinner.rotate_y(spin_speed * delta)
	_life_left -= delta
	if _life_left <= 0.0:
		_release()
		return
	var step := speed * delta
	if not _returning:
		var to_out := _out_point - global_position
		if to_out.length() <= step:
			global_position = _out_point
			_returning = true
			_hit_ids_this_leg.clear()
		else:
			global_position += to_out.normalized() * step
		return
	# Vuelve a QUIEN LA LANZÓ (cada raider en co-op atrapa su hoja); sin él,
	# vuelve al jugador más cercano.
	var player: Node3D = null
	if _source != null and is_instance_valid(_source):
		player = _source.carrier_player()
	if player == null:
		player = Coop.nearest_player(get_tree(), global_position)
	if player == null:
		_release()
		return
	var to_catch := player.global_position + Vector3.UP * catch_height - global_position
	if to_catch.length() <= maxf(step, catch_radius):
		_release()
	else:
		global_position += to_catch.normalized() * step


## Única salida: marca la hoja como gastada antes de devolverla, así el
## Area3D todavía vivo no puede dar otro corte en este paso de física.
func _release() -> void:
	_spent = true
	Pools.release(self)


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	if not body.is_in_group("enemies"):
		return
	var body_id := body.get_instance_id()
	if _hit_ids_this_leg.has(body_id):
		return
	_hit_ids_this_leg[body_id] = true
	var health := Health.find_in(body)
	if health != null and _source != null and is_instance_valid(_source):
		_source.deal_damage(health)
