class_name CofferMimic
extends SecretBossBase
## Cofre Mímico, minijefe oculto de las Dunas de Ceniza (GDD 6), lo atrae
## el Cráneo zumbante: un cofre de arenisca con patas de cangrejo y fauces
## de dientes dorados. Se mueve en ráfagas rápidas con pausas cortas,
## Muerde cuerpo a cuerpo (breve carga marcada sobre el punto del mordisco)
## y cada tanto se Entierra (solo asoma la tapa, con armadura extra) antes
## de salir con una onda de choque marcada. El pago, la barra de vida y el
## desbloqueo del personaje al morir viven en SecretBossBase.

enum State { ENTRANCE, PURSUE, SNAP_WINDUP, SNAP_RECOVER, BURIED }

const TELEGRAPH_COLOR := Color(0.98, 0.75, 0.25)
const IMPACT_COLOR := Color(1.0, 0.88, 0.5)
const ENTRANCE_RING_RADIUS: float = 2.4
## Ángulo de la tapa enterrado: cerrada del todo, solo se ve arena.
const LID_CLOSED_ANGLE: float = 0.0
## Cuánto se abren las fauces durante la carga del mordisco.
const LID_GAPE_ANGLE: float = 1.15

@export var entrance_duration: float = 0.8

@export_group("Scuttle")
## La move_speed del chasis es la de la ráfaga; en las pausas se queda quieto.
@export var scuttle_burst_time: float = 0.8
@export var scuttle_rest_time: float = 0.6

@export_group("Snap")
## Distancia al raider que dispara un mordisco.
@export var snap_range: float = 2.4
## Radio del disco del mordisco alrededor del punto que fijan las fauces.
@export var snap_radius: float = 1.8
@export var snap_damage: float = 14.0
@export var snap_windup: float = 0.45
@export var snap_recover: float = 0.55
@export var snap_cooldown: float = 2.2
@export var snap_height_window: float = 1.3

@export_group("Bury")
@export var bury_interval: float = 8.0
## Segundos enterrado (también el aviso de la onda al salir).
@export var bury_duration: float = 2.0
## Armadura plana que se suma a Health mientras está enterrado.
## Health.take_damage deja todo golpe en al menos 1 de daño, así que
## enterrado (armadura 2 de la escena + esto = 8) cualquier golpe de menos
## de 8 hace exactamente 1. Esa ES la ventana de "espera"; subirlo más se
## leería como inmunidad, no como armadura.
@export var bury_armor_bonus: float = 6.0
## Cuánto se hunde el cuerpo: ajustado para que solo asome la tapa.
@export var bury_sink_depth: float = 0.85
@export var shockwave_radius: float = 3.0
@export var shockwave_damage: float = 10.0
@export var shockwave_height_window: float = 1.5

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _scuttle_timer: float = 0.0
var _scuttle_resting: bool = false
var _snap_cooldown_timer: float = 0.0
var _snap_point: Vector3 = Vector3.ZERO
var _bury_timer: float = 0.0
var _buried_armor_applied: bool = false
## La tapa anima en su propio slot: corre junto a las señales del cuerpo
## (hundirse, salir), así que no puede compartir el _cue_tween de BossBase.
var _lid_tween: Tween

@onready var _lid_pivot: Node3D = $Visual/LidPivot
@onready var _lid_rest_angle: float = _lid_pivot.rotation.x


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_scuttle_timer = scuttle_burst_time
	_bury_timer = bury_interval


func _scale_attack_damage(multiplier: float) -> void:
	snap_damage *= multiplier
	shockwave_damage *= multiplier


func _behavior_tick(delta: float) -> void:
	_snap_cooldown_timer = maxf(_snap_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_bury_timer = maxf(_bury_timer - delta, 0.0)
		_scuttle_timer -= delta
		if _scuttle_timer <= 0.0:
			_scuttle_resting = not _scuttle_resting
			_scuttle_timer = scuttle_rest_time if _scuttle_resting else scuttle_burst_time
		return
	if _state == State.ENTRANCE and not _entrance_played:
		# Fuera de _ready para que el disparador ya haya puesto la posición
		# real antes de que aparezca el anillo de llegada.
		_entrance_played = true
		_play_entrance()
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.SNAP_WINDUP:
			_resolve_snap()
		State.SNAP_RECOVER:
			_state = State.PURSUE
		State.BURIED:
			_resolve_bury()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	if _state != State.PURSUE or _scuttle_resting:
		return Vector3.ZERO
	return seek


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE or _state == State.BURIED:
		return Vector3.ZERO
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _bury_timer <= 0.0:
		_start_bury()
		return
	if _snap_cooldown_timer <= 0.0 and distance <= snap_range:
		_start_snap(player)


## Llegada reventando la arena, con la voz de rugido del desierto.
func _play_entrance() -> void:
	Sfx.play(&"burrow_pop")
	Sfx.play(&"boss_roar_2", -3.0)
	_play_boss_entrance(ENTRANCE_RING_RADIUS, IMPACT_COLOR)


# --- Mordisco ------------------------------------------------------------------

func _start_snap(player: Node3D) -> void:
	_state = State.SNAP_WINDUP
	_state_timer = snap_windup
	_snap_point = _clamp_to_arena(player.global_position)
	Telegraph.spawn_disc(self, _snap_point, snap_radius, snap_windup, TELEGRAPH_COLOR)
	_play_lid(LID_GAPE_ANGLE, snap_windup)


func _resolve_snap() -> void:
	_state = State.SNAP_RECOVER
	_state_timer = snap_recover
	_snap_cooldown_timer = snap_cooldown
	Telegraph.spawn_disc(self, _snap_point, snap_radius, 0.15, IMPACT_COLOR)
	Sfx.play(&"hit_crit", -3.0)
	_play_lid(_lid_rest_angle, 0.12)
	# Contra el punto marcado del mordisco y todo el equipo: el raider que
	# fijó puede ya no ser el más cercano.
	damage_players_in_disc(_snap_point, snap_radius, snap_height_window,
			snap_damage, self)


# --- Enterrarse ----------------------------------------------------------------

func _start_bury() -> void:
	_state = State.BURIED
	_state_timer = bury_duration
	_bury_timer = bury_interval
	if not _buried_armor_applied:
		_buried_armor_applied = true
		_health.armor += bury_armor_bonus
	Sfx.play(&"burrow_pop", -2.0)
	# Todo el tiempo enterrado se lee como la cuenta de la onda.
	Telegraph.spawn_disc(self, global_position, shockwave_radius,
			bury_duration, TELEGRAPH_COLOR)
	_play_lid(LID_CLOSED_ANGLE, 0.15)
	_play_cue(_visual, "position:y", -bury_sink_depth, 0.25,
			Tween.TRANS_QUAD, Tween.EASE_IN)


func _resolve_bury() -> void:
	_state = State.PURSUE
	_scuttle_resting = false
	_scuttle_timer = scuttle_burst_time
	if _buried_armor_applied:
		_buried_armor_applied = false
		_health.armor -= bury_armor_bonus
	Telegraph.spawn_disc(self, global_position, shockwave_radius, 0.2, IMPACT_COLOR)
	Sfx.play(&"burrow_pop")
	Juice.shake(0.15, 0.35)
	_play_cue(_visual, "position:y", 0.0, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	# Enterrarse cerró la tapa; al salir hay que abrirla a su ángulo de
	# reposo o el cofre sigue peleando sellado el resto de la partida.
	_play_lid(_lid_rest_angle, 0.2)
	# El anillo de la onda se marca para todos, así que lo recibe todo el que
	# esté dentro.
	damage_players_in_disc(global_position, shockwave_radius,
			shockwave_height_window, shockwave_damage, self)


## Un slot para la tapa, así un mordisco durante un entierro (o al revés)
## reemplaza la animación de la tapa en vez de pelearse con ella.
func _play_lid(target_x: float, duration: float) -> void:
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	_lid_tween = create_tween()
	_lid_tween.tween_property(_lid_pivot, "rotation:x", target_x, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
