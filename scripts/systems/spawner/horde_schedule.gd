class_name HordeSchedule
extends RefCounted
## Hordas y ráfagas de presión. Una horda llega en los horde_minutes de la
## etapa (RunState.stage_time) y luego cada horde_repeat_minutes, repartida
## en horde_waves oleadas alrededor de un raider al azar. Las ráfagas de
## presión (oleadas de horda, jauría shiny del WorldDirector) y los puntos de
## lluvia y tsunami del nodo Weather caen encima de la cadencia normal, con
## su propio presupuesto sobre max_active.
## Los valores son exports del spawner (grupos «Hordas», «Oleadas de
## presión» y «Cupo de enemigos»): cada arena los guarda en su nodo
## EnemySpawner.
## No procesa solo: EnemySpawner llama tick() desde su _physics_process, así
## que detener al spawner también lo detiene.

## Edita aquí. Radianes que un hueco de ráfaga puede desviarse de su posición
## pareja en el anillo, para que el cerco se vea orgánico y no geométrico.
const BURST_ANGLE_JITTER: float = 0.35

var _spawner: EnemySpawner = null
var _points: SpawnPoints = null
var _hordes_fired: int = 0
var _horde_waves_left: int = 0
var _horde_wave_timer: float = 0.0
var _horde_wave_size: int = 0


func _init(spawner: EnemySpawner, points: SpawnPoints) -> void:
	_spawner = spawner
	_points = points


## Avanza la horda en curso o dispara la siguiente cuando vence su minuto.
func tick(delta: float) -> void:
	var spawner := _spawner
	if _horde_waves_left > 0:
		_horde_wave_timer -= delta
		if _horde_wave_timer <= 0.0:
			# Primero el ancla: con toda la party derribada no hay a quién
			# rodear, y gastar la oleada igual achicaría una horda anunciada.
			# Se reintenta en el próximo tick.
			var anchor := Coop.random_player(spawner.get_tree())
			if anchor == null:
				return
			_horde_wave_timer = spawner.horde_wave_gap
			_horde_waves_left -= 1
			pressure_burst(anchor.global_position, _horde_wave_size, false, true)
		return
	if RunState.stage_time < next_horde_time():
		return
	_hordes_fired += 1
	var size := int((float(spawner.horde_base_size)
			+ spawner.horde_size_per_minute * spawner.run_minutes())
			* (1.0 + RunState.difficulty_bonus)
			* (1.0 + spawner.coop_horde_per_extra_player
					* SpawnScaling.coop_extra_alive(spawner.get_tree()))
			* (spawner.endless_horde_mult if RunState.stage_cleared else 1.0)
			* spawner.spawn_count_multiplier)
	_horde_wave_size = maxi(ceili(float(size) / float(maxi(spawner.horde_waves, 1))), 1)
	_horde_waves_left = spawner.horde_waves
	_horde_wave_timer = 0.0
	spawner.get_tree().call_group("boss_ui", "announce", spawner.horde_warning_text)
	# Se loguea lo que de verdad se pide: redondear hacia arriba el tamaño
	# de oleada puede pasar el `size` crudo hasta en horde_waves - 1, y este
	# log es la única vista de la horda que tienen los soaks.
	print("Horde: %d enemies in %d waves at %.1fs" % [
			_horde_wave_size * spawner.horde_waves, spawner.horde_waves, RunState.stage_time])


## Segundo de etapa en que llega la próxima horda.
func next_horde_time() -> float:
	var minutes := _spawner.horde_minutes
	if _hordes_fired < minutes.size():
		return minutes[_hordes_fired] * 60.0
	var last := minutes[minutes.size() - 1] if not minutes.is_empty() else 0.0
	return (last + _spawner.horde_repeat_minutes
			* float(_hordes_fired - minutes.size() + 1)) * 60.0


## Ráfaga de `count` enemigos de la fase actual en la banda
## surge_min_radius-surge_max_radius alrededor de `center`. Ver
## EnemySpawner.spawn_pressure_burst.
## Orden del RNG: por hueco, el desvío de ángulo y luego la banda.
func pressure_burst(center: Vector3, count: int, force_elites: bool, horde: bool) -> int:
	var spawner := _spawner
	if Coop.alive_player_count(spawner.get_tree()) <= 0:
		return 0
	var budget := mini(count, _cap(horde) - spawner.live_enemy_count())
	var spawned := 0
	for i in budget:
		# Huecos parejos en el anillo con desvío, para que rodee sin amontonar.
		var angle := TAU * float(i) / float(budget) \
				+ randf_range(-BURST_ANGLE_JITTER, BURST_ANGLE_JITTER)
		# Un hueco bloqueado gira dentro de la banda de OLEADA, nunca hacia el
		# anillo lejano: un punto junto a un muro debe seguir sintiéndose como
		# "aguanta aquí bajo presión".
		var pos := _points.on_ground(_points.band_position(center,
				spawner.surge_min_radius, spawner.surge_max_radius, angle))
		if spawner.make_enemy_at(pos, force_elites) != null:
			spawned += 1
	return spawned


## Un enemigo en cada uno de `points`, a ras de suelo. Ver
## EnemySpawner.spawn_at_points.
func spawn_at_points(points: Array[Vector3], horde: bool) -> int:
	var budget := _cap(horde) - _spawner.live_enemy_count()
	if budget <= 0:
		return 0
	var made := 0
	for point: Vector3 in points:
		if made >= budget:
			break
		if _spawner.make_enemy_at(_points.on_ground(point)) != null:
			made += 1
	return made


## Tope de vivos de una ráfaga: max_active más horde_overflow si `horde`, o
## pressure_overflow si no.
func _cap(horde: bool) -> int:
	return _spawner.max_active + (
			_spawner.horde_overflow if horde else _spawner.pressure_overflow)
