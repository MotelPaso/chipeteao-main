class_name ItemCatalog
extends RefCounted
## Static catalog of run items (iteration 40): the loot chests pay out.
## Items are independent of weapons and tomes — a raider can hold any
## number of copies of any item — and every item has a FIXED rarity (the
## chest's rarity decides which pool it rolls from; luck tilts chest
## rarity, never the item itself). Data-driven like every other catalog:
## a new item is one row here (plus an ItemBag branch only for a new
## behavioral `kind`).
## Row fields:
##   id:       identifier (English, keys SaveData counters) — never shown.
##   display_name/description: the HUD/announce text, in player language.
##   rarity:   "Common" | "Rare" | "Epic" | "Legendary" (UpgradePool names).
##             An IDENTIFIER, not display text — screens translate it with
##             UpgradePool.rarity_display().
##   glyph:    1-2 letters drawn on the HUD slot while there is no sprite.
##             Initials of the DISPLAYED name, so the tile and the tooltip
##             agree ("Piedra de afilar" -> "PA").
##   icon:     OPTIONAL res:// texture path; when set the HUD shows it
##             instead of the glyph (drop the 2D sprites here later).
##   effects:  OPTIONAL [{stat, amount}] PlayerStats effects PER COPY,
##             applied through the same channel as tomes (recompute).
##   kind:     OPTIONAL behavior handled by ItemBag: "magnet",
##             "poison_on_hit", "titan", "spiders", or "hook" (a counter
##             other systems read — altars, portals). ItemBag resolves
##             behavior by kind, so a row's id can be renamed without
##             silently switching its behavior off.
## There is no "pet" kind any more (iteration 54). Pets became a single
## companion slot on the Player, filled only by the pet box and the animal
## trafficker, so a chest or a roulette can no longer hand one out — and
## must not be able to: a companion arriving unasked would throw away the
## one the player chose.

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
		# Iteration 48: the multi-jump item. PlayerStats caps the stat
		# (MAX_EXTRA_JUMPS), so extra copies past the cap are inert by
		# design rather than by accident.
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
		"id": "electric_belt", "display_name": "Cinturón eléctrico", "rarity": "Rare",
		"glyph": "CL", "kind": "shock_dash",
		"description": "Al derrapar, un rayo salta entre 3 enemigos (uno más por copia)",
	},
	{
		"id": "saiyan_blood", "display_name": "Sangre sayayin", "rarity": "Epic",
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

## Lazily built id -> row index (see CatalogIndex): PlayerStats.recompute()
## resolves one row per carried item on every stat change.
static var _by_id: Dictionary[String, Dictionary] = {}
## Lazily built kind -> ids index: ItemBag asks per physics frame.
static var _ids_by_kind: Dictionary[String, PackedStringArray] = {}


static func by_id(item_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(ITEM_LIBRARY)
	return _by_id.get(item_id, {})


static func ids_of_rarity(rarity_name: String) -> Array[String]:
	return CatalogIndex.values_where(ITEM_LIBRARY, "rarity", rarity_name)


## Every item id with the given behavioral `kind`. ItemBag counts copies by
## kind instead of by hardcoded id, so renaming a row cannot quietly turn
## its behavior off while the item still shows in the HUD.
static func ids_of_kind(kind: String) -> PackedStringArray:
	if not _ids_by_kind.has(kind):
		var ids := PackedStringArray()
		for item_id: String in CatalogIndex.values_where(ITEM_LIBRARY, "kind", kind):
			ids.append(item_id)
		_ids_by_kind[kind] = ids
	return _ids_by_kind[kind]


## A random item id of the given rarity; a rarity with no items falls
## back one tier at a time, so a chest always pays something.
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
