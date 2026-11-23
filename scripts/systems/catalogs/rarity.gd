class_name Rarity
extends RefCounted
## Rarezas de cartas, cofres y objetos: la tabla de niveles y el sorteo
## inclinado por la suerte. Es la única implementación de la curva de suerte
## del juego (cartas, cofres, vendedor y objetos la usan).
##
## Se puede cambiar libremente: weight, potency y color de cada fila de TIERS,
## los textos de DISPLAY_NAMES y la fuerza de la suerte (LUCK_REFERENCE y compañía).
## Llave interna, NUNCA la cambies: name (Common, Rare, Epic, Legendary). Es un
## IDENTIFICADOR, no texto: llavea los precios del vendedor
## (Vendor.item_price_factors), el campo `rarity` de cada fila de
## ItemCatalog, las cartas con rareza fija y los pisos min_rarity que pasan
## cofres, altares y el director del mundo. Queda en inglés; las pantallas lo
## muestran con display_name().
## El orden de TIERS va de menor a mayor: los pisos y potency_rank cuentan con
## ese orden.

## Suerte, edita aquí. La suerte arma un multiplicador
##   m = 1 + LUCK_BOOST_AT_REFERENCE x (suerte / LUCK_REFERENCE) ^ LUCK_CURVE
## y el peso de cada rareza se multiplica por m elevado a su escalón
## (Poco común x1, Raro x m, Épico x m², Legendario x m³).
## Con 800 / 3.92 / 1.5: Legendario 3% sin suerte, ~4.5% con 100, ~8% con 200,
## ~20% con 400 y 50% con 800.
## Suerte a la que el multiplicador vale 1 + LUCK_BOOST_AT_REFERENCE.
const LUCK_REFERENCE: float = 800.0
## Cuánto sube el multiplicador a LUCK_REFERENCE de suerte. 3.92 = Legendario
## al 50% justo en LUCK_REFERENCE (con los pesos de TIERS de hoy).
const LUCK_BOOST_AT_REFERENCE: float = 3.92
## Curva de la suerte: 1 = cada punto vale lo mismo; más de 1 = la poca suerte
## influye poco y la mucha, mucho.
const LUCK_CURVE: float = 1.5
## La dificultad de la partida agranda la suerte en porcentaje: suerte x
## (1 + dificultad x esto). Con 0.5, +50% de dificultad = suerte x1.25 (sin
## suerte no hay nada que agrandar). 0 = la dificultad no toca la suerte.
const DIFFICULTY_LUCK_SHARE: float = 0.5
## Niveles de rareza, de menor a mayor. weight: peso relativo del sorteo.
## potency: multiplicador de la cantidad de una carta sin lista `values`
## (x1, x1.3, x1.7, x2). color: color de la rareza en pantalla. La primera
## se llama "Common" por dentro (llave de objetos y precios) y se ve como
## «Poco común», en verde.
const TIERS: Array[Dictionary] = [
	{"name": "Common", "color": Color(0.35, 0.8, 0.4), "weight": 70.0, "potency": 1.0},
	{"name": "Rare", "color": Color(0.3, 0.55, 1.0), "weight": 19.0, "potency": 1.3},
	{"name": "Epic", "color": Color(0.68, 0.32, 0.95), "weight": 8.0, "potency": 1.7},
	{"name": "Legendary", "color": Color(1.0, 0.78, 0.2), "weight": 3.0, "potency": 2.0},
]

## Lo que llevan las cartas de algo NUEVO (el primer tomo, un arma que no
## tienes): no es una rareza ni se sortea, solo el aspecto «base» en gris.
## Da lo mismo que la primera rareza.
const BASE: Dictionary = {"name": "Base", "color": Color(0.62, 0.65, 0.68),
		"weight": 0.0, "potency": 1.0}

## Nombre que ve el jugador por cada name de TIERS. Es el único lugar donde se
## traduce una rareza.
const DISPLAY_NAMES: Dictionary[String, String] = {
	"Common": "Poco común",
	"Base": "Nuevo",
	"Rare": "Raro",
	"Epic": "Épico",
	"Legendary": "Legendario",
}


## Traduce un name de rareza para mostrarlo. Toda pantalla que imprime una
## rareza pasa por aquí; nada compara contra el resultado.
static func display_name(rarity_name: String) -> String:
	return DISPLAY_NAMES.get(rarity_name, rarity_name)


## Índice de una rareza por name; un nombre desconocido o vacío da la rareza
## base (índice 0), que no pone piso.
static func index_of(rarity_name: String) -> int:
	for i: int in TIERS.size():
		if String(TIERS[i].name) == rarity_name:
			return i
	return 0


## Índice de rareza para un valor de potencia (Common 1.0 -> 0 ...
## Legendary 2.0 -> 3); para valores fuera de la tabla gana la más cercana.
static func potency_rank(potency: float) -> int:
	var best := 0
	var best_gap := INF
	for i: int in TIERS.size():
		var gap := absf(float(TIERS[i].potency) - potency)
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


## Rareza fija por name (subida al piso `floor_index`), o una sorteada con
## roll() si `fixed_name` está vacío o no existe.
static func resolve(fixed_name: String, luck: float, floor_index: int = 0) -> Dictionary:
	if not fixed_name.is_empty():
		for i: int in TIERS.size():
			if String(TIERS[i].name) == fixed_name:
				# El piso también sube las rarezas fijas: una elección
				# «Epic o más» nunca muestra una carta fijada en Rare.
				return TIERS[maxi(i, floor_index)]
	return roll(luck, floor_index)


## Sortea una rareza, inclinada por la suerte y con piso en `floor_index`.
## Hace una sola tirada de randf() (el orden de tiradas importa en los soaks
## con semilla).
static func roll(luck: float, floor_index: int = 0) -> Dictionary:
	return _pick(_weights(luck), floor_index)


## Una tirada sobre `weights` (uno por fila de TIERS), con piso.
static func _pick(weights: PackedFloat32Array, floor_index: int) -> Dictionary:
	var total := 0.0
	for weight: float in weights:
		total += weight
	var pick := randf() * total
	var index := 0
	for i: int in TIERS.size():
		pick -= weights[i]
		if pick <= 0.0:
			index = i
			break
	return TIERS[maxi(index, floor_index)]


## La suerte que cuenta en los sorteos: la del jugador agrandada por la
## dificultad de la partida (DIFFICULTY_LUCK_SHARE). Nunca negativa.
static func effective_luck(luck: float) -> float:
	return maxf(luck, 0.0) * (1.0 + RunState.difficulty_bonus * DIFFICULTY_LUCK_SHARE)


## Pesos de rareza al sortear: la suerte multiplica directamente el peso de
## cada rareza según su escalón (ver LUCK_REFERENCE), así cuanto más alta la
## rareza, más la empuja la suerte. Todo sorteo de rareza del juego (cartas,
## cofres, vendedor, ruleta, bloque de la suerte) pasa por aquí.
static func _weights(luck: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	var ratio := effective_luck(luck) / maxf(LUCK_REFERENCE, 1.0)
	var boost := 1.0 + LUCK_BOOST_AT_REFERENCE * pow(ratio, LUCK_CURVE)
	for i: int in TIERS.size():
		weights.append(float(TIERS[i].weight) * pow(boost, float(i)))
	return weights
