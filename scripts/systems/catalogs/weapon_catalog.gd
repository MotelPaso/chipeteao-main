class_name WeaponCatalog
extends RefCounted
## Catálogo de armas equipables. Las cartas new_weapon y las cartas de stats
## por arma del pool de mejoras (UpgradePool) se generan desde aquí, así un
## arma nueva es una fila nueva más su escena en scenes/weapons/.
##
## Se puede cambiar libremente: display_name, glyph, flavor y los textos y
## números de extra_entries.
## Llaves internas, NUNCA las cambies:
##   id: va en los contadores used_weapon_<id> y evo_<id> del guardado y en
##       el weapon_id de EvolutionCatalog.
##   node_name: nombre del nodo del arma bajo el montaje Weapons del jugador.
##       Lo nombran el target "weapon/<node_name>" de las cartas, el
##       weapon_node_name de CharacterCatalog y el weapon_node de
##       EvolutionCatalog, y debe ser el nombre del archivo de `scene` (las
##       mascotas resuelven su arma por el nombre del archivo).
## La `property` de cada carta de extra_entries debe existir en la escena del
## arma.
##
## Campos de cada fila:
##   id, node_name: llaves (ver arriba). Nunca se muestran.
##   display_name: nombre del arma que ve el jugador.
##   glyph: sigla de dos letras que dibuja la tira de armas del HUD mientras
##       no hay ícono (el mismo campo que llevan las filas de ItemCatalog). Se
##       DECLARA, no se deriva de display_name: casi todos los nombres en
##       español son «Sustantivo de Complemento» y las iniciales chocan («Vara
##       de brasas» y «Vial de sangre» darían «VD»). No debe repetirse entre
##       armas, evoluciones, tomos, objetos, power-ups ni mascotas: la tira los
##       mezcla (el lint glyphs_unique lo revisa).
##   scene: escena del arma que se instancia al ganarla.
##   flavor: texto de la carta de arma nueva y de Colección.
##   extra_entries (opcional): cartas propias del arma, con el formato de
##       entrada de UpgradePool (id, title, description, target, property, op,
##       amount); se ofrecen junto a las de UpgradePool.WEAPON_STAT_CARDS.
## Texto que ve el jugador: display_name, flavor, y title y description de
## extra_entries.

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


## Índices id -> fila y node_name -> fila, armados al primer uso (ver
## CatalogIndex).
static var _by_id: Dictionary[String, Dictionary] = {}
static var _by_node: Dictionary[String, Dictionary] = {}


## Fila con ese id, o un Dictionary vacío si no existe.
static func by_id(weapon_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(WEAPON_LIBRARY)
	return _by_id.get(weapon_id, {})


## Fila para el nombre de un nodo del montaje, o vacío si no existe.
static func by_node(node_name: String) -> Dictionary:
	if _by_node.is_empty():
		_by_node = CatalogIndex.build(WEAPON_LIBRARY, "node_name")
	return _by_node.get(node_name, {})


## Id para el nombre de un nodo del montaje ("" si no existe); con él se arman
## los contadores used_weapon_<id>.
static func id_for_node(node_name: String) -> String:
	return String(by_node(node_name).get("id", ""))


## Nombre que ve el jugador para el nombre de un nodo del montaje, o el
## propio nombre del nodo si no existe. La tira del HUD, las cartas y el
## cartel de evolución resuelven nombres por aquí.
static func display_name_for_node(node_name: String) -> String:
	return String(by_node(node_name).get("display_name", node_name))
