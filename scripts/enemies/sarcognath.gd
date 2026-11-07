class_name Sarcognath
extends BossBase
## Sarcognato, jefe de las Dunas de Ceniza: un enorme sarcófago-chacal que
## acecha flotando. Moveset con el patrón de máquina de estados del Rotking:
## Rayo de barrido (línea de aviso que gira y después un láser radial que
## barre un arco: corre con él, salta la línea o párate en el hueco),
## Ataúdes de arena (un anillo de discos alrededor del raider con un hueco y
## un disco extra a sus pies: encuentra el hueco) y Sepultar, una vez por
## umbral de vida, que inmoviliza a quien quede en su disco
## (Player.apply_root; las armas siguen disparando). Título, grados y pago
## viven en BossBase; la revancha Elder llega por apply_tier().
## Colores de aviso (Sepultar) e impacto: grupo Telegrafía de Sarcognath.tscn;
## líneas del barrido: nodos WarnLine y Beam; púas: SandSpikes.tscn.

enum State { ENTRANCE, PURSUE, SWEEP, COFFINS, ENTOMB }

@export_group("Llegada")
## Segundos del estado de llegada antes de empezar a pelear.
@export var entrance_duration: float = 1.0
## Radio en metros del anillo de destello de la llegada.
@export var entrance_ring_radius: float = 3.0

@export_group("Sweep Beam")
@export var sweep_windup: float = 1.0
@export var sweep_duration: float = 3.0
@export var sweep_arc_deg: float = 120.0
@export var sweep_length: float = 15.0
@export var sweep_tick_damage: float = 8.0
@export var sweep_tick_interval: float = 0.5
@export var sweep_cooldown: float = 8.0
@export var sweep_max_range: float = 14.0
## Medio ancho angular de la cuña de golpe del rayo.
@export var sweep_hit_half_angle_deg: float = 7.0
## El rayo barre a la altura del pecho: unos pies más altos que esto sobre
## los del jefe (un salto a tiempo, una mesa) le pasan por encima.
@export var sweep_height_window: float = 1.2
@export var beam_height: float = 0.9
## Segundos de espera al aparecer antes del primer barrido.
@export var first_sweep_delay: float = 3.0
## Grados que avanza la línea de aviso hacia el arco durante la carga.
@export var warn_lead_deg: float = 12.0
## Grosor en metros de la línea de aviso al empezar la carga.
@export var warn_width_start: float = 0.04
## Grosor en metros de la línea de aviso al terminar la carga.
@export var warn_width_end: float = 0.16

@export_group("Sand Coffins")
@export var coffin_interval: float = 6.0
## Fracción de coffin_interval que espera la primera tanda al aparecer (0-1).
@export var first_coffin_fraction: float = 0.6
## Color de los discos de aviso de los ataúdes (Sepultar usa telegraph_color).
@export var coffin_telegraph_color: Color = Color(0.95, 0.72, 0.28)
## Fuerza del temblor de cámara cuando caen los ataúdes (0-1).
@export var coffin_shake_strength: float = 0.2
## Segundos del temblor de cámara cuando caen los ataúdes.
@export var coffin_shake_duration: float = 0.4
@export var coffin_windup: float = 1.0
## Huecos repartidos en anillo alrededor del raider; uno al azar queda vacío
## (el escape) y un disco extra cae a sus pies.
@export var coffin_ring_slots: int = 5
@export var coffin_ring_radius: float = 2.6
@export var coffin_radius: float = 1.6
@export var coffin_damage: float = 12.0
@export var coffin_min_range: float = 3.0
@export var coffin_max_range: float = 18.0
@export var coffin_height_window: float = 1.5

@export_group("Entomb")
## Fracciones de vida (de mayor a menor) que disparan un Sepultar cada una
## cuando el jefe las cruza.
@export var entomb_thresholds: Array[float] = [0.66, 0.33]
@export var entomb_windup: float = 1.2
@export var entomb_radius: float = 2.0
@export var entomb_damage: float = 10.0
@export var entomb_root_duration: float = 1.5
@export var entomb_height_window: float = 1.5

@export_group("Flotación")
## Velocidad del vaivén vertical (radianes por segundo).
@export var hover_speed: float = 2.0
## Amplitud del vaivén vertical en metros.
@export var hover_amplitude: float = 0.09

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _sweep_cooldown_timer: float = 0.0
var _sweep_firing: bool = false
var _sweep_angle: float = 0.0
var _sweep_sign: float = 1.0
## Ritmo de quemadura POR raider (instance id -> segundos hasta volver a
## quemarlo). El rayo es un ataque de área: dos raiders dentro se queman
## cada uno a su propio sweep_tick_interval en vez de compartir uno.
var _sweep_tick_cd: Dictionary[int, float] = {}
var _coffin_timer: float = 0.0
var _coffin_spots: Array[Vector3] = []
var _entomb_spot: Vector3 = Vector3.ZERO
var _thresholds_remaining: Array[float] = []
var _pending_entombs: int = 0
var _hover_time: float = 0.0
var _hover_base: float = 0.0

@onready var _warn_line: BeamVisual = $WarnLine
@onready var _beam: BeamVisual = $Beam


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_sweep_cooldown_timer = first_sweep_delay
	_coffin_timer = coffin_interval * first_coffin_fraction
	_thresholds_remaining = entomb_thresholds.duplicate()
	_hover_base = _visual.position.y
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_sarcognath_died)


func _behavior_tick(delta: float) -> void:
	_hover_time += delta
	_visual.position.y = _hover_base + sin(_hover_time * hover_speed) * hover_amplitude
	_sweep_cooldown_timer = maxf(_sweep_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_coffin_timer = maxf(_coffin_timer - delta, 0.0)
		return
	_tick_entrance(_state == State.ENTRANCE)
	_state_timer -= delta
	if _state == State.SWEEP:
		_tick_sweep(delta)
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.SWEEP:
			_advance_sweep_phase()
		State.COFFINS:
			_resolve_coffins()
		State.ENTOMB:
			_resolve_entomb()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	# Los ataques (y la entrada) pausan el acecho flotante.
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	if _state == State.SWEEP:
		# La cresta sigue a su propio rayo mientras barre.
		return Vector3(cos(_sweep_angle), 0.0, sin(_sweep_angle))
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _pending_entombs > 0:
		_start_entomb(player)
		return
	if _sweep_cooldown_timer <= 0.0 and distance <= sweep_max_range:
		_start_sweep(player)
		return
	if _coffin_timer <= 0.0 \
			and distance >= coffin_min_range and distance <= coffin_max_range:
		_start_coffins(player)


func _scale_attack_damage(multiplier: float) -> void:
	sweep_tick_damage *= multiplier
	coffin_damage *= multiplier
	entomb_damage *= multiplier


## Se alza de un anillo de destello con la segunda voz de rugido.
func _play_entrance() -> void:
	Sfx.play(&"boss_roar_2")
	_play_boss_entrance(entrance_ring_radius, impact_color)


# --- Rayo de barrido -----------------------------------------------------------

func _start_sweep(player: Node3D) -> void:
	_state = State.SWEEP
	_sweep_firing = false
	_state_timer = sweep_windup
	_sweep_sign = 1.0 if randf() < 0.5 else -1.0
	var to_player := player.global_position - global_position
	var player_angle := atan2(to_player.z, to_player.x)
	# Empieza medio arco antes del rumbo del raider para que el rayo cruce su
	# punto a mitad del barrido: quieto te alcanza; muévete con él, salta la
	# línea o métete en los 240 grados que nunca cubre.
	_sweep_angle = player_angle - _sweep_sign * deg_to_rad(sweep_arc_deg) * 0.5


func _tick_sweep(delta: float) -> void:
	var origin := global_position + Vector3.UP * beam_height
	if not _sweep_firing:
		# Línea de aviso: avanza unos grados hacia el arco que viene (se lee
		# como sentido de giro) y engorda a medida que se acaba la carga.
		var progress := 1.0 - clampf(_state_timer / sweep_windup, 0.0, 1.0)
		var warn_angle := _sweep_angle + progress * deg_to_rad(warn_lead_deg) * _sweep_sign
		var warn_to := origin \
				+ Vector3(cos(warn_angle), 0.0, sin(warn_angle)) * sweep_length
		_warn_line.span(origin, warn_to, lerpf(warn_width_start, warn_width_end, progress))
		return
	_sweep_angle += deg_to_rad(sweep_arc_deg) / sweep_duration * delta * _sweep_sign
	var beam_to := origin \
			+ Vector3(cos(_sweep_angle), 0.0, sin(_sweep_angle)) * sweep_length
	_beam.span(origin, beam_to)
	# Todo raider que cruza la cuña se quema, cada uno a su ritmo: el láser es
	# un área de 120 grados, no un ataque a un solo objetivo.
	for player: Node3D in Coop.alive_players(get_tree()):
		var id := player.get_instance_id()
		var cooldown := maxf(float(_sweep_tick_cd.get(id, 0.0)) - delta, 0.0)
		_sweep_tick_cd[id] = cooldown
		if cooldown > 0.0 or not _sweep_contact(player):
			continue
		var player_health := Health.find_in(player)
		if player_health == null or player_health.is_dead:
			continue
		_sweep_tick_cd[id] = sweep_tick_interval
		player_health.take_damage(sweep_tick_damage, false, self)


## True mientras el raider está en la cuña actual del rayo: dentro de su
## alcance, de su ancho angular y por debajo de la ventana de altura.
func _sweep_contact(player: Node3D) -> bool:
	var to_player := player.global_position - global_position
	var height := to_player.y
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > sweep_length or dist < 0.2:
		return false
	if absf(height) > sweep_height_window:
		return false
	var player_angle := atan2(to_player.z, to_player.x)
	return absf(angle_difference(_sweep_angle, player_angle)) \
			<= deg_to_rad(sweep_hit_half_angle_deg)


func _advance_sweep_phase() -> void:
	if not _sweep_firing:
		_sweep_firing = true
		_state_timer = sweep_duration
		_sweep_tick_cd.clear()
		_warn_line.clear()
		_beam.start_hum()
		return
	_end_sweep()


func _end_sweep() -> void:
	_state = State.PURSUE
	_sweep_firing = false
	_sweep_cooldown_timer = sweep_cooldown
	# Se vacía en vez de conservarse: los ids de raiders que se fueron (o
	# murieron) quedarían en el mapa el resto de la pelea.
	_sweep_tick_cd.clear()
	_beam.clear()


# --- Ataúdes de arena ----------------------------------------------------------

func _start_coffins(player: Node3D) -> void:
	_state = State.COFFINS
	_state_timer = coffin_windup
	_coffin_timer = coffin_interval
	_coffin_spots.clear()
	# Recortado como los huecos del anillo: un raider fuera del borde de la
	# arena (trepadores recortados, empujones) recibiría un disco fuera del campo.
	var base := _clamp_to_arena(player.global_position)
	_coffin_spots.append(base)  # el disco sobre el raider obliga a moverse
	var base_angle := randf() * TAU
	var gap_slot := randi_range(0, coffin_ring_slots - 1)
	for i in coffin_ring_slots:
		if i == gap_slot:
			continue
		var slot_angle := base_angle + TAU * float(i) / float(coffin_ring_slots)
		_coffin_spots.append(_clamp_to_arena(base
				+ Vector3(cos(slot_angle), 0.0, sin(slot_angle)) * coffin_ring_radius))
	for spot: Vector3 in _coffin_spots:
		Telegraph.spawn_disc(self, spot, coffin_radius, coffin_windup, coffin_telegraph_color)


func _resolve_coffins() -> void:
	_state = State.PURSUE
	Juice.shake(coffin_shake_strength, coffin_shake_duration)
	for spot: Vector3 in _coffin_spots:
		_spawn_spike_cluster(spot, coffin_radius * 0.5)
	# Contra los PUNTOS marcados y todo el equipo: el raider alrededor del que
	# se dibujó el anillo puede ya no ser el más cercano.
	damage_players_in_discs(_coffin_spots, coffin_radius, coffin_height_window,
			coffin_damage, self)


# --- Sepultar ------------------------------------------------------------------

func _start_entomb(player: Node3D) -> void:
	_state = State.ENTOMB
	_state_timer = entomb_windup
	_pending_entombs -= 1
	# Marcado a los pies del raider: si sigue moviéndose, falla del todo.
	_entomb_spot = _clamp_to_arena(player.global_position)
	Telegraph.spawn_disc(self, _entomb_spot, entomb_radius, entomb_windup, telegraph_color)


func _resolve_entomb() -> void:
	_state = State.PURSUE
	_spawn_spike_cluster(_entomb_spot, coffin_radius * 0.5)
	# Todo el que quede en el disco marcado queda inmovilizado, no solo el más
	# cercano: la marca es la promesa que todos pudieron ver.
	for caught: Node3D in _resolve_ground_hit([_entomb_spot], entomb_radius,
			entomb_height_window, entomb_damage):
		var body := caught as Player
		if body != null:
			body.apply_root(entomb_root_duration)


# --- piezas compartidas --------------------------------------------------------

func _on_damaged(_amount: float, current: float) -> void:
	var ratio := current / _health.max_hp
	# Cada umbral cruzado da su propio Sepultar, encadenados de a un estado ENTOMB.
	_pending_entombs += _consume_thresholds(_thresholds_remaining, ratio)


func _on_sarcognath_died() -> void:
	_warn_line.clear()
	_beam.clear()
