class_name Tome
extends RefCounted
## Catálogo de tomos. Cada tomo es un stat permanente que se acumula por
## stacks (sin tope de stacks; solo hay tope de tomos DISTINTOS, ver
## Player.max_tomes).
##
## Campos de un tomo:
##   id: identificador (no lo cambies: lo usan guardados y PlayerStats).
##   short: sigla de 2 letras para la franja del HUD.
##   title: nombre base; display_title() le añade el numeral.
##   description: texto de la carta, con un "%d" que se llena con la cantidad.
##   effects: lista de {stat, amount, values?}.
##       stat: id de stat de PlayerStats._apply_effect (damage, cooldown,
##           area, move_speed, crit_chance, crit_damage, lifesteal, evasion,
##           armor, luck, thorns, max_hp, projectiles, duration, xp_gain,
##           difficulty, jumps, powerup_chance, pickup_radius, gambling).
##       amount: cantidad base (respaldo si no hay `values`).
##       values: OPCIONAL. Cantidad FIJA por rareza, en el orden de
##           Rarity.TIERS: [Poco común, Raro, Épico, Legendario]. Si existe manda
##           sobre amount x potencia. ESTAS LISTAS SE EDITAN PARA BALANCEAR.
##   gamble: true en el Tomo del Azar (ver gamble_boon_count y GAMBLE_MULTIPLIERS).

const TOME_LIBRARY: Array[Dictionary] = [
	{
		"id": "tome_fury", "short": "FU", "title": "Tomo de Furia",
		"description": "Daño +%d%%",
		"effects": [{"stat": "damage", "amount": 7.0, "values": [7, 10, 12, 15]}],
	},
	{
		"id": "tome_haste", "short": "CE", "title": "Tomo de Celeridad",
		"description": "Vel. de ataque +%d%%",
		# "cooldown" suma amount/100 a la velocidad de ataque (+100% = el doble de rápido).
		"effects": [{"stat": "cooldown", "amount": 8.0, "values": [10, 13, 17, 20]}],
	},
	{
		"id": "tome_reach", "short": "AL", "title": "Tomo de Alcance",
		"description": "Área +%d%%",
		"effects": [{"stat": "area", "amount": 8.0, "values": [8, 10, 13, 15]}],
	},
	{
		"id": "tome_swiftness", "short": "LI", "title": "Tomo de Ligereza",
		"description": "Vel. de movimiento +%d%%",
		"effects": [{"stat": "move_speed", "amount": 7.0, "values": [10, 13, 17, 20]}],
	},
	{
		"id": "tome_precision", "short": "PR", "title": "Tomo de Precisión",
		"description": "Prob. crítico +%d%%",
		"effects": [{"stat": "crit_chance", "amount": 5.0, "values": [7, 10, 13, 15]}],
	},
	{
		"id": "tome_thirst", "short": "SE", "title": "Tomo de Sed",
		"description": "Robo de vida +%d%%",
		"effects": [{"stat": "lifesteal", "amount": 3.0, "values": [4, 6, 8, 10]}],
	},
	{
		"id": "tome_stone", "short": "PI", "title": "Tomo de Piedra",
		"description": "Armadura +%d%%",
		"effects": [{"stat": "armor", "amount": 5.0, "values": [5, 7, 9, 12]}],
	},
	{
		"id": "tome_mist", "short": "BR", "title": "Tomo de Bruma",
		"description": "Evasión +%d%%",
		"effects": [{"stat": "evasion", "amount": 5.0, "values": [5, 7, 9, 10]}],
	},
	{
		"id": "tome_fortune", "short": "FO", "title": "Tomo de Fortuna",
		"description": "Suerte +%d",
		"effects": [{"stat": "luck", "amount": 7.0, "values": [7, 10, 12, 15]}],
	},
	{
		"id": "tome_multitude", "short": "MU", "title": "Tomo de Multitud",
		"description": "+%d proyectil en armas de andanada",
		"effects": [{"stat": "projectiles", "amount": 1.0, "values": [1, 1.3, 1.7, 2]}],
	},
	{
		"id": "tome_lingering", "short": "PS", "title": "Tomo de Persistencia",
		"description": "Duración de efectos +%d%%",
		"effects": [{"stat": "duration", "amount": 20.0, "values": [20, 26, 34, 40]}],
	},
	{
		"id": "tome_wisdom", "short": "SA", "title": "Tomo de Sabiduría",
		"description": "XP +%d%%",
		"effects": [{"stat": "xp_gain", "amount": 7.0, "values": [7, 10, 12, 14]}],
	},
	{
		"id": "tome_vitality", "short": "VI", "title": "Tomo de Vitalidad",
		"description": "HP máx. +%d",
		"effects": [{"stat": "max_hp", "amount": 20.0, "values": [20, 26, 34, 40]}],
	},
	{
		# Apuesta: sin values. La cantidad de boons sale de gamble_boon_count()
		# y PlayerStats los sortea de los dones de altar (ChargeShrine.ALTAR_BOONS)
		# al tomarlo.
		"id": "tome_chance", "short": "AZ", "title": "Tomo del Azar",
		"description": "Apuesta: %d boons al azar",
		"gamble": true,
		"effects": [{"stat": "gambling", "amount": 1.0}],
	},
	{
		# Un riesgo que también escala con la rareza: más rareza, más dificultad.
		"id": "tome_peril", "short": "PG", "title": "Tomo del Peligro",
		"description": "Dificultad +%d%%",
		"effects": [{"stat": "difficulty", "amount": 7.0, "values": [7, 10, 12, 14]}],
	},
]

## Stats cuyo valor se muestra como porcentaje; el resto, como número plano.
const PERCENT_STATS: Array[String] = [
	"damage", "cooldown", "area", "move_speed", "crit_chance", "crit_damage",
	"lifesteal", "evasion", "armor", "duration", "xp_gain", "difficulty",
	"pickup_radius", "powerup_chance",
]

## Nombre que ve el jugador por cada id de stat.
const STAT_NAMES: Dictionary[String, String] = {
	"damage": "Daño", "cooldown": "Vel. de ataque", "area": "Área",
	"move_speed": "Vel. de movimiento", "crit_chance": "Prob. crítico",
	"crit_damage": "Daño crítico", "lifesteal": "Robo de vida",
	"evasion": "Evasión", "armor": "Armadura", "luck": "Suerte",
	"thorns": "Espinas", "max_hp": "HP máx.", "projectiles": "Proyectiles",
	"duration": "Duración de efectos", "xp_gain": "XP", "difficulty": "Dificultad",
	"jumps": "Saltos", "powerup_chance": "Prob. de power-ups",
	"pickup_radius": "Radio de recolección",
}

## Cantidad de un efecto para la potencia de una rareza: el valor fijo de
## `values` si existe; si no, la cantidad base por la potencia.
static func effect_amount(effect: Dictionary, potency: float) -> float:
	var values: Array = effect.get("values", [])
	if not values.is_empty():
		var rank := mini(Rarity.potency_rank(potency), values.size() - 1)
		return float(values[rank])
	return float(effect.amount) * potency


## Tomo del Azar, edita aquí: por rareza (en el orden de Rarity.TIERS), un
## multiplicador por cada stat que sortea. Las stats salen de los dones de
## altar (ChargeShrine.ALTAR_BOONS) y su valor normal es el primero de su
## lista `values` (el de Poco común). Cuántos números = cuántas stats.
##   Poco común (y la carta base de un tomo nuevo): 1 stat x1.5
##   Raro:       1 stat x1.5 y otra normal
##   Épico:      2 stats x1.5
##   Legendario: 2 stats x1.5 y otra normal
const GAMBLE_MULTIPLIERS: Array[Array] = [
	[1.5],
	[1.5, 1.0],
	[1.5, 1.5],
	[1.5, 1.5, 1.0],
]


## Multiplicadores del Tomo del Azar para una potencia de rareza (uno por stat).
static func gamble_multipliers(potency: float) -> Array:
	var rank := mini(Rarity.potency_rank(potency), GAMBLE_MULTIPLIERS.size() - 1)
	return GAMBLE_MULTIPLIERS[rank]


## Stats que sortea el Tomo del Azar para una potencia de rareza.
static func gamble_boon_count(potency: float) -> int:
	return gamble_multipliers(potency).size()


## Número de un stack, en cifras: 1 -> "1", 2 -> "2".
static func stack_label(stack: int) -> String:
	return str(stack)


## Título de la carta: «Tomo de Furia 2».
static func display_title(tome: Dictionary, stack: int) -> String:
	return "%s %s" % [String(tome.title), stack_label(stack)]


## Fila de un tomo por id, o {} si no existe.
static func by_id(tome_id: String) -> Dictionary:
	for tome: Dictionary in TOME_LIBRARY:
		if String(tome.id) == tome_id:
			return tome
	return {}

## Texto de un boon, p. ej. "+10% Daño" o "+5 Suerte". Acepta el diccionario
## del boon {stat, amount, label} o (stat, amount) por separado.
static func boon_text(boon_or_stat: Variant, amount: float = 0.0) -> String:
	var stat := ""
	var value := amount
	var label := ""
	if boon_or_stat is Dictionary:
		var boon: Dictionary = boon_or_stat
		stat = String(boon.get("stat", ""))
		value = float(boon.get("amount", 0.0))
		label = String(boon.get("label", ""))
	else:
		stat = String(boon_or_stat)
	if label.is_empty():
		label = STAT_NAMES.get(stat, stat)
	var prefix := "+" if value >= 0.0 else "-"
	var suffix := "%" if PERCENT_STATS.has(stat) else ""
	return "%s%d%s %s" % [prefix, absi(roundi(value)), suffix, label]
