class_name LobsterLife
extends Node
## La vida de la Langosta Azul durante la pelea (nodo Life de BlueLobster.tscn).
## No es un número fijo: sale del nodo Scaling (StageBossScaling), que la
## calcula para que la pelea dure lo mismo con cualquier build.
## Al empezar se ESTIMA con el daño que la party le venía haciendo a la horda.
## Esa estimación puede errar mucho (no es lo mismo pegarle a la horda que a
## un jefe que se mueve), así que la barra se parte en tramos
## (Scaling.life_shares) y cada vez que pierde uno se recalcula lo que queda
## con el daño que le hicieron DE VERDAD en ese tramo. La barra no se mueve
## cuando eso pasa y sigue siendo una sola vida: solo cambia cuánta vida hay
## detrás de lo que falta.
## Si la pelea se alarga igual, el nodo Burnout la desgasta hasta el final.
## Líneas de log para los soaks: "<título> scaling:" al empezar (life=1) y en
## cada recálculo (life=2, 3...).

## Un tramo que duró menos que esto no dice nada del daño de la party (un solo
## golpe se llevó dos tramos): se salta sin recalcular.
const MIN_STRETCH_SECONDS: float = 1.0

## Segundos de pelea y daño que le hizo la party (el desgaste no cuenta).
var fight_seconds: float = 0.0
var party_damage: float = 0.0
## True desde que el desgaste empezó a quitarle vida.
var burning: bool = false

var _health: Health = null
var _title: String = ""
## Partes de la barra por tramo (suman 1) y el tramo en que está (1 = el primero).
var _shares: Array[float] = [1.0]
var _stretch: int = 1
## Segundos del tramo actual desde el primer golpe, y el daño de la party en él.
var _stretch_seconds: float = 0.0
var _stretch_damage: float = 0.0
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
	_shares = _normalized_shares()
	var plan := _scaling.plan_first_life(health.max_hp, 0.0)
	# El plan trae la vida del PRIMER tramo; el resto se supone al mismo ritmo
	# hasta que se recalcule.
	health.max_hp = plan.hp / _shares[0]
	health.heal_full()
	# El desgaste mira la pelea ENTERA, no un tramo: una party algo más lenta
	# que lo estimado no es una party que no le pega.
	_burnout_after = plan.burnout_after / _shares[0]
	_arm_burnout()
	print(_scaling.log_line(title, plan))
	return plan


## Un frame de pelea: corren los relojes, se recalcula si perdió un tramo y
## pulsa el desgaste (que puede matarla aquí mismo).
func tick(delta: float) -> void:
	fight_seconds += delta
	if _stretch > 1 or _stretch_damage > 0.0:
		_stretch_seconds += delta
	if _stretch < _shares.size() and not burning and not _health.is_dead \
			and _health.current_hp <= _health.max_hp * _bar_left_after(_stretch):
		_next_stretch()
	_burnout.tick(delta, fight_seconds)


## Un golpe le quitó `amount`: suma el de la party (el del desgaste no cuenta).
func on_damaged(amount: float) -> void:
	if _burnout.draining:
		burning = true
		return
	party_damage += amount
	_stretch_damage += amount


# --- privados ---------------------------------------------------------------------

## Perdió un tramo de la barra: recalcula la vida que queda con el daño real
## de ese tramo, sin mover la barra.
func _next_stretch() -> void:
	_stretch += 1
	if _stretch_seconds < MIN_STRETCH_SECONDS:
		return
	var ratio := _health.current_hp / maxf(_health.max_hp, 1.0)
	var plan := _scaling.plan_next_life(_stretch, _stretch_damage, _stretch_seconds,
			fight_seconds)
	var whole := plan.hp / _shares[_stretch - 1]
	# current_hp primero: el setter de max_hp avisa una sola vez a la barra, ya
	# con la proporción de siempre.
	_health.current_hp = whole * ratio
	_health.max_hp = whole
	_stretch_seconds = 0.0
	_stretch_damage = 0.0
	_arm_burnout()
	print(_scaling.log_line(_title, plan))


## Arma el desgaste para la barra de ahora: empieza a los _burnout_after
## segundos de pelea y se lleva la barra entera en Scaling.burnout_seconds.
func _arm_burnout() -> void:
	_burnout.arm(_health, _title, _burnout_after,
			_health.max_hp / maxf(_scaling.burnout_seconds, 0.1))


## Fracción de la barra (0-1) que queda al terminar el tramo `stretch`.
func _bar_left_after(stretch: int) -> float:
	var left := 1.0
	for index: int in mini(stretch, _shares.size()):
		left -= _shares[index]
	return maxf(left, 0.0)


## Scaling.life_shares llevado a fracciones que suman 1 (una sola si no la parte).
func _normalized_shares() -> Array[float]:
	var total := 0.0
	for share: float in _scaling.life_shares:
		total += maxf(share, 0.0)
	var shares: Array[float] = []
	if total <= 0.0:
		shares.append(1.0)
		return shares
	# Mismo índice que en Scaling.life_shares: un tramo nunca queda en cero.
	for share: float in _scaling.life_shares:
		shares.append(maxf(share / total, 0.01))
	return shares
