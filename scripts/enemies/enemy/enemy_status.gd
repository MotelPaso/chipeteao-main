class_name EnemyStatus
extends RefCounted
## Estados temporales de un enemigo: ralentización y veneno. EnemyBase lo
## crea la primera vez que recibe uno (apply_slow / apply_poison), así los
## cuerpos que nunca lo reciben no pagan nada por frame.

## Segundos entre pulsos de daño del veneno. Edita aquí.
const POISON_TICK: float = 0.5

var _health: Health
var _overlays: EnemyOverlays
## Multiplicador de velocidad activo mientras corre su reloj.
var _slow_multiplier: float = 1.0
var _slow_time_left: float = 0.0
var _poison_dps: float = 0.0
var _poison_time_left: float = 0.0
var _poison_tick_timer: float = 0.0


func _init(health: Health, overlays: EnemyOverlays) -> void:
	_health = health
	_overlays = overlays


## Ver EnemyBase.apply_slow: reaplicar refresca en vez de acumular, y ganan
## la ralentización más fuerte y el reloj más largo.
func apply_slow(speed_multiplier: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var incoming := clampf(speed_multiplier, 0.05, 1.0)
	_slow_multiplier = minf(slow_multiplier(), incoming)
	_slow_time_left = maxf(_slow_time_left, duration)


## Multiplicador de velocidad actual: 1.0 sin ralentización activa.
func slow_multiplier() -> float:
	return _slow_multiplier if _slow_time_left > 0.0 else 1.0


## Ver EnemyBase.apply_poison: ganan el dps más fuerte y el reloj más largo.
func apply_poison(dps: float, duration: float) -> void:
	if _poison_time_left <= 0.0:
		_poison_tick_timer = POISON_TICK
		_overlays.set_poisoned(true)
	_poison_dps = maxf(_poison_dps, dps)
	_poison_time_left = maxf(_poison_time_left, duration)


## Un frame: corre el reloj de la ralentización y, si hay veneno, su pulso.
## Un pulso de veneno puede MATAR al cuerpo dentro de esta llamada.
func tick(delta: float) -> void:
	_slow_time_left = maxf(_slow_time_left - delta, 0.0)
	if _poison_time_left > 0.0:
		_tick_poison(delta)


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
