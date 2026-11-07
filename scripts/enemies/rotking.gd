class_name Rotking
extends BossBase
## Rey Pútrido, jefe del Bosque Hueco: un treant podrido que acecha despacio
## y pelea con una pequeña máquina de estados sobre los hooks de EnemyBase.
## Moveset: Aplastón cercano (onda de choque en área, se esquiva saltando o
## saliendo), Estallido de raíces a media distancia (tres puntos marcados que
## revientan en púas de corteza) y una Invocación de esbirros cada vez que
## su vida cruza un umbral exportado. Título, grados, pago y recorte de
## arena viven en BossBase; el spawner sube la revancha Elder con apply_tier().
## Colores de aviso e impacto: grupo Telegrafía de Rotking.tscn; púas de
## corteza: BarkSpikes.tscn.

enum State { ENTRANCE, PURSUE, SMASH, ROOT_BURST, SUMMON }

@export_group("Llegada")
## Segundos que el jefe se queda quieto al aparecer antes de perseguir.
@export var entrance_duration: float = 0.9

@export_group("Aplastón")
## Distancia al raider, en metros, a la que empieza el Aplastón.
@export var smash_range: float = 3.5
## Radio de la onda de choque y de su disco de aviso, en metros.
@export var smash_radius: float = 4.0
## Daño de la onda a cada raider dentro del radio (valor base; apply_tier lo escala).
@export var smash_damage: float = 25.0
## Segundos de aviso entre el disco y el golpe.
@export var smash_windup: float = 0.7
## Segundos quieto después del golpe antes de volver a perseguir.
@export var smash_recover: float = 0.8
## Segundos de espera entre un Aplastón y el siguiente.
@export var smash_cooldown: float = 3.0
## Metros sobre los pies del jefe por encima de los cuales la onda no golpea (un salto a tiempo la esquiva).
@export var smash_height_window: float = 1.2

@export_group("Estallido de raíces")
## Segundos de espera entre un Estallido de raíces y el siguiente.
@export var root_burst_interval: float = 6.0
## Segundos de aviso entre los discos y las púas.
@export var root_burst_windup: float = 0.9
## Radio de cada punto de púas y de su disco de aviso, en metros.
@export var root_burst_radius: float = 1.5
## Daño de las púas a cada raider alcanzado, una vez aunque los discos se solapen (valor base; apply_tier lo escala).
@export var root_burst_damage: float = 15.0
## Distancia en metros de los dos puntos laterales al del raider; quedan en línea y dejan un pasillo de escape.
@export var root_burst_spread: float = 2.6
## Distancia mínima al raider, en metros, para usar el Estallido.
@export var root_burst_min_range: float = 3.5
## Distancia máxima al raider, en metros, para usar el Estallido.
@export var root_burst_max_range: float = 16.0
## Metros sobre el suelo por encima de los cuales las púas no golpean.
@export var spike_height_window: float = 1.5

@export_group("Invocación")
## Fracciones de vida (0-1, de mayor a menor) que disparan una oleada de esbirros cada una al cruzarlas.
@export var summon_thresholds: Array[float] = [0.75, 0.5, 0.25]
## Escena del esbirro que invoca (su raíz debe extender EnemyBase).
@export var summon_scene: PackedScene
## Mínimo de esbirros por oleada.
@export var summon_count_min: int = 4
## Máximo de esbirros por oleada.
@export var summon_count_max: int = 6
## Radio en metros del anillo donde aparecen los esbirros.
@export var summon_ring_radius: float = 3.2
## Segundos del rugido de invocación; los esbirros salen al terminar.
@export var summon_duration: float = 1.1

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
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
	_tick_entrance(_state == State.ENTRANCE)
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
	_play_boss_entrance(smash_radius * 0.75, impact_color)


func _start_smash() -> void:
	_state = State.SMASH
	_state_timer = smash_windup
	_smash_resolved = false
	Telegraph.spawn_disc(self, global_position, smash_radius, smash_windup, telegraph_color)
	_play_cue_lean(-0.38, smash_windup)


func _resolve_smash() -> void:
	_smash_resolved = true
	_state_timer = smash_recover
	_smash_cooldown_timer = smash_cooldown
	_play_cue_lean(0.0, 0.25)
	# La onda se dibuja para todo el equipo, así que golpea a todo el equipo.
	_resolve_ground_hit([global_position], smash_radius, smash_height_window,
			smash_damage)


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
		Telegraph.spawn_disc(self, spot, root_burst_radius, root_burst_windup, telegraph_color)


func _resolve_root_burst() -> void:
	_state = State.PURSUE
	for spot: Vector3 in _root_spots:
		_spawn_spike_cluster(spot, root_burst_radius * 0.5)
	# Contra los PUNTOS marcados, no contra el más cercano ahora: los discos
	# eran la promesa, y un golpe máximo por raider aunque se solapen. Sin
	# destello: las púas son el impacto.
	_resolve_ground_hit(_root_spots, root_burst_radius, spike_height_window,
			root_burst_damage, false)


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
	# Cada umbral cruzado da su propia oleada, encadenadas de a un estado SUMMON.
	_pending_summons += _consume_thresholds(_thresholds_remaining, ratio)


func _play_cue_lean(target_x: float, duration: float) -> void:
	_play_cue(_visual, "rotation:x", target_x, duration)
