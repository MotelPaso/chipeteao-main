class_name UpgradePool
extends RefCounted
## Pool de mejoras de subida de nivel, con rareza ponderada. Cada elección de
## NIVEL sortea UN lado del pool, nunca una mezcla: armas (cartas de stats de
## las armas que se tienen + cartas new_weapon) o tomos/stats (cartas de tomo +
## GENERIC_POOL). roll_side() elige el lado, ponderado por cuántas entradas
## tiene cada uno, y nunca devuelve uno vacío; la UI de cartas lo nombra en el
## título. Las elecciones extra (cofres, altares) no pasan lado y mezclan todo.
## El pool se arma de nuevo en cada tirada con:
##   - GENERIC_POOL: ajustes de player/health/run_state, siempre disponibles.
##   - Cartas de tomo (Tome.TOME_LIBRARY): el siguiente stack de cada tomo que
##     el jugador aún puede tomar; aplicarla suma un stack en PlayerStats.
##   - Cartas de stats por cada arma QUE SE TIENE (daño, velocidad de ataque,
##     alcance, más los extras declarados en WEAPON_LIBRARY), así cada arma
##     sigue escalando.
##   - Cartas "new_weapon" para las armas de la biblioteca que el jugador NO
##     tiene, ocultas del todo al llegar a su tope max_weapons.
## Campos de una entrada:
##   kind: "stat" (por defecto, se omite), "new_weapon" o "tome".
##   target: "player" | "health" | "run_state" | "weapon/<NodeName>" (las armas
##       se buscan bajo el montaje Weapons del jugador).
##   op: "mul_percent" (amount = +/- porcentaje) | "add" (cantidad plana).
##   effects: forma OPCIONAL de varios stats: una lista de
##       {property, op, amount} que se aplica junta sobre el mismo target, en
##       lugar del trío property/op/amount. La descripción lleva un "%d" por
##       efecto, en orden.
##   description: "%d" que se llena con la cantidad escalada por la rareza; las
##       descripciones de new_weapon se muestran tal cual.
##   offer_weight: probabilidad relativa de aparecer en una oferta (1.0 por
##       defecto).
##   rarity: fija la rareza de la carta por nombre en vez de sortearla.
## La rareza multiplica la cantidad base (una carta Epic de +25% sale con
## +50%), así un arma o tomo nuevo solo agrega entradas y la UI no cambia. La
## suerte del jugador (PlayerStats) inclina los pesos de rareza: mueve una
## fracción del peso de Common hacia las rarezas superiores.
##
## Texto que ve el jugador: display_name, flavor, title y description. id,
## node_name, scene y los nombres de rareza son identificadores en inglés.

## Todas las armas equipables. Las cartas new_weapon y las cartas de stats
## por arma se generan desde aquí, así un arma nueva es una fila nueva.
## Se puede cambiar libremente: display_name, glyph, flavor y los textos y
## números de extra_entries.
## Llaves internas, NUNCA las cambies: id (contadores used_weapon_<id> y
## evo_<id>, recetas de EvolutionCatalog) y node_name (nombre del nodo del arma
## en el montaje Weapons; las cartas lo nombran como "weapon/<node_name>", las
## filas de personaje como weapon_node_name, y debe ser el nombre del archivo
## de su escena porque las mascotas resuelven su arma así). scene debe existir.
## `glyph` es la sigla de dos letras que dibuja la tira de armas del HUD
## mientras no hay ícono (el mismo campo que llevan las filas de ItemCatalog).
## Se DECLARA, no se deriva de display_name: casi todos los nombres en español
## son «Sustantivo de Complemento» y las iniciales chocan («Vara de brasas» y
## «Vial de sangre» darían «VD»). No debe repetirse en WEAPON_LIBRARY,
## EvolutionCatalog.EVOLUTION_LIBRARY, Tome.TOME_LIBRARY ni
## ItemCatalog.ITEM_LIBRARY: la tira mezcla las cuatro.
const WEAPON_LIBRARY: Array[Dictionary] = [
	{
		"id": "shortsword", "display_name": "Espada corta", "glyph": "EC",
		"node_name": "Shortsword", "scene": "res://scenes/weapons/Shortsword.tscn",
		"flavor": "barre un arco cuerpo a cuerpo entre los enemigos cercanos",
	},
	{
		"id": "dart_pistol", "display_name": "Pistola de dardos", "glyph": "PD",
		"node_name": "DartPistol", "scene": "res://scenes/weapons/DartPistol.tscn",
		"flavor": "castiga al enemigo más cercano con dardos rápidos que persiguen",
		"extra_entries": [
			{
				"id": "dart_pistol_projectiles", "title": "Dardos divididos",
				"description": "La Pistola de dardos dispara %d dardo(s) más",
				"target": "weapon/DartPistol", "property": "projectile_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "ember_wand", "display_name": "Vara de brasas", "glyph": "VB",
		"node_name": "EmberWand", "scene": "res://scenes/weapons/EmberWand.tscn",
		"flavor": "detona estallidos de fuego sobre grupos lejanos",
	},
	{
		"id": "hunting_bow", "display_name": "Arco de caza", "glyph": "AR",
		"node_name": "HuntingBow", "scene": "res://scenes/weapons/HuntingBow.tscn",
		"flavor": "suelta flechas rectas que ensartan filas enteras",
		"extra_entries": [
			{
				"id": "hunting_bow_pierce", "title": "Puntas con púas",
				"description": "Las flechas del Arco de caza perforan %d enemigos más",
				"target": "weapon/HuntingBow", "property": "pierce_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "thorn_whip", "display_name": "Látigo de espinas", "glyph": "LE",
		"node_name": "ThornWhip", "scene": "res://scenes/weapons/ThornWhip.tscn",
		"flavor": "traza una línea de zarzas que engancha y ralentiza",
		"extra_entries": [
			{
				"id": "thorn_whip_slow", "title": "Espinas aferradas",
				"description": "La ralentización del Látigo de espinas es %d%% más fuerte",
				"target": "weapon/ThornWhip", "property": "slow_percent",
				"op": "add", "amount": 8.0,
			},
		],
	},
	{
		"id": "boomerang", "display_name": "Bumerán", "glyph": "BM",
		"node_name": "Boomerang", "scene": "res://scenes/weapons/Boomerang.tscn",
		"flavor": "lanza una hoja que corta al ir y al volver",
		"extra_entries": [
			{
				"id": "boomerang_travel", "title": "Vuelo lejano",
				"description": "Distancia de vuelo del Bumerán +%d%%",
				"target": "weapon/Boomerang", "property": "travel_scale",
				"op": "mul_percent", "amount": 20.0,
			},
		],
	},
	{
		"id": "twin_daggers", "display_name": "Dagas gemelas", "glyph": "DG",
		"node_name": "TwinDaggers", "scene": "res://scenes/weapons/TwinDaggers.tscn",
		"flavor": "destroza al enemigo más cercano con estocadas rapidísimas",
		"extra_entries": [
			{
				# Velocidad de ataque en su propia perilla (cooldown_scale): se
				# acumula con «Mano rápida» sin tocar el cooldown base.
				"id": "twin_daggers_flurry", "title": "Ráfaga",
				"description": "Velocidad de ataque de las Dagas gemelas +%d%%",
				"target": "weapon/TwinDaggers", "property": "cooldown_scale",
				"op": "mul_percent", "amount": -15.0,
			},
		],
	},
	{
		"id": "spirit_orbs", "display_name": "Orbes espirituales", "glyph": "OE",
		"node_name": "SpiritOrbs", "scene": "res://scenes/weapons/SpiritOrbs.tscn",
		"flavor": "espíritus en órbita que queman todo lo que rozan",
		"extra_entries": [
			{
				"id": "spirit_orbs_count", "title": "Otro espíritu",
				"description": "Los Orbes espirituales suman %d orbe(s) más",
				"target": "weapon/SpiritOrbs", "property": "projectile_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "necro_staff", "display_name": "Báculo de nigromante", "glyph": "BN",
		"node_name": "NecroStaff", "scene": "res://scenes/weapons/NecroStaff.tscn",
		"flavor": "lo que mata se levanta de tu lado",
		"extra_entries": [
			{
				"id": "necro_staff_duration", "title": "Posesión más larga",
				"description": "Tus siervos duran %d%% más",
				"target": "weapon/NecroStaff", "property": "possess_duration",
				"op": "mul_percent", "amount": 25.0,
			},
			{
				"id": "necro_staff_cap", "title": "Más siervos",
				"description": "Puedes tener %d siervos más a la vez",
				"target": "weapon/NecroStaff", "property": "max_possessed",
				"op": "add", "amount": 3.0,
			},
		],
	},
	{
		"id": "storm_rod", "display_name": "Pararrayos", "glyph": "PY",
		"node_name": "StormRod", "scene": "res://scenes/weapons/StormRod.tscn",
		"flavor": "rayos que se bifurcan entre enemigos apretados",
		"extra_entries": [
			{
				"id": "storm_rod_chain", "title": "Cielo bifurcado",
				"description": "El Pararrayos encadena a %d enemigos más",
				"target": "weapon/StormRod", "property": "chain_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "blood_vial", "display_name": "Vial de sangre", "glyph": "VS",
		"node_name": "BloodVial", "scene": "res://scenes/weapons/BloodVial.tscn",
		"flavor": "arroja frascos que encharcan sangre bajo los grupos más densos",
		"extra_entries": [
			{
				# Un pulso extra = un tick_interval más de vida del charco.
				"id": "blood_vial_coagulate", "title": "Coagular",
				"description": "Los charcos del Vial de sangre pulsan %d vez(ces) más",
				"target": "weapon/BloodVial", "property": "pool_ticks",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "slime_trail", "display_name": "Rastro de baba", "glyph": "RB",
		"node_name": "SlimeTrail", "scene": "res://scenes/weapons/SlimeTrail.tscn",
		"flavor": "deja baba cáustica por donde camines",
		"extra_entries": [
			{
				"id": "slime_trail_life", "title": "Baba más espesa",
				"description": "Los charcos del Rastro de baba duran %d%% más",
				"target": "weapon/SlimeTrail", "property": "puddle_life",
				"op": "mul_percent", "amount": 25.0,
			},
		],
	},
	{
		"id": "aura", "display_name": "Aura", "glyph": "AU",
		"node_name": "Aura", "scene": "res://scenes/weapons/Aura.tscn",
		"flavor": "un anillo de luz que quema todo a tu alrededor",
	},
	{
		"id": "stench", "display_name": "Hedor", "glyph": "HE",
		"node_name": "Stench", "scene": "res://scenes/weapons/Stench.tscn",
		"flavor": "pulsos flatulentos que envenenan y ralentizan a la jauría",
		"extra_entries": [
			{
				"id": "stench_linger", "title": "Hedor más rancio",
				"description": "El veneno del Hedor dura %d%% más",
				"target": "weapon/Stench", "property": "poison_duration",
				"op": "mul_percent", "amount": 30.0,
			},
		],
	},
	{
		"id": "kamehameha", "display_name": "Kamehameha", "glyph": "KH",
		"node_name": "Kamehameha", "scene": "res://scenes/weapons/Kamehameha.tscn",
		"flavor": "un rayo devastador que borra un carril entero",
		"extra_entries": [
			{
				"id": "kamehameha_length", "title": "Rayo más largo",
				"description": "El rayo del Kamehameha llega %d%% más lejos",
				"target": "weapon/Kamehameha", "property": "beam_length",
				"op": "mul_percent", "amount": 25.0,
			},
		],
	},
]

## Los dos lados del pool. Son identificadores, no texto: SIDE_LABELS los
## traduce para el título de la carta.
const SIDE_WEAPONS: String = "weapons"
const SIDE_TOMES: String = "tomes"
const SIDE_LABELS: Dictionary[String, String] = {
	SIDE_WEAPONS: "Armas", SIDE_TOMES: "Tomos"}

## Tope de armas de respaldo, SOLO para un nodo jugador sin max_weapons. El
## tope real es el export Player.max_weapons.
const DEFAULT_MAX_WEAPONS: int = 5
## Tope de tomos DISTINTOS de respaldo, SOLO para un nodo jugador sin
## max_tomes. El tope real es el export Player.max_tomes.
const DEFAULT_MAX_TOMES: int = 5
## Peso de oferta de las cartas de arma de dos stats (algo menos que las de
## un stat).
const MULTI_STAT_OFFER_WEIGHT: float = 0.7
## Peso de oferta de las cartas de arma nueva (menos que las de stats).
const NEW_WEAPON_OFFER_WEIGHT: float = 0.6
## Peso de oferta de cada carta de tomo, algo bajo para que los tomos no
## llenen el pool.
const TOME_OFFER_WEIGHT: float = 0.8
## Pendiente de la suerte en cero: cada punto de suerte mueve esta fracción
## del peso de Common hacia arriba. La curva de _rarity_weights se aleja de
## esta pendiente al crecer la suerte, pero nunca se aplana.
const LUCK_TILT_PER_POINT: float = 0.01
## Asíntota de esa curva: como máximo se mueve esta fracción del peso de
## Common. Se acerca sin llegar nunca, así cada punto de suerte extra aporta.
const MAX_LUCK_TILT: float = 0.5

## Escalones de balance de las cartas que genera cada arma, en porcentaje y
## a potencia Common (la rareza sorteada los escala).
const WEAPON_DAMAGE_STEP: float = 25.0
const WEAPON_COOLDOWN_STEP: float = -10.0
const WEAPON_RANGE_STEP: float = 15.0
## Cartas de dos stats: x es el escalón del primer efecto, y el del segundo.
const TEMPERED_STEPS: Vector2 = Vector2(15.0, 10.0)
const RHYTHM_STEPS: Vector2 = Vector2(-6.0, 10.0)

## Cartas de stats sin tomo equivalente. Los stats que tienen tomo
## (velocidad -> Tomo de Ligereza) viven solo en el catálogo de tomos.
const GENERIC_POOL: Array[Dictionary] = [
	{
		# Sube el máximo y cura SOLO lo ganado (ver _apply_property).
		"id": "max_hp", "title": "Corazón recio",
		"description": "HP máx. +%d (te cura lo que ganas)",
		"target": "health", "property": "max_hp",
		"op": "add", "amount": 20.0,
	},
	{
		"id": "pickup_radius", "title": "Aura de codicia",
		"description": "Radio de recolección +%d%%",
		"target": "run_state", "property": "pickup_radius_multiplier",
		"op": "mul_percent", "amount": 25.0,
	},
]

## Rarezas. `name` es un IDENTIFICADOR, no texto: llavea los precios de cofre
## (RunState.CHEST_BASE_PRICES), el campo `rarity` de cada fila de ItemCatalog
## y los pisos min_rarity que pasan cofres, altares y el director del mundo.
## Queda en inglés; las pantallas lo muestran con rarity_display().
## weight: peso relativo del sorteo. potency: multiplicador de la cantidad de
## la carta. color: color de la rareza en pantalla.
const RARITIES: Array[Dictionary] = [
	{"name": "Common", "color": Color(0.62, 0.65, 0.68), "weight": 60.0, "potency": 1.0},
	{"name": "Rare", "color": Color(0.3, 0.55, 1.0), "weight": 25.0, "potency": 1.5},
	{"name": "Epic", "color": Color(0.68, 0.32, 0.95), "weight": 12.0, "potency": 2.0},
	{"name": "Legendary", "color": Color(1.0, 0.78, 0.2), "weight": 3.0, "potency": 3.0},
]

## Nombre que ve el jugador por cada id de rareza. Es el único lugar donde se
## traduce una rareza.
const RARITY_DISPLAY: Dictionary[String, String] = {
	"Common": "Común",
	"Rare": "Raro",
	"Epic": "Épico",
	"Legendary": "Legendario",
}

## Índice node_name -> fila de WEAPON_LIBRARY armado al primer uso (ver
## CatalogIndex).
static var _weapons_by_node: Dictionary[String, Dictionary] = {}


## Traduce un id de rareza para mostrarlo. Toda pantalla que imprime una
## rareza pasa por aquí; nada compara contra el resultado.
static func rarity_display(rarity_name: String) -> String:
	return RARITY_DISPLAY.get(rarity_name, rarity_name)


## Sortea `count` mejoras distintas del pool válido para el equipo de este
## jugador, cada una con su propia rareza ponderada. Devuelve diccionarios
## listos para mostrar: entry, rarity, amount, title, description. Altares y
## cofres pasan luck_bonus (suerte temporal sobre la de PlayerStats) y/o
## min_rarity (nombre de la rareza mínima, que sube también las fijas). `side`
## limita el pool a SIDE_WEAPONS o SIDE_TOMES; "" (por defecto, lo que pasan
## las elecciones extra) mezcla.
static func roll_offer(player: Node, count: int = 3, luck_bonus: float = 0.0,
		min_rarity: String = "", side: String = "") -> Array[Dictionary]:
	var offer: Array[Dictionary] = []
	var stats := PlayerStats.find_in(player)
	var luck := (stats.luck if stats != null else 0.0) + luck_bonus
	var floor_index := rarity_index(min_rarity)
	for entry: Dictionary in _weighted_pick(build_pool(player, side), count):
		var rarity := _rarity_for(entry, luck, floor_index)
		if String(entry.get("kind", "stat")) == "new_weapon":
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": 0.0,
				"title": entry.title,
				"description": entry.description,
			})
			continue
		if entry.has("effects"):
			# Carta de varios stats: una cantidad escalada por efecto, en orden.
			var amounts: Array[float] = []
			var shown: Array[int] = []
			for effect: Dictionary in entry.effects as Array:
				var scaled: float = roundf(float(effect.amount) * float(rarity.potency))
				amounts.append(scaled)
				shown.append(absi(roundi(scaled)))
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": amounts[0] if not amounts.is_empty() else 0.0,
				"amounts": amounts,
				"title": entry.title,
				"description": String(entry.description) % shown,
			})
			continue
		var amount: float = roundf(float(entry.amount) * float(rarity.potency))
		if bool(entry.get("gamble", false)):
			# Tomo del Azar: la cantidad de boons sale del rango de rareza, no
			# de amount x potencia. La carta y PlayerStats leen la misma
			# función, así la carta nunca promete menos boons de los que salen.
			amount = float(Tome.gamble_boon_count(float(rarity.potency)))
		offer.append({
			"entry": entry,
			"rarity": rarity,
			"amount": amount,
			"title": entry.title,
			"description": entry.description % absi(roundi(amount)),
		})
	return offer


## El pool del que el jugador puede sortear ahora. `side` lo limita a una
## mitad (SIDE_WEAPONS / SIDE_TOMES); "" devuelve las dos, como quieren las
## elecciones extra.
static func build_pool(player: Node, side: String = "") -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if side != SIDE_WEAPONS:
		pool.append_array(_tome_side(player))
	if side != SIDE_TOMES:
		pool.append_array(_weapon_side(player))
	return pool


## Mitad de tomos/stats: las cartas genéricas, siempre disponibles, más el
## siguiente stack de cada tomo que el jugador aún puede tomar.
static func _tome_side(player: Node) -> Array[Dictionary]:
	var pool: Array[Dictionary] = GENERIC_POOL.duplicate()
	if player == null:
		return pool
	pool.append_array(_tome_entries(player))
	return pool


## Mitad de armas: cartas de stats por cada arma que se tiene más cartas
## new_weapon para las que no (ninguna al llegar al tope de armas).
static func _weapon_side(player: Node) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if player == null:
		return pool
	var mount := player.get_node_or_null("Weapons")
	if mount == null:
		return pool
	var owned := 0
	for weapon: Dictionary in WEAPON_LIBRARY:
		if mount.has_node(String(weapon.node_name)):
			owned += 1
			pool.append_array(_entries_for_weapon(weapon))
	if owned < _max_weapons(player):
		for weapon: Dictionary in WEAPON_LIBRARY:
			if not mount.has_node(String(weapon.node_name)):
				pool.append(_new_weapon_entry(weapon))
	return pool


## Qué lado ofrece una elección de nivel: al azar, ponderado por cuántas
## entradas tiene cada lado ahora. Nunca devuelve un lado vacío: una elección
## sin nada que mostrar trabaría el árbol pausado. Arma las dos mitades para
## contarlas (corre una vez por subida de nivel), así las reglas de topes
## viven solo en _tome_side / _weapon_side.
static func roll_side(player: Node) -> String:
	var weapons := _weapon_side(player).size()
	var tomes := _tome_side(player).size()
	if weapons <= 0:
		return SIDE_TOMES
	if tomes <= 0:
		return SIDE_WEAPONS
	return SIDE_WEAPONS if randf() * float(weapons + tomes) < float(weapons) \
			else SIDE_TOMES


## Nombre de un lado para el título del selector de cartas.
static func side_label(side: String) -> String:
	return SIDE_LABELS.get(side, "")


## Aplica una oferta sorteada a los nodos vivos que cuelgan de `player`.
## Devuelve los boons que acaba de sortear un tomo de apuesta (Tomo del Azar),
## para que quien llama muestre lo que pagó; vacío para cualquier otra carta.
static func apply(offer: Dictionary, player: Node) -> Array[Dictionary]:
	var entry: Dictionary = offer.entry
	var rolled: Array[Dictionary] = []
	match String(entry.get("kind", "stat")):
		"new_weapon":
			_grant_weapon(entry, player)
			return rolled
		"tome":
			return _grant_tome(entry, offer, player)
	var target := _resolve_target(entry.target, player)
	if target == null:
		push_warning("UpgradePool: target '%s' not found for '%s'" % [entry.target, entry.id])
		return rolled
	if entry.has("effects"):
		var amounts: Array[float] = offer.get("amounts", [] as Array[float])
		var effects: Array = entry.effects
		for i in effects.size():
			var effect: Dictionary = effects[i]
			_apply_property(target, String(effect.property), String(effect.op),
					amounts[i] if i < amounts.size() else float(effect.amount), entry)
	else:
		_apply_property(target, String(entry.property), String(entry.op),
				float(offer.amount), entry)
	# Cada carta invertida en un arma es un nivel de arma; en cada umbral de
	# EvolutionCatalog evoluciona o asciende en el acto.
	if target is WeaponBase:
		var weapon := target as WeaponBase
		weapon.upgrade_level += 1
		EvolutionCatalog.try_advance_by_level(weapon, player)
	return rolled


## Un cambio de propiedad sobre un objetivo vivo. Subir max_hp de un Health
## también cura lo ganado (nunca una curación completa).
static func _apply_property(target: Object, property: String, op: String,
		amount: float, entry: Dictionary) -> void:
	# Object.get() devuelve null para una propiedad que no existe, y asignarlo
	# a un `float` tipado sería un error duro a mitad de carta, con el árbol
	# pausado. Una fila mal escrita debe quedar en advertencia y no congelar la
	# incursión (WeaponBase.evolve hace lo mismo).
	var raw: Variant = target.get(property)
	if raw == null:
		push_warning("UpgradePool: no property '%s' on target for '%s'"
				% [property, entry.get("id", "?")])
		return
	var current := float(raw)
	match op:
		"mul_percent":
			target.set(property, current * (1.0 + amount / 100.0))
		"add":
			target.set(property, current + amount)
		_:
			push_warning("UpgradePool: unknown op '%s' in '%s'" % [op, entry.id])
	if target is Health and property == "max_hp" and amount > 0.0:
		(target as Health).heal(amount)


## Cartas de stats que aporta cada arma que se tiene (mismo escalado para
## todas) más los extra_entries de su fila. Las descripciones genéricas no
## nombran el arma: la UI de cartas muestra una etiqueta con el arma en toda
## entrada cuyo `target` empieza con "weapon/" (la resuelve
## weapon_display_name()).
static func _entries_for_weapon(weapon: Dictionary) -> Array[Dictionary]:
	var target: String = "weapon/" + String(weapon.node_name)
	var entries: Array[Dictionary] = [
		{
			"id": String(weapon.id) + "_damage", "title": "Afilado",
			"description": "Aumenta el daño en un %d%%",
			"target": target, "property": "damage",
			"op": "mul_percent", "amount": WEAPON_DAMAGE_STEP,
		},
		{
			"id": String(weapon.id) + "_cooldown", "title": "Mano rápida",
			"description": "Aumenta la velocidad de ataque en un %d%%",
			"target": target, "property": "cooldown",
			"op": "mul_percent", "amount": WEAPON_COOLDOWN_STEP,
		},
		{
			"id": String(weapon.id) + "_range", "title": "Largo alcance",
			"description": "Aumenta el alcance en un %d%%",
			"target": target, "property": "attack_range",
			"op": "mul_percent", "amount": WEAPON_RANGE_STEP,
		},
		# Cartas de dos stats: un nivel, dos perillas.
		{
			"id": String(weapon.id) + "_tempered", "title": "Temple",
			"description": "Aumenta el daño en un %d%%\nAumenta el alcance en un %d%%",
			"target": target,
			"effects": [
				{"property": "damage", "op": "mul_percent", "amount": TEMPERED_STEPS.x},
				{"property": "attack_range", "op": "mul_percent", "amount": TEMPERED_STEPS.y},
			],
			"offer_weight": MULTI_STAT_OFFER_WEIGHT,
		},
		{
			"id": String(weapon.id) + "_rhythm", "title": "Ritmo de batalla",
			"description": "Aumenta la velocidad de ataque en un %d%%\nAumenta el daño en un %d%%",
			"target": target,
			"effects": [
				{"property": "cooldown", "op": "mul_percent", "amount": RHYTHM_STEPS.x},
				{"property": "damage", "op": "mul_percent", "amount": RHYTHM_STEPS.y},
			],
			"offer_weight": MULTI_STAT_OFFER_WEIGHT,
		},
	]
	for extra: Dictionary in weapon.get("extra_entries", [] as Array[Dictionary]):
		entries.append(extra)
	return entries


## Una carta por tomo disponible, que ofrece el SIGUIENTE stack (el título
## lleva el numeral, p. ej. «Tomo de Furia II»; Tome.stack_label lo arma para
## cualquier número). La potencia de la rareza sorteada escala las cantidades
## igual que en las cartas de stats.
static func _tome_entries(player: Node) -> Array[Dictionary]:
	var stats := PlayerStats.find_in(player)
	var entries: Array[Dictionary] = []
	# Tope de tomos distintos: con max_tomes tomos diferentes, solo se
	# ofrecen más stacks de esos.
	var owned_distinct := stats.distinct_tome_count() if stats != null else 0
	var at_cap := owned_distinct >= _player_cap(player, "max_tomes", DEFAULT_MAX_TOMES)
	for tome: Dictionary in Tome.TOME_LIBRARY:
		var tome_id := String(tome.id)
		var owned_stacks := stats.stack_count(tome_id) if stats != null else 0
		if at_cap and owned_stacks == 0:
			continue
		# Sin tope de stacks: solo se limita la cantidad de tomos DISTINTOS,
		# así un tomo favorito sigue creciendo toda la incursión.
		var next_stack := owned_stacks + 1
		var effects: Array = tome.effects
		var primary: Dictionary = effects[0]
		entries.append({
			"id": tome_id,
			"kind": "tome",
			"tome_id": tome_id,
			"title": Tome.display_title(tome, next_stack),
			"description": String(tome.description),
			# El efecto principal da el número que muestra la carta.
			"amount": float(primary.amount),
			# Los tomos de apuesta cuentan boons en su lugar (ver roll_offer).
			"gamble": bool(tome.get("gamble", false)),
			"offer_weight": TOME_OFFER_WEIGHT,
		})
	return entries


static func _new_weapon_entry(weapon: Dictionary) -> Dictionary:
	return {
		"id": "gain_" + String(weapon.id),
		"kind": "new_weapon",
		"title": String(weapon.display_name),
		"description": String(weapon.flavor),
		"scene": String(weapon.scene),
		"weapon_name": String(weapon.node_name),
		"weapon_id": String(weapon.id),
		"rarity": "Rare",
		"offer_weight": NEW_WEAPON_OFFER_WEIGHT,
	}


static func _grant_weapon(entry: Dictionary, player: Node) -> void:
	var mount := player.get_node_or_null("Weapons")
	if mount == null:
		push_warning("UpgradePool: no Weapons mount on player for '%s'" % entry.id)
		return
	# Las ofertas ya filtran las armas que se tienen, pero una tirada vieja en
	# cola podría llegar tarde.
	if mount.has_node(String(entry.weapon_name)):
		return
	var scene := load(String(entry.scene)) as PackedScene
	if scene == null:
		push_warning("UpgradePool: bad weapon scene '%s' in '%s'" % [entry.scene, entry.id])
		return
	var weapon := scene.instantiate() as Node3D
	weapon.name = String(entry.weapon_name)
	mount.add_child(weapon)
	# Colección: «llevó esta arma alguna vez» (se guarda al cerrar la
	# incursión, como todo contador).
	var weapon_id := String(entry.get("weapon_id", ""))
	if not weapon_id.is_empty():
		var save_data := autoload_node(&"SaveData")
		if save_data != null:
			save_data.bump("used_weapon_" + weapon_id)


## Un nodo autoload buscado por el árbol principal: las funciones estáticas
## no ven los nombres de autoload directamente y un harness `-s` no tiene
## autoloads, así que todo uso estático de un autoload en estos catálogos
## pasa por aquí y devuelve null en vez de caerse.
static func autoload_node(node_name: StringName) -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null(NodePath(node_name))


## Fila de WEAPON_LIBRARY con ese id, o vacío si no existe.
static func weapon_by_id(weapon_id: String) -> Dictionary:
	for row: Dictionary in WEAPON_LIBRARY:
		if String(row.id) == weapon_id:
			return row
	return {}


## Fila de WEAPON_LIBRARY para el nombre de un nodo del montaje, o vacío si
## no existe.
static func weapon_by_node(node_name: String) -> Dictionary:
	if _weapons_by_node.is_empty():
		_weapons_by_node = CatalogIndex.build(WEAPON_LIBRARY, "node_name")
	return _weapons_by_node.get(node_name, {})


## Id de WEAPON_LIBRARY para el nombre de un nodo del montaje ("" si no
## existe); con él se arman los contadores used_weapon_<id>.
static func weapon_id_for_node(node_name: String) -> String:
	return String(weapon_by_node(node_name).get("id", ""))


## Nombre del arma que ve el jugador para el nombre de un nodo del montaje,
## o el propio nombre del nodo si no existe. La tira del HUD y el cartel de
## evolución resuelven nombres por aquí.
static func weapon_display_name(node_name: String) -> String:
	return String(weapon_by_node(node_name).get("display_name", node_name))


## Suma un stack con la potencia de la rareza sorteada; PlayerStats
## recalcula todo desde cero, así lo mostrado coincide con lo aplicado.
## Devuelve los boons que sorteó un tomo de apuesta (vacío para los demás).
static func _grant_tome(entry: Dictionary, offer: Dictionary,
		player: Node) -> Array[Dictionary]:
	var stats := PlayerStats.find_in(player)
	if stats == null:
		push_warning("UpgradePool: no PlayerStats on player for '%s'" % entry.id)
		return [] as Array[Dictionary]
	var rarity: Dictionary = offer.rarity
	return stats.add_tome(String(entry.tome_id), float(rarity.potency))


static func _max_weapons(player: Node) -> int:
	return _player_cap(player, "max_weapons", DEFAULT_MAX_WEAPONS)


## Un tope exportado en el script del jugador, o el respaldo si no existe.
static func _player_cap(player: Node, property: String, fallback: int) -> int:
	if player == null:
		return fallback
	var value: Variant = player.get(property)
	return int(value) if value != null else fallback


static func _resolve_target(target_path: String, player: Node) -> Object:
	match target_path:
		"player":
			return player
		"health":
			return Health.find_in(player)
		"run_state":
			return autoload_node(&"RunState")
	if target_path.begins_with("weapon/"):
		var mount := player.get_node_or_null("Weapons")
		if mount != null:
			return mount.get_node_or_null(target_path.get_slice("/", 1))
	return null


## Elige hasta `count` entradas distintas, ponderadas por offer_weight.
static func _weighted_pick(entries: Array[Dictionary], count: int) -> Array[Dictionary]:
	var remaining := entries.duplicate()
	var picked: Array[Dictionary] = []
	while picked.size() < count and not remaining.is_empty():
		var total := 0.0
		for entry: Dictionary in remaining:
			total += float(entry.get("offer_weight", 1.0))
		var roll := randf() * total
		var chosen := remaining.size() - 1
		for i in remaining.size():
			roll -= float(remaining[i].get("offer_weight", 1.0))
			if roll <= 0.0:
				chosen = i
				break
		picked.append(remaining[chosen])
		remaining.remove_at(chosen)
	return picked


## Índice de rareza para un valor de potencia (Common 1.0 -> 0 ...
## Legendary 3.0 -> 3); para valores fuera de la tabla gana la más cercana.
static func potency_rank(potency: float) -> int:
	var best := 0
	var best_gap := INF
	for i: int in RARITIES.size():
		var gap := absf(float(RARITIES[i].potency) - potency)
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


## Índice de una rareza por nombre; un nombre desconocido o vacío da la
## rareza base (índice 0), que no pone piso.
static func rarity_index(rarity_name: String) -> int:
	for i: int in RARITIES.size():
		if String(RARITIES[i].name) == rarity_name:
			return i
	return 0


static func _rarity_for(entry: Dictionary, luck: float, floor_index: int = 0) -> Dictionary:
	var fixed_name: String = String(entry.get("rarity", ""))
	if not fixed_name.is_empty():
		for i: int in RARITIES.size():
			if String(RARITIES[i].name) == fixed_name:
				# El piso min_rarity de una elección extra también sube las
				# rarezas fijas: una elección «Epic o más» nunca muestra Rare.
				return RARITIES[maxi(i, floor_index)]
	return roll_rarity(luck, floor_index)


## Sortea una rareza, inclinada por la suerte y con piso en `floor_index`.
## Es pública porque los cofres sortean su propia rareza (chest.gd) y la
## curva de suerte debe tener una sola implementación.
static func roll_rarity(luck: float, floor_index: int = 0) -> Dictionary:
	var weights := _rarity_weights(luck)
	var total := 0.0
	for weight: float in weights:
		total += weight
	var pick := randf() * total
	var index := 0
	for i: int in RARITIES.size():
		pick -= weights[i]
		if pick <= 0.0:
			index = i
			break
	return RARITIES[maxi(index, floor_index)]


## Pesos de rareza al sortear: la suerte mueve una fracción del peso de la
## rareza base (RARITIES[0], Common) a las superiores, repartida en
## proporción a sus pesos base. La fracción se acerca a MAX_LUCK_TILT sin
## cortarse en seco, así la suerte sigue sirviendo por encima de 50 (el Tomo
## de Fortuna solo puede llegar a 150).
static func _rarity_weights(luck: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	var upper_total := 0.0
	for i: int in RARITIES.size():
		weights.append(float(RARITIES[i].weight))
		if i > 0:
			upper_total += float(RARITIES[i].weight)
	var tilt := MAX_LUCK_TILT * (1.0 - exp(-maxf(luck, 0.0) * LUCK_TILT_PER_POINT / MAX_LUCK_TILT))
	if tilt <= 0.0 or upper_total <= 0.0:
		return weights
	var moved := weights[0] * tilt
	weights[0] -= moved
	for i: int in range(1, weights.size()):
		weights[i] += moved * float(RARITIES[i].weight) / upper_total
	return weights
