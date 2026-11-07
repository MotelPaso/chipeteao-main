class_name Grubthing
extends SecretBossBase
## Larvón, minijefe oculto del Bosque Hueco (GDD 6), lo despierta el Tocón
## raro: una larva gorda y pálida con un sombrero de hongo furioso. Moveset
## simple a propósito, con el patrón de máquina de estados de jefe: Salto
## embestida (disco de aterrizaje marcado al que se lanza; sal de él) y
## Escupitajo (tres bolas lentas en arco, cada una con su disco de
## salpicadura marcado). El pago, la barra de vida y el desbloqueo del
## personaje al morir viven en SecretBossBase. Colores de aviso e impacto:
## grupo Telegrafía de Grubthing.tscn; la bola del escupitajo: GrubGlob.tscn.

enum State { ENTRANCE, PURSUE, HOP_WINDUP, HOP_LEAP, HOP_RECOVER, SPIT }

## Distancia plana al punto de aterrizaje que termina un salto antes de tiempo.
const HOP_ARRIVAL_EPSILON: float = 0.35

@export_group("Llegada")
## Segundos del estado de llegada antes de empezar a pelear.
@export var entrance_duration: float = 0.8
## Radio en metros del anillo de destello de la llegada.
@export var entrance_ring_radius: float = 2.4

@export_group("Lunging Hop")
## Distancia al raider que dispara un salto (sin mínimo: también salta en el sitio).
@export var hop_max_range: float = 9.0
@export var hop_windup: float = 0.75
## Tiempo en el aire del salto hacia el punto marcado.
@export var hop_leap_time: float = 0.45
@export var hop_recover: float = 0.5
@export var hop_cooldown: float = 2.8
@export var hop_damage: float = 12.0
@export var hop_radius: float = 2.0
## El aplastón al caer es de suelo; un raider más alto que esto no lo recibe.
@export var hop_height_window: float = 1.4
## La velocidad del salto es distancia/tiempo en el aire, con este tope.
@export var hop_max_speed: float = 24.0

@export_group("Glob Spit")
@export var spit_min_range: float = 4.0
@export var spit_max_range: float = 16.0
@export var spit_interval: float = 5.5
@export var spit_windup: float = 1.0
## Fracción de spit_interval que espera el primer escupitajo al aparecer (0-1).
@export var first_spit_fraction: float = 0.5
@export var glob_count: int = 3
@export var glob_radius: float = 1.5
@export var glob_damage: float = 10.0
## La primera bola va al punto del raider; las demás se esparcen en este rango.
@export var glob_scatter: float = 2.4
@export var glob_height_window: float = 1.5
## Segundos del destello de cada salpicadura.
@export var glob_flash_time: float = 0.18
## Bola cosmética que vuela de la boca al disco (GrubGlob.tscn).
@export var glob_visual_scene: PackedScene
## Altura máxima en metros del arco de la bola.
@export var glob_arc_height: float = 2.2

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _hop_cooldown_timer: float = 0.0
var _hop_target: Vector3 = Vector3.ZERO
var _base_move_speed: float = 0.0
var _spit_timer: float = 0.0
var _glob_spots: Array[Vector3] = []


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_spit_timer = spit_interval * first_spit_fraction
	_base_move_speed = move_speed


func _scale_attack_damage(multiplier: float) -> void:
	hop_damage *= multiplier
	glob_damage *= multiplier


func _behavior_tick(delta: float) -> void:
	_hop_cooldown_timer = maxf(_hop_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_spit_timer = maxf(_spit_timer - delta, 0.0)
		return
	_tick_entrance(_state == State.ENTRANCE)
	if _state == State.HOP_LEAP:
		# Llegar antes igual se resuelve sobre el disco marcado.
		var to_target := _hop_target - global_position
		to_target.y = 0.0
		if to_target.length() <= HOP_ARRIVAL_EPSILON:
			_resolve_hop()
			return
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.HOP_WINDUP:
			_begin_leap()
		State.HOP_LEAP:
			_resolve_hop()
		State.HOP_RECOVER:
			_state = State.PURSUE
		State.SPIT:
			_resolve_spit()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	if _state == State.HOP_LEAP:
		var to_target := _hop_target - global_position
		to_target.y = 0.0
		return to_target.normalized() if to_target.length() > 0.001 else Vector3.ZERO
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	if _state == State.HOP_LEAP:
		return steer
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _hop_cooldown_timer <= 0.0 and distance <= hop_max_range:
		_start_hop(player)
		return
	if _spit_timer <= 0.0 \
			and distance >= spit_min_range and distance <= spit_max_range:
		_start_spit(player)


## Llegada reventando el suelo: sale de un anillo de destello donde lo puso
## el disparador.
func _play_entrance() -> void:
	Sfx.play(&"burrow_pop")
	Sfx.play(&"boss_roar", -3.0)
	_play_boss_entrance(entrance_ring_radius, impact_color)


# --- Salto embestida -----------------------------------------------------------

func _start_hop(player: Node3D) -> void:
	_state = State.HOP_WINDUP
	_state_timer = hop_windup
	_hop_target = _clamp_to_arena(player.global_position)
	# Un solo disco cubre la carga y el vuelo, así la promesa dura hasta caer.
	Telegraph.spawn_disc(self, _hop_target, hop_radius,
			hop_windup + hop_leap_time, telegraph_color)
	_play_cue_squash(Vector3(1.18, 0.62, 1.18), hop_windup)


func _begin_leap() -> void:
	_state = State.HOP_LEAP
	_state_timer = hop_leap_time
	var flat := _hop_target - global_position
	flat.y = 0.0
	_base_move_speed = move_speed
	move_speed = minf(flat.length() / maxf(hop_leap_time, 0.05), hop_max_speed)
	# Arco solo visual: el cuerpo sube y baja mientras el chasis avanza.
	var cue := _begin_cue()
	cue.tween_property(_visual, "scale", Vector3(0.85, 1.25, 0.85), 0.1)
	cue.parallel().tween_property(_visual, "position:y", 1.1, hop_leap_time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cue.tween_property(_visual, "position:y", 0.0, hop_leap_time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _resolve_hop() -> void:
	_state = State.HOP_RECOVER
	_state_timer = hop_recover
	_hop_cooldown_timer = hop_cooldown
	move_speed = _base_move_speed
	Sfx.play(&"burrow_pop", -2.0)
	# La señal de aplastarse de abajo mata el tween del arco; un salto que
	# llegó ANTES de tiempo dejaría el rig en el aire, así que se baja a mano.
	_visual.position.y = 0.0
	_play_cue_squash(Vector3.ONE, 0.25)
	_resolve_ground_hit([_hop_target], hop_radius, hop_height_window, hop_damage)


# --- Escupitajo ----------------------------------------------------------------

func _start_spit(player: Node3D) -> void:
	_state = State.SPIT
	_state_timer = spit_windup
	_spit_timer = spit_interval
	_glob_spots.clear()
	var base := player.global_position
	for i in glob_count:
		var spot := base
		if i > 0:
			var angle := randf() * TAU
			spot += Vector3(cos(angle), 0.0, sin(angle)) \
					* randf_range(glob_scatter * 0.4, glob_scatter)
		_glob_spots.append(_clamp_to_arena(spot))
	var mouth := global_position + Vector3.UP * 1.1
	for spot: Vector3 in _glob_spots:
		Telegraph.spawn_disc(self, spot, glob_radius, spit_windup, telegraph_color)
		_launch_glob_visual(mouth, spot + Vector3.UP * 0.1, spit_windup)
	_play_cue_squash(Vector3(0.92, 1.16, 0.92), 0.25)


func _resolve_spit() -> void:
	_state = State.PURSUE
	_play_cue_squash(Vector3.ONE, 0.25)
	for spot: Vector3 in _glob_spots:
		Telegraph.spawn_disc(self, spot, glob_radius, glob_flash_time, impact_color)
	# Un golpe máximo POR RAIDER donde las salpicaduras se solapan.
	damage_players_in_discs(_glob_spots, glob_radius, glob_height_window,
			glob_damage, self)


## Bola cosmética: vuela en arco de la boca al punto de salpicadura durante
## la carga y se libera sola. El daño sigue en la resolución del disco.
func _launch_glob_visual(from: Vector3, to: Vector3, duration: float) -> void:
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null or glob_visual_scene == null:
		return
	var glob := glob_visual_scene.instantiate() as Node3D
	scene_root.add_child(glob)
	glob.global_position = from
	# Arco cuadrático: interpolación lineal más una elevación parabólica
	# 4t(1-t) (máxima a mitad de vuelo, cero en ambos extremos).
	var slide := func(t: float) -> void:
		var pos := from.lerp(to, t)
		pos.y += glob_arc_height * 4.0 * t * (1.0 - t)
		glob.global_position = pos
	var tween := glob.create_tween()
	tween.tween_method(slide, 0.0, 1.0, duration)
	tween.tween_callback(glob.queue_free)


func _play_cue_squash(target: Vector3, duration: float) -> void:
	_play_cue(_visual, "scale", target, duration)
