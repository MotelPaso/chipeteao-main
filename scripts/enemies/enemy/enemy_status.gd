class_name EnemyStatus
extends RefCounted
## Estados temporales de un enemigo: ralentización, empuje, veneno y quemadura.
## Veneno y quemadura son daños por segundo independientes: corren a la vez,
## cada uno con su reloj. EnemyBase lo
## crea la primera vez que recibe uno (apply_slow / apply_poison), así los
## cuerpos que nunca lo reciben no pagan nada por frame.

## Segundos entre pulsos de daño del veneno. Edita aquí.
const POISON_TICK: float = 0.5
## Segundos entre pulsos de daño de la quemadura. Edita aquí.
const BURN_TICK: float = 0.5

var _health: Health
var _overlays: EnemyOverlays
## Multiplicador de velocidad activo mientras corre su reloj.
var _slow_multiplier: float = 1.0
var _slow_time_left: float = 0.0
## Resistencia a empujes y ralentizaciones (0-1): sube con cada golpe que lo
## empuja o frena y mientras está frenado, y baja cuando no, así un enemigo
## golpeado sin parar deja de quedar clavado.
var _slow_resist: float = 0.0
var _resist_per_hit: float = 0.0
var _resist_build: float = 0.0
var _resist_max: float = 0.0
var _resist_recovery: float = 0.0
var _poison_dps: float = 0.0
var _poison_time_left: float = 0.0
var _poison_tick_timer: float = 0.0
var _burn_dps: float = 0.0
var _burn_time_left: float = 0.0
var _burn_tick_timer: float = 0.0
## Empuje de los golpes (m/s, en el plano): se suma a su paso y se apaga
## a _push_decay metros por segundo cada segundo.
var _push: Vector3 = Vector3.ZERO
var _push_decay: float = 0.0


func _init(health: Health, overlays: EnemyOverlays) -> void:
	_health = health
	_overlays = overlays


## Ver EnemyBase.apply_slow: reaplicar refresca en vez de acumular, y ganan
## la ralentización más fuerte y el reloj más largo.
func apply_slow(speed_multiplier: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var incoming := clampf(speed_multiplier, 0.05, 1.0)
	var current := _slow_multiplier if _slow_time_left > 0.0 else 1.0
	_slow_multiplier = minf(current, incoming)
	_slow_time_left = maxf(_slow_time_left, duration)


## Ver EnemyBase.apply_hit_impact. Golpes seguidos no se acumulan sin fin:
## el empuje queda en el más fuerte de los dos (el que traía o el nuevo).
func apply_push(push: Vector3, decay: float) -> void:
	var cap := maxf(_push.length(), push.length())
	_push = (_push + push).limit_length(cap)
	_push_decay = maxf(decay, 0.0)


## Empuje actual en m/s (Vector3.ZERO sin empuje).
func push_velocity() -> Vector3:
	return _push


## Ver EnemyBase (grupo «Impacto»): cuánto resiste a los empujes y frenazos
## seguidos.
func configure_slow_resist(per_hit: float, build: float, max_resist: float,
		recovery: float) -> void:
	_resist_per_hit = maxf(per_hit, 0.0)
	_resist_build = maxf(build, 0.0)
	_resist_max = clampf(max_resist, 0.0, 1.0)
	_resist_recovery = maxf(recovery, 0.0)


## Resistencia actual (0-1): cuánta fuerza les quita a empujes y frenazos.
func resistance() -> float:
	return _slow_resist


## Un golpe de arma que empuja o frena: suma resistencia hasta el tope.
func register_impact() -> void:
	_slow_resist = minf(_slow_resist + _resist_per_hit, _resist_max)


## Multiplicador de velocidad actual: 1.0 sin ralentización activa. La
## resistencia acumulada le quita fuerza al frenazo.
func slow_multiplier() -> float:
	if _slow_time_left <= 0.0:
		return 1.0
	return 1.0 - (1.0 - _slow_multiplier) * (1.0 - _slow_resist)


## Ver EnemyBase.apply_poison: ganan el dps más fuerte y el reloj más largo.
func apply_poison(dps: float, duration: float) -> void:
	if _poison_time_left <= 0.0:
		_poison_tick_timer = POISON_TICK
		_overlays.set_poisoned(true)
	_poison_dps = maxf(_poison_dps, dps)
	_poison_time_left = maxf(_poison_time_left, duration)


## Ver EnemyBase.apply_burn: como el veneno, ganan el dps más fuerte y el
## reloj más largo, pero no comparte nada con él.
func apply_burn(dps: float, duration: float) -> void:
	if _burn_time_left <= 0.0:
		_burn_tick_timer = BURN_TICK
		_overlays.set_burning(true)
	_burn_dps = maxf(_burn_dps, dps)
	_burn_time_left = maxf(_burn_time_left, duration)


## Un frame: corre el reloj de la ralentización y los pulsos de veneno y
## quemadura. Un pulso puede MATAR al cuerpo dentro de esta llamada.
func tick(delta: float) -> void:
	if _slow_time_left > 0.0:
		_slow_resist = minf(_slow_resist + _resist_build * delta, _resist_max)
	else:
		_slow_resist = maxf(_slow_resist - _resist_recovery * delta, 0.0)
	_slow_time_left = maxf(_slow_time_left - delta, 0.0)
	if _push != Vector3.ZERO:
		_push = _push.move_toward(Vector3.ZERO, _push_decay * delta)
	if _poison_time_left > 0.0:
		_tick_poison(delta)
	if _burn_time_left > 0.0 and not _health.is_dead:
		_tick_burn(delta)


func _tick_poison(delta: float) -> void:
	_poison_time_left = maxf(_poison_time_left - delta, 0.0)
	_poison_tick_timer -= delta
	if _poison_tick_timer <= 0.0:
		_poison_tick_timer += POISON_TICK
		# Por take_damage, así aplican la armadura, los números y la muerte.
		_health.take_damage(_poison_dps * POISON_TICK)
	if _poison_time_left <= 0.0:
		_poison_dps = 0.0
		_overlays.set_poisoned(false)


func _tick_burn(delta: float) -> void:
	_burn_time_left = maxf(_burn_time_left - delta, 0.0)
	_burn_tick_timer -= delta
	if _burn_tick_timer <= 0.0:
		_burn_tick_timer += BURN_TICK
		_health.take_damage(_burn_dps * BURN_TICK)
	if _burn_time_left <= 0.0:
		_burn_dps = 0.0
		_overlays.set_burning(false)
