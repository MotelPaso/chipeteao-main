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
##   text_values: OPCIONAL, campos que llenan los %d de la descripción (ver
##             RowText): el número del texto es el del campo, nunca una copia.
##   Números del comportamiento: cada objeto con `kind` lleva sus propios
##             campos (ver cada fila); los lee ItemBag (o PlayerStats en
##             Zenkai). Los de Sangre de demonio, Llave maestra y Gusano
##             cósmico los aplican los santuarios (ver cada fila).
## Llave interna (la lee el código; cambiarla rompe algo):
##   id:       identificador en inglés, nunca se muestra; nombra los
##             contadores de SaveData. Los santuarios todavía buscan por id a
##             demon_blood, master_key y cosmic_worm: no los renombres.
##   rarity:   "Common" | "Rare" | "Epic" | "Legendary" (nombres de
##             UpgradePool); la pantalla lo traduce con
##             UpgradePool.rarity_display().
##   kind:     OPCIONAL, comportamiento: "magnet", "poison_on_hit", "titan",
##             "spiders", "shock_dash", "saiyan", "zenkai" (los maneja
##             ItemBag) y "demonic_boost", "charge_boost", "portal_recharge"
##             (contadores que leen los santuarios). Un kind por fila: el
##             comportamiento se busca por kind, no por id.
## No hay kind "pet": la mascota es un espacio único del Player que solo
## llenan la caja de mascota y el traficante, así que un cofre o la ruleta
## nunca pueden repartir una (tirarían la que el jugador eligió).

const ITEM_LIBRARY: Array[Dictionary] = [
	# --- Common ---------------------------------------------------------
	{
		"id": "whetstone", "display_name": "Piedra de afilar", "rarity": "Common",
		"glyph": "PA", "description": "Todo el daño +%d%% por copia", "text_values": ["amount"],
		"effects": [{"stat": "damage", "amount": 8.0}],
	},
	{
		"id": "iron_rations", "display_name": "Raciones de hierro", "rarity": "Common",
		"glyph": "RH", "description": "HP máx. +%d por copia", "text_values": ["amount"],
		"effects": [{"stat": "max_hp", "amount": 15.0}],
	},
	{
		"id": "lucky_coin", "display_name": "Moneda de la suerte", "rarity": "Common",
		"glyph": "MO", "description": "Suerte +%d por copia", "text_values": ["amount"],
		"effects": [{"stat": "luck", "amount": 8.0}],
	},
	{
		"id": "swift_boots", "display_name": "Botas veloces", "rarity": "Common",
		"glyph": "BV", "description": "Velocidad de movimiento +%d%% por copia",
		"text_values": ["amount"],
		"effects": [{"stat": "move_speed", "amount": 6.0}],
	},
	# --- Rare -----------------------------------------------------------
	{
		# PlayerStats pone techo a los saltos (MAX_EXTRA_JUMPS): las copias
		# por encima del techo no hacen nada, a propósito.
		"id": "spring_boots", "display_name": "Botas de resorte", "rarity": "Rare",
		"glyph": "RS", "description": "+%d salto en el aire por copia", "text_values": ["amount"],
		"effects": [{"stat": "jumps", "amount": 1.0}],
	},
	{
		"id": "magnet", "display_name": "Imán", "rarity": "Rare",
		"glyph": "IM", "kind": "magnet",
		"description": "Cada tanto atrae todas las gemas de XP del mapa; cada copia lo hace antes y suma +%d%% de XP",
		"text_values": ["amount"],
		"effects": [{"stat": "xp_gain", "amount": 10.0}],
		# Segundos entre tirones con un imán, y el multiplicador de ese
		# tiempo por cada copia extra.
		"pull_interval": 24.0, "interval_per_extra_copy": 0.8,
	},
	{
		"id": "fart_bag", "display_name": "Bolsa de pedos", "rarity": "Rare",
		"glyph": "BP", "kind": "poison_on_hit",
		"description": "Los golpes de arma envenenan; más copias = veneno más fuerte, y la duración de efectos lo alarga",
		# Daño de veneno por segundo por copia, y duración base en segundos
		# (se multiplica por la stat de duración).
		"poison_dps_per_copy": 3.0, "poison_duration": 3.0,
	},
	{
		"id": "keen_eye", "display_name": "Ojo agudo", "rarity": "Rare",
		"glyph": "OA", "description": "Prob. de crítico +%d%% por copia", "text_values": ["amount"],
		"effects": [{"stat": "crit_chance", "amount": 5.0}],
	},
	# --- Epic -----------------------------------------------------------
	{
		"id": "titan_blood", "display_name": "Sangre de titán", "rarity": "Epic",
		"glyph": "ST", "kind": "titan",
		"description": "Creces un %d%% y tus ataques cubren +%d%% de área por copia",
		"text_values": ["growth_percent", "amount"],
		"effects": [{"stat": "area", "amount": 8.0}],
		# Crecimiento del sello por copia (%) y escala máxima (el brazo de
		# cámara deja de funcionar si el sello crece sin techo).
		"growth_percent": 8.0, "max_scale": 2.2,
	},
	{
		"id": "demon_blood", "display_name": "Sangre de demonio", "rarity": "Epic",
		"glyph": "SD", "kind": "demonic_boost",
		"description": "Los altares demoníacos dan +%d%% más por copia",
		"text_values": ["boost_percent"],
		# Lo aplica curse_shrine.gd (demon_blood_per_copy = 0.25): mantén los
		# dos iguales hasta que el santuario lo lea de aquí.
		"boost_percent": 25.0,
	},
	{
		"id": "master_key", "display_name": "Llave maestra", "rarity": "Epic",
		"glyph": "LM", "kind": "charge_boost",
		"description": "Los altares de carga se llenan %d%% más rápido y dan +%d%% más por copia",
		"text_values": ["charge_speed_percent", "boon_percent"],
		# Lo aplica charge_shrine.gd (key_speed_per_copy y key_boon_per_copy
		# = 0.2): mantén los dos iguales hasta que el santuario lo lea de aquí.
		"charge_speed_percent": 20.0, "boon_percent": 20.0,
	},
	# --- Legendary ------------------------------------------------------
	{
		"id": "superhero_mask", "display_name": "Máscara de superhéroe", "rarity": "Legendary",
		"glyph": "MS", "kind": "spiders",
		"description": "Tus bajas liberan arañas venenosas que cazan a otros enemigos",
		# Arañas por baja por copia, alcance de vuelo (m), su veneno (daño
		# por segundo y segundos) y su color. max_spiders_per_frame es un
		# techo de rendimiento: un arma de área puede matar una docena de
		# cuerpos de un golpe.
		"spiders_per_copy": 2, "spider_range": 16.0,
		"spider_poison_dps": 4.0, "spider_poison_duration": 2.5,
		"spider_color": Color(0.55, 0.2, 0.75), "max_spiders_per_frame": 12,
	},
	{
		"id": "electric_belt", "display_name": "Cinturón eléctrico", "rarity": "Legendary",
		"glyph": "CL", "kind": "shock_dash",
		# El 4 sale de BeltBolt (belt_bolt.gd): el primer blanco más
		# base_bounces (2) más 1 por la copia. Mantén el texto igual a eso.
		"description": "Al derrapar, un rayo salta entre 4 enemigos (uno más por copia)",
	},
	{
		"id": "saiyan_blood", "display_name": "Sangre sayayin", "rarity": "Legendary",
		"glyph": "SS", "kind": "saiyan",
		"description": "Cada %d bajas te envuelve un aura: daño, velocidad de ataque y velocidad",
		"text_values": ["kills_per_aura"],
		# Bajas por aura con una copia; cada copia extra multiplica la
		# cuenta por kills_scale_per_extra_copy, sin bajar de kills_floor
		# (si no, el aura sería permanente).
		"kills_per_aura": 40, "kills_scale_per_extra_copy": 0.85, "kills_floor": 15,
		# Segundos del aura y sus bonos por copia, en %: daño, velocidad de
		# ataque y velocidad de movimiento. aura_color tiñe la cáscara.
		"aura_duration": 12.0, "aura_damage": 40.0, "aura_attack_speed": 25.0,
		"aura_move_speed": 20.0, "aura_color": Color(1.0, 0.85, 0.25),
	},
	{
		"id": "zenkai", "display_name": "Zenkai", "rarity": "Legendary",
		"glyph": "ZK", "kind": "zenkai",
		"description": "Sobrevivir por debajo del %d%% de HP sube todo un %d%% para siempre",
		"text_values": ["arm_below_hp_percent", "percent_per_stack"],
		# Se arma bajo arm_below_hp_percent del HP máx. y se dispara al volver
		# sobre trigger_above_hp_percent (dos umbrales: hay que salir de
		# verdad). Cada disparo suma una acumulación por copia, y cada
		# acumulación sube percent_per_stack a cada stat de `stats` (en
		# max_hp y luck son puntos fijos, no %).
		"arm_below_hp_percent": 10.0, "trigger_above_hp_percent": 50.0,
		"percent_per_stack": 8.0,
		"stats": ["damage", "cooldown", "area", "move_speed", "crit_chance", "max_hp", "luck"],
	},
	{
		"id": "cosmic_worm", "display_name": "Gusano cósmico", "rarity": "Legendary",
		"glyph": "GC", "kind": "portal_recharge",
		"description": "Los portales se recargan %d%% más rápido por copia",
		"text_values": ["recharge_percent"],
		# Lo aplica portal_shrine.gd (worm_cooldown_per_copy = 0.25): mantén
		# los dos iguales hasta que el portal lo lea de aquí.
		"recharge_percent": 25.0,
	},
]

## Índice id -> fila con la descripción ya armada (ver RowText), construido
## al primer uso (ver CatalogIndex): PlayerStats.recompute() resuelve una
## fila por objeto llevado en cada cambio de stats.
static var _by_id: Dictionary[String, Dictionary] = {}
## Índice kind -> ids, construido al primer uso: ItemBag pregunta en cada
## frame de física.
static var _ids_by_kind: Dictionary[String, PackedStringArray] = {}


static func by_id(item_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(RowText.render_all(ITEM_LIBRARY))
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


## La fila del objeto con este `kind` de comportamiento (hay una por tipo),
## o vacía si no existe. ItemBag y PlayerStats leen de aquí los números de
## cada comportamiento.
static func kind_row(kind: String) -> Dictionary:
	var ids := ids_of_kind(kind)
	return by_id(ids[0]) if not ids.is_empty() else {}


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
