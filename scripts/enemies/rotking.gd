class_name Rotking
extends BossBase
## Rey Pútrido, jefe del Bosque Hueco: un treant podrido que acecha despacio
## y pelea con una pequeña máquina de estados sobre los hooks de EnemyBase.
## Moveset: Aplastón cercano (onda de choque en área, se esquiva saltando o
## saliendo), Estallido de raíces a media distancia (tres puntos marcados que
## revientan en púas de corteza) y una Invocación de esbirros cada vez que
## su vida cruza un umbral exportado. Título, grados, pago y recorte de
## arena viven en BossBase; el spawner sube la revancha Elder con apply_tier().

enum State { ENTRANCE, PURSUE, SMASH, ROOT_BURST, SUMMON }

const TELEGRAPH_COLOR := Color(1.0, 0.55, 0.12)
const IMPACT_COLOR := Color(1.0, 0.8, 0.35)
## Piel de corteza para el grupo de púas compartido.
const SPIKE_COLOR := Color(0.36, 0.26, 0.16)
const SPIKE_ROUGHNESS: float = 0.95
const SPIKE_BOTTOM_RADIUS: float = 0.16
const SPIKE_LENGTH: float = 1.1
const SPIKE_SINK_DEPTH: float = 1.2

@export var entrance_duration: float = 0.9

@export_group("Smash")
@export var smash_range: float = 3.5
@export var smash_radius: float = 4.0
@export var smash_damage: float = 25.0
@export var smash_windup: float = 0.7
@export var smash_recover: float = 0.8
@export var smash_cooldown: float = 3.0
## El golpe es una onda de suelo: un raider más alto que esto sobre los pies
## del jefe (un salto a tiempo, una cornisa) no la recibe.
@export var smash_height_window: float = 1.2

@export_group("Root Burst")
@export var root_burst_interval: float = 6.0
@export var root_burst_windup: float = 0.9
@export var root_burst_radius: float = 1.5
@export var root_burst_damage: float = 15.0
## Distancia de los dos puntos laterales al del raider; quedan en línea con
## él y dejan un pasillo de escape perpendicular.
@export var root_burst_spread: float = 2.6
@export var root_burst_min_range: float = 3.5
@export var root_burst_max_range: float = 16.0
@export var spike_height_window: float = 1.5

@export_group("Summon")
## Fracciones de vida (de mayor a menor) que disparan una oleada cada una
## cuando el jefe las cruza.
@export var summon_thresholds: Array[float] = [0.75, 0.5, 0.25]
@export var summon_scene: PackedScene
@export var summon_count_min: int = 4
@export var summon_count_max: int = 6
@export var summon_ring_radius: float = 3.2
@export var summon_duration: float = 1.1

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _smash_cooldown_timer: float = 0.0
var _smash_resolved: bool = false
var _root_burst_timer: float = 0.0
var _root_spots: Array[Vector3] = []
var _thresholds_remaining: Array[float] = []
var _pending_summons: int = 0


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_root_burst_timer = root_burst_interval
	_thresholds_remaining = summon_thresholds.duplicate()
	_health.damaged.connect(_on_damaged)


func _scale_attack_damage(multiplier: float) -> void:
	smash_damage *= multiplier
	root_burst_damage *= multiplier


func _behavior_tick(delta: float) -> void:
	_smash_cooldown_timer = maxf(_smash_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_root_burst_timer = maxf(_root_burst_timer - delta, 0.0)
		return
	if _state == State.ENTRANCE and not _entrance_played:
		# Fuera de _ready para que el spawner ya haya puesto la posición real
		# antes de que aparezca el anillo de llegada.
		_entrance_played = true
		_play_entrance()
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.SMASH:
			if _smash_resolved:
				_state = State.PURSUE
			else:
				_resolve_smash()
		State.ROOT_BURST:
			_resolve_root_burst()
		State.SUMMON:
			_resolve_summon()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	# Los ataques (y la entrada) pausan la persecución.
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _pending_summons > 0:
		_start_summon()
		return
	if _smash_cooldown_timer <= 0.0 and distance <= smash_range:
		_start_smash()
		return
	if _root_burst_timer <= 0.0 \
			and distance >= root_burst_min_range and distance <= root_burst_max_range:
		_start_root_burst(player)


## Llegada con golpe al suelo: la silueta sale de un anillo de destello.
func _play_entrance() -> void:
	Sfx.play(&"boss_roar")
	_play_boss_entrance(smash_radius * 0.75, IMPACT_COLOR)


func _start_smash() -> void:
	_state = State.SMASH
	_state_timer = smash_windup
	_smash_resolved = false
	Telegraph.spawn_disc(self, global_position, smash_radius, smash_windup, TELEGRAPH_COLOR)
	_play_cue_lean(-0.38, smash_windup)


func _resolve_smash() -> void:
	_smash_resolved = true
	_state_timer = smash_recover
	_smash_cooldown_timer = smash_cooldown
	Telegraph.spawn_disc(self, global_position, smash_radius, 0.2, IMPACT_COLOR)
	Juice.shake(0.2, 0.4)
	_play_cue_lean(0.0, 0.25)
	# La onda se dibuja para todo el equipo, así que golpea a todo el equipo;
	# nombrarse como atacante deja que las espinas respondan.
	damage_players_in_disc(global_position, smash_radius, smash_height_window,
			smash_damage, self)


func _start_root_burst(player: Node3D) -> void:
	_state = State.ROOT_BURST
	_state_timer = root_burst_windup
	_root_burst_timer = root_burst_interval
	_root_spots.clear()
	var base := _clamp_to_arena(player.global_position)
	_root_spots.append(base)
	var line_angle := randf() * TAU
	for i in 2:
		var spot_angle := line_angle + PI * float(i)
		_root_spots.append(_clamp_to_arena(base
				+ Vector3(cos(spot_angle), 0.0, sin(spot_angle)) * root_burst_spread))
	for spot: Vector3 in _root_spots:
		Telegraph.spawn_disc(self, spot, root_burst_radius, root_burst_windup, TELEGRAPH_COLOR)


func _resolve_root_burst() -> void:
	_state = State.PURSUE
	Juice.shake(0.2, 0.4)
	for spot: Vector3 in _root_spots:
		_spawn_spikes(spot)
	# Contra los PUNTOS marcados, no contra el más cercano ahora: los discos
	# eran la promesa, y un golpe máximo por raider aunque se solapen.
	damage_players_in_discs(_root_spots, root_burst_radius, spike_height_window,
			root_burst_damage, self)


func _start_summon() -> void:
	_state = State.SUMMON
	_state_timer = summon_duration
	# Se consume aquí y no al resolver: pase lo que pase con la oleada, el
	# umbral no puede volver a dispararse para siempre.
	_pending_summons -= 1
	# Señal de rugido: la silueta entera se infla y se asienta.
	var cue := _begin_cue()
	cue.tween_property(_visual, "scale", Vector3.ONE * 1.14, summon_duration * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cue.tween_property(_visual, "scale", Vector3.ONE, summon_duration * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _resolve_summon() -> void:
	_state = State.PURSUE
	if summon_scene == null:
		push_warning("Rotking: summon_scene is unset; the wave is lost.")
		return
	var parent := get_parent()
	if parent == null:
		return
	var count := randi_range(summon_count_min, summon_count_max)
	for i in count:
		var node := summon_scene.instantiate()
		var minion := node as EnemyBase
		if minion == null:
			# Una instancia mala no debe comerse el resto de la oleada en silencio.
			node.free()
			push_warning("Rotking: summon scene root does not extend EnemyBase.")
			continue
		parent.add_child(minion)
		var ring_angle := TAU * float(i) / float(count)
		# Respeta la máscara caminable: un esbirro dentro de un muro de
		# máscara pasaría la pelea trepando para salir de la roca.
		minion.global_position = _safe_arena_point(global_position
				+ Vector3(cos(ring_angle), 0.0, sin(ring_angle)) * summon_ring_radius
				+ Vector3.UP * 0.1)


func _on_damaged(_amount: float, current: float) -> void:
	var ratio := current / _health.max_hp
	# Un golpe grande puede cruzar varios umbrales a la vez; cada uno da su
	# propia oleada, encadenadas de a un estado SUMMON.
	while not _thresholds_remaining.is_empty() and ratio <= _thresholds_remaining[0]:
		_thresholds_remaining.remove_at(0)
		_pending_summons += 1


func _play_cue_lean(target_x: float, duration: float) -> void:
	_play_cue(_visual, "rotation:x", target_x, duration)


## Erupción rápida: un grupo de conos de corteza sale del suelo y se hunde
## (BossBase anima; estas constantes son la piel de corteza).
func _spawn_spikes(center: Vector3) -> void:
	_spawn_spike_cluster(center, root_burst_radius * 0.5, SPIKE_COLOR,
			SPIKE_ROUGHNESS, SPIKE_BOTTOM_RADIUS, SPIKE_LENGTH, SPIKE_SINK_DEPTH)
