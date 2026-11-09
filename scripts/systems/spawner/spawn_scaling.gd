class_name SpawnScaling
extends RefCounted
## Escalado de stats de los spawns nuevos: vuelta, rampa tardía,
## pseudo-infinito, tamaño de la party, evento de cielo y el buff temporal
## de la ruleta. También lleva el estado del evento de cielo y del buff.
## Los valores son exports del spawner (grupos «Vueltas y pseudo-infinito»,
## «Rampa tardía», «Co-op» y «Eventos de cielo»): cada arena los guarda en su
## nodo EnemySpawner.
## No procesa solo: EnemySpawner llama tick() y tick_endless_log() desde su
## _physics_process, así que detener al spawner también lo detiene.

## Evento de cielo activo (nodo Weather del WorldDirector): "" | "blood_moon"
## | "eclipse". Lo lee la cadencia del spawner.
var sky_kind: String = ""

var _spawner: EnemySpawner = null
## Segundos que le quedan al evento de cielo.
var _sky_left: float = 0.0
## Buff temporal de enemigos (frenesí de la ruleta): multiplicador y segundos.
var _temp_buff_multiplier: float = 1.0
var _temp_buff_left: float = 0.0
## Último minuto pseudo-infinito ya anunciado, para que el log salga una vez
## por minuto y no una vez por frame.
var _endless_minute_logged: int = -1


func _init(spawner: EnemySpawner) -> void:
	_spawner = spawner


## La party que sigue en pie. Un raider derribado sale del grupo "player"
## hasta que lo reanimen (ver coop.gd), así que la presión por tick (ritmo,
## HP de spawns nuevos, tamaño de horda) sigue a la pelea y no castiga al
## último en pie con la horda de cuatro.
static func coop_extra_alive(tree: SceneTree) -> float:
	return float(maxi(Coop.alive_player_count(tree) - 1, 0))


## La party configurada en el lobby: para lo que se dimensiona toda la
## partida (HP de jefe), esté quien esté derribado ahora.
static func coop_extra() -> float:
	return float(maxi(Coop.player_count - 1, 0))


## Descuenta los relojes del buff temporal y del evento de cielo; el cielo
## se apaga al vencer.
func tick(delta: float) -> void:
	_temp_buff_left = maxf(_temp_buff_left - delta, 0.0)
	_sky_left = maxf(_sky_left - delta, 0.0)
	if _sky_left <= 0.0 and not sky_kind.is_empty():
		sky_kind = ""


## Escalado por VUELTA: cada vuelta completa a la lista de mapas multiplica
## los spawns nuevos y los jefes.
func lap_hp_factor() -> float:
	return pow(_spawner.lap_hp_mult, float(RunState.lap))


func lap_damage_factor() -> float:
	return pow(_spawner.lap_damage_mult, float(RunState.lap))


func lap_xp_factor() -> float:
	return pow(_spawner.lap_xp_mult, float(RunState.lap))


## Superada la etapa, la party puede quedarse cuanto quiera y el mapa
## responde: por minuto de RunState.pseudo_infinite_time los spawns nuevos
## traen más HP, daño y velocidad, el intervalo se acorta y las hordas
## crecen. La velocidad tiene techo: un cuerpo más rápido que el raider no se
## puede esquivar.
func endless_minutes() -> float:
	return RunState.pseudo_infinite_time / 60.0 if RunState.stage_cleared else 0.0


func endless_hp_factor() -> float:
	return 1.0 + _spawner.endless_hp_per_minute * endless_minutes()


func endless_damage_factor() -> float:
	return 1.0 + _spawner.endless_damage_per_minute * endless_minutes()


func endless_speed_factor() -> float:
	return minf(1.0 + _spawner.endless_speed_per_minute * endless_minutes(),
			_spawner.endless_speed_cap)


func endless_interval_factor() -> float:
	return pow(_spawner.endless_interval_per_minute, endless_minutes())


## Factores de la rampa tardía para un spawn que cae ahora (1.0 antes de la
## rampa).
func late_hp_factor() -> float:
	return 1.0 + _spawner.late_hp_per_minute * _late_minutes()


func late_damage_factor() -> float:
	return 1.0 + _spawner.late_damage_per_minute * _late_minutes()


func late_xp_factor() -> float:
	return 1.0 + _spawner.late_xp_per_minute * _late_minutes()


## Arranca un evento de cielo por `duration` segundos; "" lo apaga.
func set_sky_event(kind: String, duration: float) -> void:
	sky_kind = kind
	_sky_left = duration if not kind.is_empty() else 0.0


## Renueva como EnemyBase.apply_poison: gana el multiplicador más fuerte y el
## temporizador más largo.
func apply_temp_buff(multiplier: float, duration: float) -> void:
	var live := _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0
	_temp_buff_multiplier = maxf(live, maxf(multiplier, 1.0))
	_temp_buff_left = maxf(_temp_buff_left, duration)


func temp_buff() -> float:
	return _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0


## Todo el escalado de stats de un spawn regular en un solo lugar: vuelta x
## pseudo-infinito x rampa tardía x HP de co-op x dificultad de la partida
## (más duros Y más ricos: la parte de XP la paga RunState).
## Orden del RNG: la tirada de variante de cielo va al final.
func scale_fresh_spawn(enemy: EnemyBase) -> void:
	var difficulty := (1.0 + RunState.difficulty_bonus) * temp_buff()
	enemy.apply_tier_scaling(
			lap_hp_factor() * endless_hp_factor() * late_hp_factor() * difficulty
					* _sky_hp_factor()
					* (1.0 + _spawner.coop_hp_per_extra_player
							* coop_extra_alive(_spawner.get_tree())),
			lap_damage_factor() * endless_damage_factor() * late_damage_factor()
					* difficulty * _sky_damage_factor(),
			lap_xp_factor() * late_xp_factor())
	# La velocidad es el canal propio de la rampa pseudo-infinita:
	# apply_tier_scaling solo cubre HP, daño y pago.
	enemy.move_speed *= endless_speed_factor()
	_apply_sky_variant(enemy)


## Una línea por minuto mientras corre la rampa pseudo-infinita, para que un
## soak pruebe que se movió.
func tick_endless_log() -> void:
	if not RunState.stage_cleared:
		_endless_minute_logged = -1
		return
	var minute := floori(endless_minutes())
	if minute <= _endless_minute_logged:
		return
	_endless_minute_logged = minute
	print("Pseudo-infinite: minute %d hp x%.2f dmg x%.2f speed x%.2f" % [
			minute, endless_hp_factor(), endless_damage_factor(),
			endless_speed_factor()])


## Minutos de partida pasados el inicio de la rampa tardía (0 antes).
func _late_minutes() -> float:
	return maxf(_spawner.run_minutes() - _spawner.late_ramp_start_minute, 0.0)


func _sky_hp_factor() -> float:
	return _spawner.eclipse_hp_multiplier if sky_kind == "eclipse" else 1.0


func _sky_damage_factor() -> float:
	return _spawner.blood_moon_damage_multiplier if sky_kind == "blood_moon" else 1.0


## Luna de sangre: algunos llegan como berserker. Eclipse: algunos llegan
## como sombra. Un randf solo con un evento activo.
func _apply_sky_variant(enemy: EnemyBase) -> void:
	match sky_kind:
		"blood_moon":
			if randf() < _spawner.blood_moon_berserker_chance:
				enemy.apply_variant("berserker")
		"eclipse":
			if randf() < _spawner.eclipse_shade_chance:
				enemy.apply_variant("shade")
