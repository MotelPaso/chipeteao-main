class_name CurseShrine
extends ChargeShrine
## Altar demoníaco (obelisco): se carga igual que un altar de carga (por
## cercanía, pausa al salir, se hunde tras pagar), pero paga un PACTO. Al
## completar ofrece tres pactos: cada uno es un BENEFICIO con un COSTO que la
## carta explica (un don mayor, puntos o un cofre gratis, a cambio de
## dificultad, más élites, cielos más largos, más eventos o desastres). La
## Sangre de demonio agranda las dos mitades del trato. Los jefes sueltan un
## cofre extra por uso (BossBase lee RunState.demonic_uses).

## Id del objeto que agranda las dos mitades del pacto (ItemCatalog).
const DEMON_BLOOD_ID: String = "demon_blood"

## Pactos: cada fila es una carta. `benefit` y `cost` son filas {kind, ...}
## resueltas por los dos match de abajo: un pacto nuevo es una fila nueva y
## un KIND nuevo es una rama en cada match, nunca un caso por id.
## Beneficios: "boon" (stat plano para la party, ~2× un ALTAR_BOONS),
## "points" (puntos para quien sostuvo el anillo), "chest" (cofre gratis
## junto al altar). Los costos escriben knobs de RunState. `label` lleva
## exactamente los marcadores que llena su kind (el cofre, ninguno).
const PACT_LIBRARY: Array[Dictionary] = [
	{
		"id": "pact_fury", "name": "Pacto de furia",
		"benefit": {"kind": "boon", "stat": "damage", "amount": 20.0,
			"label": "daño +%d%%"},
		"cost": {"kind": "difficulty", "amount": 15.0, "label": "dificultad +%d%%"},
	},
	{
		"id": "pact_rhythm", "name": "Pacto del pulso",
		"benefit": {"kind": "boon", "stat": "cooldown", "amount": 12.0,
			"label": "velocidad de ataque +%d%%"},
		"cost": {"kind": "elites", "amount": 6.0, "label": "prob. de shiny +%d%%"},
	},
	{
		"id": "pact_hide", "name": "Pacto de la coraza",
		"benefit": {"kind": "boon", "stat": "armor", "amount": 4.0,
			"label": "armadura +%d"},
		"cost": {"kind": "sky_duration", "amount": 40.0,
			"label": "las lunas duran %d%% más"},
	},
	{
		"id": "pact_flesh", "name": "Pacto de carne",
		"benefit": {"kind": "boon", "stat": "max_hp", "amount": 40.0,
			"label": "HP máx. +%d"},
		"cost": {"kind": "events", "amount": 10.0,
			"label": "prob. de luna +%d%%"},
	},
	{
		"id": "pact_swarm", "name": "Pacto del enjambre",
		"benefit": {"kind": "boon", "stat": "projectiles", "amount": 2.0,
			"label": "+%d proyectil(es)"},
		"cost": {"kind": "difficulty", "amount": 20.0, "label": "dificultad +%d%%"},
	},
	{
		"id": "pact_greed", "name": "Pacto de codicia",
		"benefit": {"kind": "points", "amount": 150.0, "label": "+%d pts"},
		"cost": {"kind": "elites", "amount": 8.0, "label": "prob. de shiny +%d%%"},
	},
	{
		"id": "pact_hoard", "name": "Pacto del arcón",
		"benefit": {"kind": "chest", "amount": 0.0, "label": "un cofre gratis aquí mismo"},
		"cost": {"kind": "difficulty", "amount": 25.0, "label": "dificultad +%d%%"},
	},
	{
		"id": "pact_omen", "name": "Pacto del augurio",
		"benefit": {"kind": "boon", "stat": "luck", "amount": 20.0,
			"label": "suerte +%d"},
		"cost": {"kind": "disasters", "amount": 15.0,
			"label": "prob. de desastre +%d%%"},
	},
]

@export_group("Pactos")
## Multiplica el costo de dificultad de cada pacto (1 = el número de PACT_LIBRARY, 2 = el doble).
@export var difficulty_scale: float = 1.0
## Sangre de demonio: cada copia de quien carga suma esta fracción al don Y al costo de dificultad.
@export var demon_blood_per_copy: float = 0.25
## Distancia en metros desde el obelisco a la que cae el cofre gratis del pacto.
@export var chest_drop_distance: float = 2.4
## Texto de cada carta: beneficio (%s) arriba y costo (%s) abajo, en dos líneas para que el costo se lea.
@export_multiline var pact_description: String = "Ganas: %s\nPagas: %s"


func _demon_blood_in_ring() -> int:
	return best_item_count_in_range(DEMON_BLOOD_ID)


## La Sangre de demonio agranda el don y el costo de dificultad; ambos la
## leen de aquí.
func _blood_scale() -> float:
	return 1.0 + demon_blood_per_copy * float(_demon_blood_in_ring())


func _effective_boon_scale() -> float:
	return boon_scale * _blood_scale()


## Tres pactos distintos de la tabla, con precio según las Llaves maestras y
## la Sangre de demonio de quien carga.
func _reward_options(keys: int) -> Array[Dictionary]:
	var pool := PACT_LIBRARY.duplicate()
	pool.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(ALTAR_CHOICE_COUNT, pool.size()):
		var pact: Dictionary = pool[i]
		options.append({
			"title": String(pact.name),
			"description": pact_description % [_benefit_text(pact.benefit, keys),
					_cost_text(pact.cost)],
			"color": accent_color,
			"pact": pact,
		})
	return options


## Cómo se lee el beneficio de un pacto en la carta, con la escala de ESTE altar.
func _benefit_text(benefit: Dictionary, keys: int) -> String:
	var label := String(benefit.label)
	if String(benefit.kind) == "chest":
		return label
	return label % roundi(_benefit_amount(benefit, keys))


## Cómo se lee el costo. Solo la dificultad crece con la Sangre de demonio,
## así que es el único número que cambia con la bolsa del raider.
func _cost_text(cost: Dictionary) -> String:
	return String(cost.label) % roundi(_cost_amount(cost))


## Tamaño del beneficio: los dones de stat usan la escala del altar y las
## Llaves maestras como cualquier don; puntos y cofre son fijos.
func _benefit_amount(benefit: Dictionary, keys: int) -> float:
	if String(benefit.kind) == "boon":
		return boon_amount(float(benefit.amount), keys)
	return float(benefit.amount)


func _cost_amount(cost: Dictionary) -> float:
	var amount := float(cost.amount)
	if String(cost.kind) == "difficulty":
		return amount * _blood_scale() * difficulty_scale
	return amount


## Paga el pacto elegido: primero el beneficio, luego el costo. Devuelve el
## texto del beneficio, que es lo que anuncian el cartel y el log
## `Altar charged:`; el costo tiene sus propios logs.
func _grant_choice(option: Dictionary, keys: int, recipient: Node) -> String:
	var pact: Dictionary = option.pact
	var benefit: Dictionary = pact.benefit
	var gained := _benefit_text(benefit, keys)
	_pay_benefit(benefit, keys, recipient)
	var difficulty_step := _pay_cost(pact.cost)
	RunState.demonic_uses += 1
	# Logs de una línea para los soaks. Un pacto cuyo costo no es dificultad
	# informa un paso de 0.
	print("Demonic pact: %s" % String(pact.id))
	print("Demonic altar used: difficulty +%d%% (total +%d%%)" % [
			roundi(difficulty_step * 100.0), roundi(RunState.difficulty_bonus * 100.0)])
	return gained


## Una rama por kind de beneficio.
func _pay_benefit(benefit: Dictionary, keys: int, recipient: Node) -> void:
	match String(benefit.kind):
		"boon":
			grant_boon(String(benefit.stat), _benefit_amount(benefit, keys))
		"points":
			if recipient != null and is_instance_valid(recipient) \
					and recipient.has_method("add_points"):
				recipient.call("add_points", roundi(float(benefit.amount)))
		"chest":
			_drop_free_chest()
		_:
			push_warning("CurseShrine: unknown benefit kind '%s'" % benefit.kind)


## Una rama por kind de costo. Devuelve la fracción de DIFICULTAD sumada (0
## para los demás kinds), que es lo que informa el log.
func _pay_cost(cost: Dictionary) -> float:
	var fraction := _cost_amount(cost) / 100.0
	match String(cost.kind):
		"difficulty":
			RunState.add_difficulty(fraction, "altars")
			return fraction
		"elites":
			RunState.elite_chance_bonus += fraction
		"sky_duration":
			RunState.sky_duration_multiplier *= 1.0 + fraction
		"events":
			RunState.event_chance_bonus += fraction
		"disasters":
			# Lo lee WorldDirector._maybe_weather.
			RunState.disaster_chance_bonus += fraction
		_:
			push_warning("CurseShrine: unknown cost kind '%s'" % cost.kind)
	return 0.0


## El beneficio "cofre gratis": un cofre sin precio que tira su rareza al
## abrirse, a chest_drop_distance del obelisco en una dirección al azar.
## Chest.spawn_free lo cuelga de la arena: el obelisco se libera unos
## segundos después de pagar y no se lleva el premio.
func _drop_free_chest() -> void:
	var angle := randf() * TAU
	Chest.spawn_free(get_tree(), global_position
			+ Vector3(cos(angle), 0.0, sin(angle)) * chest_drop_distance)
