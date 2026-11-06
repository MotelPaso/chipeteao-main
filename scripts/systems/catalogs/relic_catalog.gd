class_name RelicCatalog
extends RefCounted
## Catálogo de reliquias: mejoras permanentes de stats entre incursiones que
## se compran con esquirlas en la Armería. Una reliquia nueva es una fila aquí.
## Las cantidades son chicas a propósito (una Armería completa es ~+10% de
## poder, lejos de un build de tomos): la maestría sigue siendo la curva real.
##
## Se puede cambiar libremente: display_name, description, amount,
## amount_text, max_ranks, base_cost, cost_growth.
## Llave interna, NUNCA la cambies: id (llave de SaveData.relic_ranks en el
## guardado).
## stat debe ser un efecto de PlayerStats._apply_effect.
##
## Campos de cada fila:
##   id: llave interna (ver arriba). Nunca se muestra.
##   display_name, description: texto del jugador; el "%s" de description se
##       llena con amount_text.
##   stat: efecto de PlayerStats; se aplica en cada recompute como
##       amount * rangos comprados.
##   amount: efecto por rango (porcentaje en los stats multiplicadores; plano
##       en armor, luck y max_hp).
##   amount_text: cómo se lee un rango en la fila ("+2%"); su número debe
##       coincidir con amount.
##   max_ranks, base_cost, cost_growth: tope de rangos y escalera de precios en
##       esquirlas; con N rangos comprados, el siguiente cuesta
##       base_cost * cost_growth^N (redondeado).
## Guardado: SaveData.relic_ranks (purchase_relic / relic_rank).

const RELIC_LIBRARY: Array[Dictionary] = [
	{
		"id": "relic_fury", "display_name": "Sello de brasas",
		"description": "Todo el daño %s por rango.",
		"stat": "damage", "amount": 2.0, "amount_text": "+2%",
		"max_ranks": 5, "base_cost": 40, "cost_growth": 1.6,
	},
	{
		"id": "relic_vitality", "display_name": "Amuleto de roble",
		"description": "HP máx. %s por rango.",
		"stat": "max_hp", "amount": 6.0, "amount_text": "+6",
		"max_ranks": 5, "base_cost": 40, "cost_growth": 1.6,
	},
	{
		"id": "relic_haste", "display_name": "Colmillo silbante",
		"description": "Velocidad de ataque %s por rango.",
		"stat": "cooldown", "amount": 1.5, "amount_text": "+1.5%",
		"max_ranks": 5, "base_cost": 50, "cost_growth": 1.6,
	},
	{
		"id": "relic_fortune", "display_name": "Bigote dorado",
		"description": "Suerte %s por rango (cartas de mejora más raras).",
		"stat": "luck", "amount": 3.0, "amount_text": "+3",
		"max_ranks": 4, "base_cost": 45, "cost_growth": 1.6,
	},
	{
		"id": "relic_stride", "display_name": "Tobillera de marea",
		"description": "Velocidad de movimiento %s por rango.",
		"stat": "move_speed", "amount": 1.5, "amount_text": "+1.5%",
		"max_ranks": 4, "base_cost": 35, "cost_growth": 1.6,
	},
	{
		"id": "relic_hide", "display_name": "Coraza de percebes",
		"description": "Armadura %s por rango (reducción fija de daño).",
		"stat": "armor", "amount": 1.0, "amount_text": "+1",
		"max_ranks": 4, "base_cost": 50, "cost_growth": 1.7,
	},
]


## Índice id -> fila armado al primer uso (ver CatalogIndex):
## PlayerStats._apply_relics recorre la biblioteca entera en cada recompute.
static var _by_id: Dictionary[String, Dictionary] = {}


## Fila con ese id, o un Dictionary vacío si no existe.
static func by_id(relic_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(RELIC_LIBRARY)
	return _by_id.get(relic_id, {})


## Precio en esquirlas del rango `owned_ranks + 1` (owned_ranks cuenta desde 0),
## o -1 si la reliquia no existe o ya está en su tope.
static func next_rank_cost(relic_id: String, owned_ranks: int) -> int:
	var row := by_id(relic_id)
	if row.is_empty() or owned_ranks >= int(row.max_ranks):
		return -1
	return roundi(float(row.base_cost) * pow(float(row.cost_growth), float(owned_ranks)))
