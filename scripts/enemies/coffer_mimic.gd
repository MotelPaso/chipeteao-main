class_name CofferMimic
extends SecretBossBase
## Cofre Mímico, minijefe oculto de las Dunas de Ceniza (GDD 6), lo atrae
## el Cráneo zumbante: un cofre de arenisca con patas de cangrejo y fauces
## de dientes dorados. Se mueve en ráfagas rápidas con pausas cortas,
## Muerde cuerpo a cuerpo (breve carga marcada sobre el punto del mordisco)
## y cada tanto se Entierra (solo asoma la tapa, con armadura extra) antes
## de salir con una onda de choque marcada. El pago, la barra de vida y el
## desbloqueo del personaje al morir viven en SecretBossBase. Colores de
## aviso e impacto: grupo Telegrafía de CofferMimic.tscn.

enum State { ENTRANCE, PURSUE, SNAP_WINDUP, SNAP_RECOVER, BURIED }

## Ángulo de la tapa enterrado: cerrada del todo, solo se ve arena.
const LID_CLOSED_ANGLE: float = 0.0
## Cuánto se abren las fauces durante la carga del mordisco.
const LID_GAPE_ANGLE: float = 1.15

@export_group("Llegada")
## Segundos del estado de llegada antes de empezar a pelear.
@export var entrance_duration: float = 0.8
## Radio en metros del anillo de destello de la llegada.
@export var entrance_ring_radius: float = 2.4

@export_group("Correteo")
## Segundos de cada ráfaga de carrera, a la move_speed del chasis.
@export var scuttle_burst_time: float = 0.8
## Segundos de cada pausa quieto entre ráfagas.
@export var scuttle_rest_time: float = 0.6

@export_group("Mordisco")
## Distancia al raider, en metros, que dispara un mordisco.
@export var snap_range: float = 2.4
## Radio en metros del disco del mordisco alrededor del punto que fijan las fauces.
@export var snap_radius: float = 1.8
## Daño del mordisco a cada raider dentro del disco (valor base; apply_tier lo escala).
@export var snap_damage: float = 14.0
## Segundos de aviso entre el disco y el mordisco.
@export var snap_windup: float = 0.45
## Segundos quieto después del mordisco antes de volver a moverse.
@export var snap_recover: float = 0.55
## Segundos de espera entre un mordisco y el siguiente.
@export var snap_cooldown: float = 2.2
## Metros sobre el suelo por encima de los cuales el mordisco no golpea.
@export var snap_height_window: float = 1.3
## Segundos del destello del mordisco (más corto que el impacto común).
@export var snap_flash_time: float = 0.15

@export_group("Enterrarse")
## Segundos de espera entre un entierro y el siguiente.
@export var bury_interval: float = 8.0
## Segundos enterrado (también el aviso de la onda al salir).
@export var bury_duration: float = 2.0
## Armadura plana que se suma a Health mientras está enterrado (con la de la escena, golpes menores que el total hacen 1).
@export var bury_armor_bonus: float = 6.0
## Metros que se hunde el cuerpo: ajustado para que solo asome la tapa.
@export var bury_sink_depth: float = 0.85
## Radio de la onda de choque al salir y de su disco de aviso, en metros.
@export var shockwave_radius: float = 3.0
## Daño de la onda a cada raider dentro del radio (valor base; apply_tier lo escala).
@export var shockwave_damage: float = 10.0
## Metros sobre el suelo por encima de los cuales la onda no golpea.
@export var shockwave_height_window: float = 1.5

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
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
	_tick_entrance(_state == State.ENTRANCE)
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
	_play_boss_entrance(entrance_ring_radius, impact_color)


# --- Mordisco ------------------------------------------------------------------

func _start_snap(player: Node3D) -> void:
	_state = State.SNAP_WINDUP
	_state_timer = snap_windup
	_snap_point = _clamp_to_arena(player.global_position)
	Telegraph.spawn_disc(self, _snap_point, snap_radius, snap_windup, telegraph_color)
	_play_lid(LID_GAPE_ANGLE, snap_windup)


func _resolve_snap() -> void:
	_state = State.SNAP_RECOVER
	_state_timer = snap_recover
	_snap_cooldown_timer = snap_cooldown
	Telegraph.spawn_disc(self, _snap_point, snap_radius, snap_flash_time, impact_color)
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
			bury_duration, telegraph_color)
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
	Sfx.play(&"burrow_pop")
	_play_cue(_visual, "position:y", 0.0, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	# Enterrarse cerró la tapa; al salir hay que abrirla a su ángulo de
	# reposo o el cofre sigue peleando sellado el resto de la partida.
	_play_lid(_lid_rest_angle, 0.2)
	# El anillo de la onda se marca para todos, así que lo recibe todo el que
	# esté dentro.
	_resolve_ground_hit([global_position], shockwave_radius,
			shockwave_height_window, shockwave_damage)


## Un slot para la tapa, así un mordisco durante un entierro (o al revés)
## reemplaza la animación de la tapa en vez de pelearse con ella.
func _play_lid(target_x: float, duration: float) -> void:
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	_lid_tween = create_tween()
	_lid_tween.tween_property(_lid_pivot, "rotation:x", target_x, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
