class_name ItemCatalog
extends RefCounted
## Catálogo estático de objetos de partida: lo que pagan los cofres. Los
## objetos son independientes de armas y tomos — un raider puede llevar
## cualquier cantidad de copias de cualquiera — y cada uno tiene una rareza
## FIJA (la rareza del cofre decide de qué grupo sale; la suerte inclina la
## rareza del cofre, nunca la del objeto). Un objeto nuevo es una fila aquí
## (más una rama en ItemBag solo si trae un `kind` de comportamiento nuevo).
##
## Edita aquí: una fila por objeto.
## Se puede cambiar sin romper nada:
##   display_name, description: texto para el jugador (HUD, avisos, cofres).
##   glyph:    1-2 letras de la casilla del HUD mientras no hay sprite. Se
##             DECLARA (no sale del nombre) y debe ser único entre armas,
##             evoluciones, tomos, objetos y power-ups: la franja los mezcla.
##   icon:     OPCIONAL, ruta res:// de una textura; si está, el HUD la
##             muestra en vez del glifo.
##   effects:  OPCIONAL, [{stat, amount}] de PlayerStats POR COPIA, por el
##             mismo canal que los tomos (recompute).
## Llave interna (la lee el código; cambiarla rompe algo):
##   id:       identificador en inglés, nunca se muestra; nombra los
##             contadores de SaveData. Los objetos `hook` además se buscan
##             por id en los santuarios: renombrar su id los apaga.
##   rarity:   "Common" | "Rare" | "Epic" | "Legendary" (nombres de
##             UpgradePool); la pantalla lo traduce con
##             UpgradePool.rarity_display().
##   kind:     OPCIONAL, comportamiento que maneja ItemBag: "magnet",
##             "poison_on_hit", "titan", "spiders", "shock_dash", "saiyan",
##             "zenkai" o "hook" (un contador que leen altares y portales).
## No hay kind "pet": la mascota es un espacio único del Player que solo
## llenan la caja de mascota y el traficante, así que un cofre o la ruleta
## nunca pueden repartir una (tirarían la que el jugador eligió).

const ITEM_LIBRARY: Array[Dictionary] = [
	# --- Common ---------------------------------------------------------
	{
		"id": "whetstone", "display_name": "Piedra de afilar", "rarity": "Common",
		"glyph": "PA", "description": "Todo el daño +8% por copia",
		"effects": [{"stat": "damage", "amount": 8.0}],
	},
	{
		"id": "iron_rations", "display_name": "Raciones de hierro", "rarity": "Common",
		"glyph": "RH", "description": "HP máx. +15 por copia",
		"effects": [{"stat": "max_hp", "amount": 15.0}],
	},
	{
		"id": "lucky_coin", "display_name": "Moneda de la suerte", "rarity": "Common",
		"glyph": "MO", "description": "Suerte +8 por copia",
		"effects": [{"stat": "luck", "amount": 8.0}],
	},
	{
		"id": "swift_boots", "display_name": "Botas veloces", "rarity": "Common",
		"glyph": "BV", "description": "Velocidad de movimiento +6% por copia",
		"effects": [{"stat": "move_speed", "amount": 6.0}],
	},
	# --- Rare -----------------------------------------------------------
	{
		# PlayerStats pone techo a los saltos (MAX_EXTRA_JUMPS): las copias
		# por encima del techo no hacen nada, a propósito.
		"id": "spring_boots", "display_name": "Botas de resorte", "rarity": "Rare",
		"glyph": "RS", "description": "+1 salto en el aire por copia",
		"effects": [{"stat": "jumps", "amount": 1.0}],
	},
	{
		"id": "magnet", "display_name": "Imán", "rarity": "Rare",
		"glyph": "IM", "kind": "magnet",
		"description": "Cada tanto atrae todas las gemas de XP del mapa; cada copia lo hace antes y suma +10% de XP",
		"effects": [{"stat": "xp_gain", "amount": 10.0}],
	},
	{
		"id": "fart_bag", "display_name": "Bolsa de pedos", "rarity": "Rare",
		"glyph": "BP", "kind": "poison_on_hit",
		"description": "Los golpes de arma envenenan; más copias = veneno más fuerte, y la duración de efectos lo alarga",
	},
	{
		"id": "keen_eye", "display_name": "Ojo agudo", "rarity": "Rare",
		"glyph": "OA", "description": "Prob. de crítico +5% por copia",
		"effects": [{"stat": "crit_chance", "amount": 5.0}],
	},
	# --- Epic -----------------------------------------------------------
	{
		"id": "titan_blood", "display_name": "Sangre de titán", "rarity": "Epic",
		"glyph": "ST", "kind": "titan",
		"description": "Creces un 8% y tus ataques cubren +8% de área por copia",
		"effects": [{"stat": "area", "amount": 8.0}],
	},
	{
		"id": "demon_blood", "display_name": "Sangre de demonio", "rarity": "Epic",
		"glyph": "SD", "kind": "hook",
		"description": "Los altares demoníacos dan +25% más por copia",
	},
	{
		"id": "master_key", "display_name": "Llave maestra", "rarity": "Epic",
		"glyph": "LM", "kind": "hook",
		"description": "Los altares de carga se llenan 20% más rápido y dan +20% más por copia",
	},
	# --- Legendary ------------------------------------------------------
	{
		"id": "superhero_mask", "display_name": "Máscara de superhéroe", "rarity": "Legendary",
		"glyph": "MS", "kind": "spiders",
		"description": "Tus bajas liberan arañas venenosas que cazan a otros enemigos",
	},
	{
		"id": "electric_belt", "display_name": "Cinturón eléctrico", "rarity": "Legendary",
		"glyph": "CL", "kind": "shock_dash",
		"description": "Al derrapar, un rayo salta entre 4 enemigos (uno más por copia)",
	},
	{
		"id": "saiyan_blood", "display_name": "Sangre sayayin", "rarity": "Legendary",
		"glyph": "SS", "kind": "saiyan",
		"description": "Cada 40 bajas te envuelve un aura: daño, velocidad de ataque y velocidad",
	},
	{
		"id": "zenkai", "display_name": "Zenkai", "rarity": "Legendary",
		"glyph": "ZK", "kind": "zenkai",
		"description": "Sobrevivir por debajo del 10% de HP sube todo un 8% para siempre",
	},
	{
		"id": "cosmic_worm", "display_name": "Gusano cósmico", "rarity": "Legendary",
		"glyph": "GC", "kind": "hook",
		"description": "Los portales se recargan 25% más rápido por copia",
	},
]

## Índice id -> fila, construido al primer uso (ver CatalogIndex):
## PlayerStats.recompute() resuelve una fila por objeto llevado en cada
## cambio de stats.
static var _by_id: Dictionary[String, Dictionary] = {}
## Índice kind -> ids, construido al primer uso: ItemBag pregunta en cada
## frame de física.
static var _ids_by_kind: Dictionary[String, PackedStringArray] = {}


static func by_id(item_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(ITEM_LIBRARY)
	return _by_id.get(item_id, {})


static func ids_of_rarity(rarity_name: String) -> Array[String]:
	return CatalogIndex.values_where(ITEM_LIBRARY, "rarity", rarity_name)


## Cada id de objeto con el `kind` de comportamiento dado. ItemBag cuenta
## copias por tipo y no por id fijo, para que renombrar una fila no apague su
## comportamiento mientras el objeto sigue en el HUD.
static func ids_of_kind(kind: String) -> PackedStringArray:
	if not _ids_by_kind.has(kind):
		var ids := PackedStringArray()
		for item_id: String in CatalogIndex.values_where(ITEM_LIBRARY, "kind", kind):
			ids.append(item_id)
		_ids_by_kind[kind] = ids
	return _ids_by_kind[kind]


## Un id al azar de la rareza dada; una rareza sin objetos baja un escalón
## por vez, así un cofre siempre paga algo.
static func roll_id(rarity_name: String) -> String:
	var index := UpgradePool.rarity_index(rarity_name)
	while index >= 0:
		var ids := ids_of_rarity(String(UpgradePool.RARITIES[index].name))
		if not ids.is_empty():
			return ids.pick_random()
		index -= 1
	return ""


static func rarity_color(rarity_name: String) -> Color:
	return UpgradePool.RARITIES[UpgradePool.rarity_index(rarity_name)].color
