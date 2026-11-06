class_name Sunspitter
extends EnemyBase
## Escupesol (Dunas de Ceniza), a distancia: un escarabajo que mantiene una
## banda de distancia, apunta una línea de aviso que engorda durante la
## carga y después fija un rayo ámbar continuo que daña por pulsos mientras
## dure la línea de visión. Cualquier geometría del mundo (mesa, roca,
## obelisco) corta el rayo, así que la cobertura es la respuesta. Después
## se escabulle de lado mientras recarga. El rayo de visión solo ve la capa
## 1 (mundo + jugadores; los enemigos están en la capa 2 y nunca bloquean ni
## se queman) y daña al raider que el rayo alcanzó: el que fijó al apuntar,
## o un compañero que se cruzó para cubrirlo. Nada más puede recibirlo.

enum State { SKITTER, AIM, FIRE }

const AIM_COLOR := Color(1.0, 0.62, 0.18)
const BEAM_COLOR := Color(1.0, 0.42, 0.1)

@export_group("Standoff Band")
@export var band_inner: float = 10.0
@export var band_outer: float = 14.0

@export_group("Beam")
@export var fire_range: float = 17.0
@export var aim_windup: float = 0.8
@export var beam_duration: float = 1.5
@export var beam_tick_damage: float = 4.0
@export var beam_tick_interval: float = 0.5
@export var beam_cooldown: float = 3.0
## Extremos del rayo: sale del ojo y sigue el pecho del raider.
@export var muzzle_height: float = 0.55
@export var target_height: float = 0.9

var _state: State = State.SKITTER
var _state_timer: float = 0.0
# Espera inicial para que uno recién aparecido no dispare al aterrizar.
var _cooldown_timer: float = 1.2
var _tick_timer: float = 0.0
# Dirección del escabullirse de lado; se invierte tras cada rayo.
var _strafe_sign: float = 1.0
## Raider fijado al empezar a apuntar. La línea de aviso promete UNA
## víctima, así que el rayo sigue quemando a esa en vez de elegir al más
## cercano en cada tick (en co-op el más cercano cambia todo el tiempo).
var _target: Node3D = null
var _aim_line: BeamVisual
var _beam: BeamVisual
var _hum_held: bool = false
## Consulta del rayo de visión (solo capa 1), creada una vez y reapuntada en
## cada lanzamiento: _beam_sight corre en cada tick de apuntar, disparar o
## esperar con la línea bloqueada. Solo cambian from y to.
var _sight_query: PhysicsRayQueryParameters3D = \
		PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1)


func _init() -> void:
	# No poseíble: su rayo solo daña al grupo "player", así que poseído
	# seguiría atacando al equipo al que ahora pertenece.
	possessable = false


func _ready() -> void:
	super()
	_aim_line = BeamVisual.create(self, AIM_COLOR, 0.05)
	_beam = BeamVisual.create(self, BEAM_COLOR, 0.22)
	_health.died.connect(_on_sunspitter_died)
	_strafe_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0


func _behavior_tick(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if _state == State.SKITTER:
		return
	# Si el objetivo fijado se va (muerte, cierre) el tiro se aborta en vez
	# de pasar en silencio al que esté más cerca ahora.
	if not _target_is_valid():
		_abort_attack()
		return
	_state_timer -= delta
	if _state == State.AIM:
		_tick_aim(_target)
	elif _state == State.FIRE:
		_tick_fire(_target, delta)


func _target_is_valid() -> bool:
	return _target != null and is_instance_valid(_target) \
			and _target.is_inside_tree() and _target.is_in_group("player")


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	if _state != State.SKITTER:
		return Vector3.ZERO  # se planta para apuntar y disparar
	if distance > band_outer:
		return seek
	if distance < band_inner:
		return -seek
	# Dentro de la banda: se escabulle de lado mientras recarga.
	return seek.cross(Vector3.UP) * _strafe_sign


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.SKITTER or _cooldown_timer > 0.0:
		return
	# El mínimo aleja la geometría del rayo del caso "encima de su cabeza".
	if distance > fire_range or distance < 1.0:
		return
	if _beam_sight(player, null) == null:
		return  # nunca apunta hacia una pared
	_state = State.AIM
	_state_timer = aim_windup
	_target = player


func _tick_aim(player: Node3D) -> void:
	# La línea de aviso engorda durante la carga: el grosor es la cuenta.
	var progress := 1.0 - clampf(_state_timer / aim_windup, 0.0, 1.0)
	_beam_sight(player, _aim_line, lerpf(0.03, 0.14, progress))
	if _state_timer <= 0.0:
		_begin_fire()


func _tick_fire(player: Node3D, delta: float) -> void:
	if _state_timer <= 0.0:
		_end_fire()
		return
	var burned := _beam_sight(player, _beam)
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer += beam_tick_interval
	if burned == null:
		return  # un pulso bloqueado se consume, no se acumula
	# Lo recibe quien el rayo alcanzó de verdad: un raider que se cruza en la
	# línea cubre al objetivo, que es lo que promete la cobertura.
	var player_health := Health.find_in(burned)
	if player_health != null and not player_health.is_dead:
		player_health.take_damage(beam_tick_damage, false, self)


func _begin_fire() -> void:
	_state = State.FIRE
	_state_timer = beam_duration
	_tick_timer = 0.0  # el primer pulso cae en el primer frame del rayo
	_aim_line.clear()
	_acquire_hum()


func _end_fire() -> void:
	_state = State.SKITTER
	_cooldown_timer = beam_cooldown
	_strafe_sign = -_strafe_sign
	_target = null
	_beam.clear()
	_release_hum()


## Lanza un rayo del ojo al pecho del raider contra la capa 1 (mundo +
## jugadores; los enemigos están en la 2 y no lo ven). Si recibe `line` la
## pinta hasta donde pegó el rayo, y devuelve EL RAIDER QUE ALCANZÓ, o null
## si la geometría lo cortó. Devolver el cuerpo y no un "¿despejado?" es lo
## que hace honesta la cobertura en co-op: quema al que se cruzó.
func _beam_sight(player: Node3D, line: BeamVisual, thickness: float = -1.0) -> Node3D:
	var from := global_position + Vector3.UP * muzzle_height
	var to := player.global_position + Vector3.UP * target_height
	_sight_query.from = from
	_sight_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_sight_query)
	var burned: Node3D = null
	var end := to
	if not hit.is_empty():
		var collider := hit["collider"] as Node3D
		end = hit["position"]
		if collider != null and collider.is_in_group("player"):
			burned = collider
	if line != null:
		line.span(from, end, thickness)
	return burned


func _apply_elite_damage(multiplier: float) -> void:
	beam_tick_damage *= multiplier


func _abort_attack() -> void:
	# Se rearma ante CUALQUIER ataque interrumpido, no solo uno disparado:
	# si no, el siguiente raider en rango recibiría el rayo al instante.
	if _state != State.SKITTER:
		_cooldown_timer = maxf(_cooldown_timer, beam_cooldown)
	_state = State.SKITTER
	_target = null
	_aim_line.clear()
	_beam.clear()
	_release_hum()


func _on_sunspitter_died() -> void:
	_abort_attack()


func _exit_tree() -> void:
	# Liberado a mitad del rayo (cambio de mapa, recortes del tope): nunca
	# dejar una referencia del zumbido colgada.
	_release_hum()


func _acquire_hum() -> void:
	if _hum_held:
		return
	_hum_held = true
	Sfx.acquire_loop(&"laser_hum")


func _release_hum() -> void:
	if not _hum_held:
		return
	_hum_held = false
	Sfx.release_loop(&"laser_hum")
