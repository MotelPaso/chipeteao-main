class_name Tome
extends RefCounted
## Catálogo estático de Tomos: objetos pasivos acumulables cuyos efectos de
## stats alimentan la capa PlayerStats del jugador. Un tomo nuevo es una fila
## aquí, igual que en UpgradePool.WEAPON_LIBRARY.
##
## Edita aquí: una fila por tomo.
## Se puede cambiar sin romper nada:
##   display_name: texto para el jugador; el título de la carta le suma el
##             numeral de la copia siguiente («Tomo de Furia II»). Las
##             copias no tienen techo (sí lo tiene la cantidad de tomos
##             DISTINTOS); ver stack_label().
##   glyph:    2 letras de la casilla del HUD mientras no hay sprite. Se
##             DECLARA, no sale de display_name: todos empiezan con
##             «Tomo de» y el resto choca (Persistencia/Peligro darían «PE»).
##             Único entre esta tabla, WEAPON_LIBRARY, EVOLUTION_LIBRARY e
##             ITEM_LIBRARY: la franja mezcla las cuatro.
##   description: texto de la carta; el "%d" se llena con el amount del
##             PRIMER efecto, escalado por la rareza.
##   effects:  lista de {stat, amount}. amount es por copia a potencia
##             Común; la potencia de la rareza sacada lo escala al tomarlo.
## Llave interna (la lee el código; cambiarla rompe algo):
##   id:       identificador en inglés, nunca se muestra.
##   effects[].stat: nombres de stat de PlayerStats (ver su _apply_effect).

## Tabla de numerales romanos para stack_label(). Las copias no tienen techo,
## así que el numeral se arma con estos pares en vez de salir de una lista
## fija; se usa numeral y no «Nv %d», que el GLOSARIO (regla 6) reserva para
## el nivel de la partida.
const ROMAN_VALUES: Array[int] = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
const ROMAN_SYMBOLS: Array[String] = [
	"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]

const TOME_LIBRARY: Array[Dictionary] = [
	{
		"id": "tome_fury", "display_name": "Tomo de Furia", "glyph": "FU",
		"description": "Daño de todas las armas +%d%%",
		"effects": [{"stat": "damage", "amount": 15.0}],
	},
	{
		"id": "tome_haste", "display_name": "Tomo de Celeridad", "glyph": "CE",
		"description": "Velocidad de ataque de todas las armas +%d%%",
		"effects": [{"stat": "cooldown", "amount": 8.0}],
	},
	{
		"id": "tome_reach", "display_name": "Tomo de Alcance", "glyph": "AL",
		"description": "Área de ataque +%d%%",
		"effects": [{"stat": "area", "amount": 12.0}],
	},
	{
		"id": "tome_swiftness", "display_name": "Tomo de Ligereza", "glyph": "LI",
		"description": "Velocidad de movimiento +%d%%",
		"effects": [{"stat": "move_speed", "amount": 8.0}],
	},
	{
		"id": "tome_precision", "display_name": "Tomo de Precisión", "glyph": "PR",
		"description": "Prob. de crítico +%d%%",
		"effects": [{"stat": "crit_chance", "amount": 6.0}],
	},
	{
		"id": "tome_ruin", "display_name": "Tomo de Ruina", "glyph": "RU",
		"description": "Daño crítico +%d%%",
		"effects": [{"stat": "crit_damage", "amount": 30.0}],
	},
	{
		"id": "tome_thirst", "display_name": "Tomo de Sed", "glyph": "SE",
		"description": "Robo de vida: te curas el %d%% del daño hecho",
		"effects": [{"stat": "lifesteal", "amount": 3.0}],
	},
	{
		"id": "tome_stone", "display_name": "Tomo de Piedra", "glyph": "PI",
		"description": "Armadura +%d (reducción fija de daño)",
		"effects": [{"stat": "armor", "amount": 2.0}],
	},
	{
		"id": "tome_mist", "display_name": "Tomo de Bruma", "glyph": "BR",
		"description": "Evasión: %d%% de probabilidad de esquivar golpes",
		"effects": [{"stat": "evasion", "amount": 4.0}],
	},
	# Capa de stats de suerte, proyectiles, duración, XP, azar y dificultad.
	{
		"id": "tome_fortune", "display_name": "Tomo de Fortuna", "glyph": "FO",
		"description": "Suerte +%d (mejores rarezas de cartas y objetos)",
		"effects": [{"stat": "luck", "amount": 10.0}],
	},
	{
		"id": "tome_multitude", "display_name": "Tomo de Multitud", "glyph": "MU",
		"description": "+%d proyectil(es) en cada arma de andanada",
		"effects": [{"stat": "projectiles", "amount": 1.0}],
	},
	{
		"id": "tome_lingering", "display_name": "Tomo de Persistencia", "glyph": "PS",
		"description": "Duración de efectos +%d%% (ralentizaciones, charcos, veneno)",
		"effects": [{"stat": "duration", "amount": 20.0}],
	},
	{
		"id": "tome_wisdom", "display_name": "Tomo de Sabiduría", "glyph": "SA",
		"description": "XP ganada +%d%%",
		"effects": [{"stat": "xp_gain", "amount": 10.0}],
	},
	{
		# Azar: cada copia saca boons de stats al azar — más y más grandes a
		# mayor rareza (la tirada la hace PlayerStats.add_tome).
		"id": "tome_chance", "display_name": "Tomo del Azar", "glyph": "AZ",
		"description": "Apuesta: %d bonificación(es) de stat al azar, mayores a más rareza",
		"effects": [{"stat": "gambling", "amount": 1.0}],
		"gamble": true,
	},
	{
		# La dificultad es DE LA PARTIDA (compartida en co-op): enemigos más
		# duros que pagan más XP; PlayerStats manda el total a RunState.
		"id": "tome_peril", "display_name": "Tomo del Peligro", "glyph": "PG",
		"description": "Dificultad +%d%%: enemigos más duros, más XP",
		"effects": [{"stat": "difficulty", "amount": 10.0}],
	},
]

## Stats en que puede caer un boon del Tomo del Azar: {stat, amount, label}
## a potencia Común (la potencia de la rareza lo escala y suma más boons).
## `label` lleva exactamente un "%d", que se llena con el amount sacado: el
## aviso del HUD muestra lo que pagó la apuesta.
const GAMBLE_BOONS: Array[Dictionary] = [
	{"stat": "damage", "amount": 12.0, "label": "daño +%d%%"},
	{"stat": "cooldown", "amount": 6.0, "label": "velocidad de ataque +%d%%"},
	{"stat": "area", "amount": 10.0, "label": "área +%d%%"},
	{"stat": "move_speed", "amount": 6.0, "label": "velocidad +%d%%"},
	{"stat": "crit_chance", "amount": 5.0, "label": "prob. de crítico +%d%%"},
	{"stat": "crit_damage", "amount": 25.0, "label": "daño crítico +%d%%"},
	{"stat": "lifesteal", "amount": 2.0, "label": "robo de vida +%d%%"},
	{"stat": "armor", "amount": 2.0, "label": "armadura +%d"},
	{"stat": "evasion", "amount": 3.0, "label": "evasión +%d%%"},
	{"stat": "luck", "amount": 8.0, "label": "suerte +%d"},
	{"stat": "max_hp", "amount": 15.0, "label": "HP máx. +%d"},
	{"stat": "xp_gain", "amount": 8.0, "label": "ganancia de XP +%d%%"},
	{"stat": "duration", "amount": 15.0, "label": "duración de efectos +%d%%"},
]

## Índice id -> fila, construido al primer uso (ver CatalogIndex):
## PlayerStats.recompute() resuelve una fila por copia llevada en cada subida
## de nivel y cada boon de altar.
static var _by_id: Dictionary[String, Dictionary] = {}


static func by_id(tome_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(TOME_LIBRARY)
	return _by_id.get(tome_id, {})


## Cuántos boons da una copia del Tomo del Azar a la potencia dada: Común 1,
## Raro 2, Épico 3, Legendario 4. LA única fuente de esa cuenta: PlayerStats
## saca exactamente esta cantidad y UpgradePool imprime la misma, así la
## carta nunca promete menos de lo que da.
static func gamble_boon_count(potency: float) -> int:
	return 1 + clampi(UpgradePool.potency_rank(potency), 0, 3)


## Título de carta para ofrecer la copia dada (desde 1): el nombre solo para
## la primera, «Nombre II», «Nombre VII», «Nombre XIV»... para las siguientes.
static func display_title(tome: Dictionary, stack: int) -> String:
	var title := String(tome.display_name)
	if stack <= 1:
		return title
	return title + " " + stack_label(stack)


## EL numeral de copias, para el título de la carta y la esquina de la
## casilla del HUD. Cualquier cantidad desde 1 se lee como numeral.
static func stack_label(stack: int) -> String:
	var value := maxi(stack, 1)
	var label := ""
	for i: int in ROMAN_VALUES.size():
		while value >= ROMAN_VALUES[i]:
			value -= ROMAN_VALUES[i]
			label += ROMAN_SYMBOLS[i]
	return label


## Lee una lista de boons sacados ({stat, amount, label}) como una línea,
## para el aviso del HUD: "daño +18%, suerte +12". Las filas sin label usan
## su id de stat, así una fila nueva de GAMBLE_BOONS nunca imprime vacío.
static func boon_text(boons: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for boon: Dictionary in boons:
		var label := String(boon.get("label", ""))
		var amount := roundi(float(boon.get("amount", 0.0)))
		parts.append(label % amount if not label.is_empty()
				else "%s +%d" % [String(boon.get("stat", "?")), amount])
	return ", ".join(parts)
