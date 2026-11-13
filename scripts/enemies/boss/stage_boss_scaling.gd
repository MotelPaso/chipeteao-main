class_name StageBossScaling
extends Node
## Escalado de un jefe de etapa por DURACIÓN OBJETIVO: la vida de cada una de
## sus vidas se calcula para que la pelea entera dure target_fight_seconds con
## el daño real de la party. No sabe qué jefe lo lleva: va como nodo hijo de
## la escena del jefe, que le pide plan_first_life() al llegar y
## plan_next_life() en cada renacer, y aplica el plan que recibe.
##
## Primera vida: el daño que las armas le harían a un solo cuerpo, medido
## contra la horda (PartyPower.focus_dps), por focus_on_boss. En co-op el
## aporte de cada jugador extra se rebaja (extra_player_focus): el jefe acosa
## a un raider a la vez. El resultado se acota alrededor de lo que el puntaje
## de poder dice que esa party debería hacer: la horda infla a las builds de
## área y castiga a las de un solo blanco, y el puntaje no depende de qué
## había para golpear. El puntaje predice el daño solo a grandes rasgos, así
## que la banda es ancha: está para frenar una medida absurda, no para
## corregir una buena.
## Vidas siguientes: el daño que el jefe recibió de verdad (el de la última
## vida mezclado con el de toda la pelea, para que una vida muy corta no
## engañe), y el tiempo que queda del objetivo.
##
## Piso: la vida que trae la escena del jefe, ya multiplicada por vuelta,
## dificultad y tamaño de party (BossSchedule.spawn_boss), repartida entre
## las vidas. Con el piso la pelea puede durar más que el objetivo.

## Lo que el jefe aplica en una vida.
class LifePlan:
	extends RefCounted
	## Número de vida, desde 1.
	var life: int = 1
	var players: int = 1
	## Daño por segundo estimado de la party contra el jefe.
	var dps: float = 0.0
	## Daño por segundo medido (contra la horda en la primera vida, contra el
	## jefe después) y el que se espera por el puntaje de poder.
	var measured: float = 0.0
	var expected: float = 0.0
	## Puntaje de poder de la party.
	var power: float = 0.0
	## Vida máxima de esta vida.
	var hp: float = 0.0
	## Segundos que debería durar esta vida con ese daño.
	var budget: float = 0.0
	## De dónde salió el daño: "horde" (medido contra la horda) o "boss".
	var source: String = "horde"
	## Qué límite decidió la vida: "none", "floor", "ceiling" o "min".
	var clamp: String = "none"
	## Agresividad del jefe en esta vida (0-1).
	var aggression: float = 0.0
	## Daño extra por poder, en fracción (0.2 = +20 %).
	var damage_bonus: float = 0.0

@export_group("Duración objetivo")
## Segundos que debería durar la pelea entera con el daño real de la party.
@export var target_fight_seconds: float = 165.0
## Segundos mínimos que dura la pelea por más fuerte que sea la party.
@export var min_fight_seconds: float = 105.0
## Parte de la pelea que toca a cada vida, en orden; la cantidad de entradas es la cantidad de vidas.
@export var life_shares: Array[float] = [0.18, 0.36, 0.46]
## Segundos mínimos presupuestados para una vida, aunque la pelea ya vaya larga.
@export var min_life_seconds: float = 14.0

@export_group("Vida")
## Fracción (0-1) de la ventaja de daño de la party que el jefe absorbe como vida extra; el resto acorta la pelea.
@export_range(0.0, 1.0) var advantage_absorbed: float = 0.78
## Techo de la vida total de la pelea, en veces el piso. Muy alto a propósito: una build tardía hace miles de veces el daño de una recién empezada; bájalo para que las peleas tardías se acorten.
@export var max_hp_over_floor: float = 20000.0
## Peso (0-1) del daño de la última vida frente al de toda la pelea al calcular la vida siguiente.
@export_range(0.0, 1.0) var recent_life_weight: float = 0.65

@export_group("Estimación de la primera vida")
## Segundos de partida hacia atrás que se promedian para el daño medido contra la horda.
@export var dps_window_seconds: float = 45.0
## Fracción (0-1) del daño a un solo cuerpo que se espera que caiga sobre el jefe; el resto se va en la horda.
@export_range(0.0, 1.0) var focus_on_boss: float = 0.6
## Fracción (0-1) de ese daño que aporta cada jugador además del primero: en co-op el jefe acosa a un raider a la vez y los demás no siempre lo tienen a tiro.
@export_range(0.0, 1.0) var extra_player_focus: float = 0.3
## Daño por segundo que se espera de un raider sin poderes.
@export var expected_dps_base: float = 9.0
## Cuánto crece ese daño esperado por cada punto de poder del raider (exponencial: 0.11 lo duplica cada 6,3 puntos).
@export var expected_dps_growth: float = 0.11
## La estimación nunca baja de esta fracción del daño esperado por poder.
@export var power_check_low: float = 0.125
## La estimación nunca sube de estas veces el daño esperado por poder.
@export var power_check_high: float = 8.0

@export_group("Agresividad")
## Agresividad (0-1) que suma cada jugador además del primero.
@export var aggression_per_extra_player: float = 0.15
## Agresividad (0-1) que suma cada punto de poder de la party.
@export var aggression_per_power: float = 0.004
## Agresividad (0-1) que suma cada vida después de la primera.
@export var aggression_per_life: float = 0.15
## Techo de la agresividad (0-1).
@export_range(0.0, 1.0) var aggression_cap: float = 1.0

@export_group("Daño")
## Daño extra (fracción) por cada punto de poder de la party.
@export var damage_per_power: float = 0.003
## Techo del daño extra por poder (0.35 = +35 %).
@export var damage_power_cap: float = 0.35

var _floor_hp: float = 1.0
var _interlude_seconds: float = 0.0
## Daño recibido y segundos vulnerables de las vidas ya terminadas.
var _fight_damage: float = 0.0
var _fight_seconds: float = 0.0


## Cantidad de vidas del jefe.
func lives() -> int:
	return _shares().size()


## Plan de la primera vida. `floor_hp` es la vida de la escena del jefe ya
## escalada por spawn_boss; `interlude_seconds`, lo que dura cada renacer.
func plan_first_life(floor_hp: float, interlude_seconds: float) -> LifePlan:
	_floor_hp = maxf(floor_hp, 1.0)
	_interlude_seconds = maxf(interlude_seconds, 0.0)
	_fight_damage = 0.0
	_fight_seconds = 0.0
	var power := PartyPower.find(get_tree())
	var score := power.score() if power != null else 0.0
	var players := maxi(Coop.player_count, 1)
	var measured := power.focus_dps(dps_window_seconds) if power != null else 0.0
	var expected := _expected_dps(score, players)
	# En co-op el daño medido es el de toda la party, pero al jefe le llega
	# entero el de un raider y solo una parte del de cada uno de los demás.
	var reach := (1.0 + extra_player_focus * float(players - 1)) / float(players)
	var estimate := clampf(measured * focus_on_boss * reach, expected * power_check_low,
			expected * power_check_high)
	var plan := _plan(1, estimate, score, players, "horde", 0.0)
	plan.measured = measured
	plan.expected = expected
	return plan


## Plan de una vida después de la primera: `damage_taken` y `life_seconds`
## son los de la vida que acaba de terminar, y `fight_elapsed` los segundos
## de pelea que ya pasaron, renaceres incluidos.
func plan_next_life(life: int, damage_taken: float, life_seconds: float,
		fight_elapsed: float) -> LifePlan:
	var power := PartyPower.find(get_tree())
	var score := power.score() if power != null else 0.0
	var players := maxi(Coop.player_count, 1)
	_fight_damage += damage_taken
	_fight_seconds += life_seconds
	var recent := damage_taken / maxf(life_seconds, 1.0)
	var whole_fight := _fight_damage / maxf(_fight_seconds, 1.0)
	var estimate := lerpf(whole_fight, recent, recent_life_weight)
	var plan := _plan(life, estimate, score, players, "boss", fight_elapsed)
	plan.measured = recent
	plan.expected = _expected_dps(score, players)
	return plan


## Línea de log de un plan; `title` es el nombre del jefe.
func log_line(title: String, plan: LifePlan) -> String:
	return ("%s scaling: life=%d players=%d dps=%.1f power=%.1f hp=%.0f budget=%.1fs"
			+ " source=%s measured=%.1f expected=%.1f clamp=%s aggression=%.2f damage=x%.2f") % [
			title, plan.life, plan.players, plan.dps, plan.power, plan.hp, plan.budget,
			plan.source, plan.measured, plan.expected, plan.clamp, plan.aggression,
			1.0 + plan.damage_bonus]


## Las partes de la pelea por vida. Un arreglo vacío cuenta como una sola
## vida que se lleva la pelea entera.
func _shares() -> Array[float]:
	if life_shares.is_empty():
		var single: Array[float] = [1.0]
		return single
	return life_shares


## Daño por segundo que el puntaje de poder dice que esta party debería
## hacer: cada raider parte de expected_dps_base y crece con SU parte del
## puntaje.
func _expected_dps(score: float, players: int) -> float:
	var per_player := score / float(maxi(players, 1))
	return float(players) * expected_dps_base * exp(expected_dps_growth * per_player)


func _plan(life: int, dps_estimate: float, score: float, players: int, source: String,
		fight_elapsed: float) -> LifePlan:
	var plan := LifePlan.new()
	plan.life = life
	plan.players = players
	plan.dps = dps_estimate
	plan.power = score
	plan.source = source
	var shares := _shares()
	var index := clampi(life - 1, 0, shares.size() - 1)
	var total_share := 0.0
	var share_left := 0.0
	for i: int in shares.size():
		total_share += shares[i]
		if i >= index:
			share_left += shares[i]
	total_share = maxf(total_share, 0.001)
	share_left = maxf(share_left, 0.001)
	var own_share := shares[index]
	# Lo que queda del objetivo, sin los renaceres que faltan, repartido entre
	# las vidas que quedan: una vida que se alargó la pagan las siguientes.
	var interludes_left := float(lives() - life) * _interlude_seconds
	var time_left := maxf(target_fight_seconds - fight_elapsed - interludes_left, 0.0)
	var seconds := maxf(time_left * own_share / share_left, min_life_seconds)
	var floor_life := _floor_hp * own_share / total_share
	var ceiling_life := floor_life * max_hp_over_floor
	# Daño de referencia: el que deja la pelea justo en el objetivo con la
	# vida del piso. De la ventaja sobre él, el jefe solo absorbe una parte.
	var reference := _floor_hp / maxf(target_fight_seconds, 1.0)
	var effective := dps_estimate
	if dps_estimate > reference:
		effective = reference + (dps_estimate - reference) * advantage_absorbed
	plan.hp = effective * seconds
	# Nunca en segundos: con su daño real la vida dura su parte del mínimo.
	var min_hp := dps_estimate * seconds \
			* min_fight_seconds / maxf(target_fight_seconds, 1.0)
	if plan.hp < min_hp:
		plan.hp = min_hp
		plan.clamp = "min"
	if plan.hp < floor_life:
		plan.hp = floor_life
		plan.clamp = "floor"
	elif plan.hp > ceiling_life:
		plan.hp = ceiling_life
		plan.clamp = "ceiling"
	plan.budget = plan.hp / maxf(dps_estimate, 0.01)
	plan.aggression = clampf(aggression_per_extra_player * float(players - 1)
			+ aggression_per_power * score + aggression_per_life * float(life - 1),
			0.0, aggression_cap)
	plan.damage_bonus = clampf(damage_per_power * score, 0.0, damage_power_cap)
	return plan
