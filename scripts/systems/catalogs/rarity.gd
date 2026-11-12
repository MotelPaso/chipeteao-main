class_name Rarity
extends RefCounted
## Rarezas de cartas, cofres y objetos: la tabla de niveles y el sorteo
## inclinado por la suerte. Es la única implementación de la curva de suerte
## del juego (cartas, cofres, vendedor y objetos la usan).
##
## Se puede cambiar libremente: weight, potency y color de cada fila de TIERS,
## los textos de DISPLAY_NAMES y la curva de suerte (LUCK_TILT_PER_POINT,
## MAX_LUCK_TILT).
## Llave interna, NUNCA la cambies: name (Common, Rare, Epic, Legendary). Es un
## IDENTIFICADOR, no texto: llavea los precios de cofre
## (RunState.CHEST_BASE_PRICES), el campo `rarity` de cada fila de
## ItemCatalog, las cartas con rareza fija y los pisos min_rarity que pasan
## cofres, altares y el director del mundo. Queda en inglés; las pantallas lo
## muestran con display_name().
## El orden de TIERS va de menor a mayor: los pisos y potency_rank cuentan con
## ese orden.

## Pendiente de la suerte en cero: cada punto de suerte mueve esta fracción
## del peso de Common hacia arriba. La curva de _weights se aleja de esta
## pendiente al crecer la suerte, pero nunca se aplana.
const LUCK_TILT_PER_POINT: float = 0.01
## Asíntota de esa curva: como máximo se mueve esta fracción del peso de
## Common. Se acerca sin llegar nunca, así cada punto de suerte extra aporta.
const MAX_LUCK_TILT: float = 0.5

## Niveles de rareza, de menor a mayor. weight: peso relativo del sorteo.
## potency: multiplicador de la cantidad de la carta. color: color de la
## rareza en pantalla.
const TIERS: Array[Dictionary] = [
	{"name": "Common", "color": Color(0.62, 0.65, 0.68), "weight": 60.0, "potency": 1.0},
	{"name": "Rare", "color": Color(0.3, 0.55, 1.0), "weight": 25.0, "potency": 1.5},
	{"name": "Epic", "color": Color(0.68, 0.32, 0.95), "weight": 12.0, "potency": 2.0},
	{"name": "Legendary", "color": Color(1.0, 0.78, 0.2), "weight": 3.0, "potency": 3.0},
]

## Nombre que ve el jugador por cada name de TIERS. Es el único lugar donde se
## traduce una rareza.
const DISPLAY_NAMES: Dictionary[String, String] = {
	"Common": "Común",
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
## Legendary 3.0 -> 3); para valores fuera de la tabla gana la más cercana.
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
	var weights := _weights(luck)
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


## Pesos de rareza al sortear: la suerte mueve una fracción del peso de la
## rareza base (TIERS[0], Common) a las superiores, repartida en proporción a
## sus pesos base. La fracción se acerca a MAX_LUCK_TILT sin cortarse en seco,
## así la suerte sigue sirviendo por encima de 50 (el Tomo de Fortuna solo
## puede llegar a 150).
static func _weights(luck: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	var upper_total := 0.0
	for i: int in TIERS.size():
		weights.append(float(TIERS[i].weight))
		if i > 0:
			upper_total += float(TIERS[i].weight)
	var tilt := MAX_LUCK_TILT * (1.0 - exp(-maxf(luck, 0.0) * LUCK_TILT_PER_POINT / MAX_LUCK_TILT))
	if tilt <= 0.0 or upper_total <= 0.0:
		return weights
	var moved := weights[0] * tilt
	weights[0] -= moved
	for i: int in range(1, weights.size()):
		weights[i] += moved * float(TIERS[i].weight) / upper_total
	return weights
