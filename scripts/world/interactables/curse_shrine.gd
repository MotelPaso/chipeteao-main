class_name CurseShrine
extends ChargeShrine
## Altar demoníaco (obelisco): se carga igual que un altar de carga (por
## cercanía, pausa al salir, se hunde tras pagar), pero paga un PACTO. Al
## completar ofrece tres cartas: cada una junta una stat al azar del jugador
## (ALTAR_BOONS, sin repetir en el altar) al MÁXIMO de su lista x
## max_multiplier, con un costo al azar de COST_LIBRARY (cada costo con su
## cantidad sorteada entre min y max). Todo uso sube además la dificultad
## (difficulty_per_use). La Sangre de demonio agranda las dos mitades del
## trato.

## Kind del objeto que agranda las dos mitades del pacto (Sangre de demonio);
## su fila de ItemCatalog lleva el porcentaje por copia (boost_percent).
const DEMON_BLOOD_KIND: String = "demonic_boost"

## Costos de los pactos, edita aquí. `kind` decide qué paga (una rama en
## _pay_cost, nunca la cambies); `min`/`max` es el rango en que se sortea la
## cantidad, en %; `label` lleva exactamente un "%d" con esa cantidad.
##   difficulty      dificultad de la partida
##   sky_duration    las lunas y lluvias duran más
##   bad_events      lunas malas, lluvias malas y desastres salen más seguido
##   enemy_speed     enemigos más rápidos (los que aparecen desde ahora)
##   points          pierdes ese % de tus puntos
const COST_LIBRARY: Array[Dictionary] = [
	{"id": "cost_difficulty", "kind": "difficulty", "min": 20, "max": 30,
		"label": "dificultad +%d%%"},
	{"id": "cost_long_nights", "kind": "sky_duration", "min": 30, "max": 50,
		"label": "las lunas y lluvias duran %d%% más"},
	{"id": "cost_bad_omens", "kind": "bad_events", "min": 30, "max": 50,
		"label": "eventos malos %d%% más seguido"},
	{"id": "cost_swift_horde", "kind": "enemy_speed", "min": 10, "max": 20,
		"label": "enemigos %d%% más rápidos"},
	{"id": "cost_tithe", "kind": "points", "min": 10, "max": 30,
		"label": "pierdes el %d%% de tus puntos"},
]

@export_group("Pactos")
## La stat del pacto vale el máximo de su lista (ver ALTAR_BOONS) por esto, redondeado hacia arriba.
@export var max_multiplier: float = 1.0
## Multiplica el costo de dificultad de cada pacto (1 = el número de COST_LIBRARY, 2 = el doble).
@export var difficulty_scale: float = 1.0
## Texto de cada carta bajo el título (la stat que da); %s = el costo del pacto.
@export_multiline var pact_description: String = "Pagas: %s"


## Grupo de los altares demoníacos (ver ChargeShrine.type_group).
func type_group() -> StringName:
	return &"demonic_altars"


## La Llave maestra solo agranda los altares de carga.
func _uses_master_key() -> bool:
	return false


func _demon_blood_in_ring() -> int:
	return best_kind_count_in_range(DEMON_BLOOD_KIND)


## La Sangre de demonio agranda el don y el costo de dificultad; ambos la
## leen de aquí. Cada copia suma boost_percent de su fila de ItemCatalog.
func _blood_scale() -> float:
	var row := ItemCatalog.kind_row(DEMON_BLOOD_KIND)
	var per_copy := float(row.get("boost_percent", 0.0)) / 100.0
	return 1.0 + per_copy * float(_demon_blood_in_ring())


## Tres pactos: stats distintas al máximo, cada una con un costo al azar.
func _reward_options(_keys: int) -> Array[Dictionary]:
	var pool := ALTAR_BOONS.duplicate()
	pool.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(ALTAR_CHOICE_COUNT, pool.size()):
		var boon: Dictionary = pool[i]
		var amount := _max_amount(boon)
		var cost: Dictionary = COST_LIBRARY.pick_random()
		var cost_amount := float(randi_range(int(cost.min), int(cost.max)))
		var gained := String(boon.label) % roundi(amount)
		options.append({
			"title": gained,
			"description": pact_description % _cost_text(cost, cost_amount),
			"color": accent_color,
			"label": gained,
			"stat": String(boon.stat),
			"amount": amount,
			"cost": cost,
			"cost_amount": cost_amount,
		})
	return options


## El don del pacto: el máximo de la lista de esa stat x max_multiplier y la
## Sangre de demonio, redondeado hacia arriba.
func _max_amount(boon: Dictionary) -> float:
	var top := 1.0
	for value: Variant in boon_values(boon):
		top = maxf(top, float(value))
	return ceilf(top * max_multiplier * _blood_scale())


## Cómo se lee el costo: solo el del pacto. La dificultad que suma todo uso
## del altar se cobra igual, pero la carta no la muestra.
func _cost_text(cost: Dictionary, amount: float) -> String:
	if String(cost.kind) == "difficulty":
		return String(cost.label) % roundi(_difficulty_cost(amount))
	return String(cost.label) % roundi(amount)


## Dificultad (en %) que suma todo uso del altar, con la escala de ESTE altar.
func _base_difficulty() -> float:
	return difficulty_per_use * _blood_scale() * difficulty_scale


## Un costo de dificultad con la Sangre de demonio y difficulty_scale.
func _difficulty_cost(amount: float) -> float:
	return amount * _blood_scale() * difficulty_scale


## Paga el pacto elegido: la stat para toda la party, el costo y la
## dificultad de siempre. Devuelve el texto del don, que anuncian el cartel
## y el log `Altar charged:`; el costo tiene sus propios logs.
func _grant_choice(option: Dictionary, _keys: int, recipient: Node) -> String:
	grant_boon(String(option.stat), float(option.amount))
	var cost: Dictionary = option.cost
	var difficulty_step := _pay_cost(cost, float(option.cost_amount), recipient)
	var always := _base_difficulty() / 100.0
	RunState.add_difficulty(always, "altars")
	difficulty_step += always
	RunState.demonic_uses += 1
	print("Demonic pact: %s +%s / %s %d" % [String(option.stat), option.amount,
			String(cost.id), roundi(float(option.cost_amount))])
	print("Demonic altar used: difficulty +%d%% (total +%d%%)" % [
			roundi(difficulty_step * 100.0), roundi(RunState.difficulty_bonus * 100.0)])
	return String(option.label)


## Una rama por kind de costo. Devuelve la fracción de DIFICULTAD sumada (0
## para los demás kinds), que es lo que informa el log.
func _pay_cost(cost: Dictionary, amount: float, recipient: Node) -> float:
	var fraction := amount / 100.0
	match String(cost.kind):
		"difficulty":
			var step := _difficulty_cost(amount) / 100.0
			RunState.add_difficulty(step, "altars")
			return step
		"sky_duration":
			RunState.sky_duration_multiplier *= 1.0 + fraction
		"bad_events":
			# Lo lee WeatherCatalog al sortear: pesa más cada fila `bad`.
			RunState.bad_weather_bonus += fraction
		"enemy_speed":
			RunState.enemy_speed_multiplier *= 1.0 + fraction
		"points":
			_lose_points(recipient, fraction)
		_:
			push_warning("CurseShrine: unknown cost kind '%s'" % cost.kind)
	return 0.0


## Quien sostuvo el anillo pierde esa fracción de sus puntos.
func _lose_points(recipient: Node, fraction: float) -> void:
	if recipient == null or not is_instance_valid(recipient) \
			or not recipient.has_method("spend_points"):
		return
	var lost := floori(float(recipient.get("points")) * fraction)
	if lost > 0:
		recipient.call("spend_points", lost)
