class_name LobsterLife
extends Node
## La vida de la Langosta Azul durante la pelea (nodo Life de BlueLobster.tscn).
## No es un número fijo: sale del nodo Scaling (StageBossScaling), que la
## calcula para que la pelea dure lo mismo con cualquier build.
## Al empezar se ESTIMA con el daño que la party le venía haciendo a la horda.
## Esa estimación puede errar mucho (no es lo mismo pegarle a la horda que a
## un jefe que se mueve), así que durante la pelea, cada replan_seconds, se
## recalcula la vida que le queda con el daño que le hacen DE VERDAD: lo que
## falta de la barra tiene que durar lo que falta de la pelea
## (Scaling.target_fight_seconds). La barra no se mueve cuando eso pasa y
## sigue siendo una sola vida: solo cambia cuánta vida hay detrás.
## Para que nada lo engañe: el daño que cuenta es el de toda la pelea con
## algo del de los últimos segundos; en los primeros segundos pesa poco
## frente a la estimación (un primer golpe enorme no la infla); la vida baja
## de a poco (max_drop_per_replan: un rato esquivando sin pegarle no la deja
## de papel); y al final ya no se recalcula (casi muerta no vuelve a crecer).
## Si la pelea se alarga igual, el nodo Burnout la desgasta hasta el final.
## Líneas de log para los soaks: "<título> scaling:" al empezar (life=1) y en
## cada recálculo que mueve su vida máxima más de log_change (life=2, 3...).

## Segundos de cada casillero del medidor de daño reciente.
const BUCKET_SECONDS: float = 0.5

@export_group("Recálculo")
## Segundos entre un recálculo de la vida y el siguiente.
@export var replan_seconds: float = 2.0
## Segundos de golpes hasta que el daño medido manda del todo sobre la estimación del principio.
@export var trust_seconds: float = 6.0
## Segundos hacia atrás que cuentan como daño reciente.
@export var recent_seconds: float = 10.0
## Peso (0-1) del daño reciente frente al de toda la pelea. Más alto = sigue más rápido los cambios de la party, y también sus rachas.
@export_range(0.0, 1.0) var recent_weight: float = 0.3
## Parte (0-1) que la vida puede bajar en un recálculo: un rato sin pegarle no la deja de papel.
@export_range(0.0, 1.0) var max_drop_per_replan: float = 0.1
## Deja de recalcular cuando faltan menos de estos segundos para la duración prevista de la pelea.
@export var stop_with_seconds_left: float = 8.0
## Deja de recalcular cuando le queda menos de esta parte de la barra (0-1).
@export_range(0.0, 1.0) var stop_with_bar_left: float = 0.15
## Cambio mínimo de la vida máxima (0.15 = 15 %) para anotar un recálculo en el log.
@export var log_change: float = 0.15

## Segundos de pelea y daño que le hizo la party (el desgaste no cuenta).
var fight_seconds: float = 0.0
var party_damage: float = 0.0
## True desde que el desgaste empezó a quitarle vida.
var burning: bool = false

var _health: Health = null
var _title: String = ""
## Daño por segundo que estimó el plan del principio.
var _start_dps: float = 0.0
## Segundos desde el primer golpe de la party (-1 = todavía no le pegan).
var _hit_seconds: float = -1.0
## Daño de la party de los últimos recent_seconds, por casillero de
## BUCKET_SECONDS, en anillo.
var _buckets: PackedFloat32Array = PackedFloat32Array()
var _bucket: int = 0
var _bucket_left: float = BUCKET_SECONDS
var _replan_left: float = 0.0
## Número del último plan anotado en el log y su vida máxima.
var _plans: int = 1
var _logged_max: float = 0.0
## Segundos de pelea tras los que empieza a desgastarse (0 = nunca).
var _burnout_after: float = 0.0

@onready var _scaling: StageBossScaling = $"../Scaling"
@onready var _burnout: BossBurnout = $"../Burnout"


## Empieza la pelea de `title`: pone la vida estimada en `health` (su vida
## máxima de ahora es el PISO) y arma el desgaste. Devuelve el plan, del que
## la langosta toma la agresividad y el daño extra.
func begin(health: Health, title: String) -> StageBossScaling.LifePlan:
	_health = health
	_title = title
	var plan := _scaling.plan_first_life(health.max_hp, 0.0)
	# El plan trae la vida del primer tramo de Scaling.life_shares; si hay
	# más, el resto de la barra se supone al mismo ritmo.
	var share := _first_share()
	health.max_hp = plan.hp / share
	health.heal_full()
	_start_dps = plan.dps
	# El desgaste mira la pelea ENTERA: una party algo más lenta que lo
	# previsto no es una party que no le pega.
	_burnout_after = plan.burnout_after / share
	_buckets.resize(maxi(ceili(recent_seconds / BUCKET_SECONDS), 1))
	_buckets.fill(0.0)
	_arm_burnout()
	_logged_max = health.max_hp
	print(_scaling.log_line(title, plan))
	return plan


## Un frame de pelea: corren los relojes y el medidor, se recalcula la vida
## si toca y pulsa el desgaste (que puede matarla aquí mismo).
func tick(delta: float) -> void:
	fight_seconds += delta
	if _hit_seconds >= 0.0:
		_hit_seconds += delta
		_advance_meter(delta)
		_replan_left -= delta
		if _replan_left <= 0.0:
			_replan_left += maxf(replan_seconds, 0.1)
			_replan()
	_burnout.tick(delta, fight_seconds)


## Un golpe le quitó `amount`: suma el de la party (el del desgaste no cuenta).
func on_damaged(amount: float) -> void:
	if _burnout.draining:
		burning = true
		return
	party_damage += amount
	if _hit_seconds < 0.0:
		_hit_seconds = 0.0
		_replan_left = maxf(replan_seconds, 0.1)
	if not _buckets.is_empty():
		_buckets[_bucket] += amount


# --- privados ---------------------------------------------------------------------

## Recalcula la vida que queda con el daño medido, sin mover la barra.
func _replan() -> void:
	if burning or _health == null or _health.is_dead \
			or (_burnout_after > 0.0 and fight_seconds >= _burnout_after):
		return
	var bar_left := _health.current_hp / maxf(_health.max_hp, 1.0)
	if bar_left < stop_with_bar_left \
			or _scaling.target_fight_seconds - fight_seconds < stop_with_seconds_left:
		return
	var whole_fight := party_damage / maxf(_hit_seconds, 1.0)
	var recent := _recent_damage() / clampf(_hit_seconds, 1.0, maxf(recent_seconds, 1.0))
	var measured := lerpf(whole_fight, recent, recent_weight)
	# Con pocos segundos medidos, manda la estimación del principio.
	var trust := clampf(_hit_seconds / maxf(trust_seconds, 0.1), 0.0, 1.0)
	var plan := _scaling.plan_rest(_plans + 1, lerpf(_start_dps, measured, trust),
			fight_seconds, bar_left)
	plan.measured = measured
	var rest := plan.hp
	var lowest := _health.current_hp * (1.0 - max_drop_per_replan)
	if rest < lowest:
		rest = lowest
		plan.clamp = "drop"
	if is_equal_approx(rest, _health.current_hp):
		return
	var whole := rest / maxf(bar_left, 0.001)
	# current_hp primero: el setter de max_hp avisa una sola vez a la barra, ya
	# con la proporción de siempre.
	_health.current_hp = rest
	_health.max_hp = whole
	_arm_burnout()
	if absf(whole - _logged_max) >= _logged_max * log_change:
		_plans += 1
		_logged_max = whole
		plan.life = _plans
		plan.hp = rest
		plan.budget = rest / maxf(plan.dps, 0.01)
		plan.burnout_after = _burnout_after
		print(_scaling.log_line(_title, plan))


## Pasa el reloj del medidor: cada BUCKET_SECONDS empieza un casillero nuevo
## y se olvida el más viejo.
func _advance_meter(delta: float) -> void:
	if _buckets.is_empty():
		return
	_bucket_left -= delta
	while _bucket_left <= 0.0:
		_bucket_left += BUCKET_SECONDS
		_bucket = (_bucket + 1) % _buckets.size()
		_buckets[_bucket] = 0.0


func _recent_damage() -> float:
	var total := 0.0
	for amount: float in _buckets:
		total += amount
	return total


## Arma el desgaste para la barra de ahora: empieza a los _burnout_after
## segundos de pelea y se lleva la barra entera en Scaling.burnout_seconds.
func _arm_burnout() -> void:
	_burnout.arm(_health, _title, _burnout_after,
			_health.max_hp / maxf(_scaling.burnout_seconds, 0.1))


## Parte de la barra (0-1) que cubre el plan del principio: el primer tramo
## de Scaling.life_shares (la langosta usa uno solo, la barra entera).
func _first_share() -> float:
	var total := 0.0
	for share: float in _scaling.life_shares:
		total += maxf(share, 0.0)
	if total <= 0.0:
		return 1.0
	return clampf(maxf(_scaling.life_shares[0], 0.0) / total, 0.01, 1.0)
