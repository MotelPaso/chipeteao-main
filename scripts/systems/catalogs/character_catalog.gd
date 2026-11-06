class_name CharacterCatalog
extends RefCounted
## Static catalog of playable characters (GDD 5): each pairs a starting
## weapon with a scaling per-level passive. Data-driven like TOME_LIBRARY
## and WEAPON_LIBRARY — a new playable character is one new row here (the
## select screen and player spawn read the rows; no per-character code).
## Row fields:
##   id/display_name/blurb: identity plus the select-card flavor line.
##   weapon_scene: starting weapon, instanced under the player's Weapons
##             mount at spawn.
##   weapon_node_name: instance name; must match the WEAPON_LIBRARY row's
##             node_name so the upgrade pool sees the weapon as owned.
##   weapon_display_name: weapon name shown on the select card.
##   passive_description: passive line shown on the select card.
##   passive_stat/passive_amount: passive effect as data — a PlayerStats
##             effect stat id (see _apply_effect there) and the amount
##             gained per level past 1 (percent for multiplier stats).
##   passive_kind (optional, default "per_level"): how PlayerStats applies
##             the passive — "per_level" scales with run level;
##             "speed_to_damage" converts bonus move speed into bonus
##             damage at the passive_amount ratio (stat id unused);
##             "evasion_execute" is per_level scaling plus every dodge
##             executing a weakened non-boss attacker.
##   passive_base (optional, default 0): amount already granted at level 1,
##             before any per-level increments (Doc's starting lifesteal).
##   unlock_cost: Shards to unlock on the select screen (GDD 5/8); 0 means
##             playable from the start. SaveData gates and persists the
##             actual unlocks — this is only the price data.
##   unlock_boss (optional): hidden-miniboss id whose kill grants this
##             character for free, bypassing Shards (GDD 5: skill unlocks).
##             SecretBossBase resolves the reward through by_unlock_boss on
##             the kill, so the mapping lives here, not in boss code.
##   unlock_hint (optional): vague select-screen clue for the boss path,
##             rendered on the locked card beside the Shard price.
##   tint:     the character's body identity colour (also the card swatch).
##   model_scene (optional): cosmetic body for THIS character — a model
##             wrapper scene (like foca_character.tscn) or a raw .glb.
##             Absent = the seal. Wrapper scenes may carry a walk-animator
##             script on their root (goku_walk_animation.gd,
##             yandere_walk_animation.gd, storm_cat_walk.gd): it measures how
##             far its own node moves each physics tick, so the limbs follow
##             the player's real movement with no per-character code here.
##   model_scale (optional): uniform scale multiplier applied on top of the
##             model scene's own transform — raw .glb rows declare their
##             sizing (the seal needs 0.6), wrapper scenes carry their own.
##             Absent/<=0 = no rescaling.
##   tint_material_prefix (optional): resource_name prefix of THIS model's
##             tintable materials (each export names them differently;
##             surfaces whose materials do not carry the prefix stay
##             untouched). Absent = the seal's "Azul personaje".

##
## Player-facing text: display_name, blurb, weapon_display_name,
## passive_description and unlock_hint. Everything else (id, weapon_scene,
## weapon_node_name, passive_stat, passive_kind) is an identifier.

## Fallback character when no selection was made (Main booted directly).
const DEFAULT_ID: String = "rook"

const CHARACTER_LIBRARY: Array[Dictionary] = [
	{
		"id": "rook", "display_name": "Rook",
		"blurb": "Un muro con patas: sus golpes solo se ponen más feos.",
		"weapon_scene": "res://scenes/weapons/Shortsword.tscn",
		"weapon_node_name": "Shortsword",
		"weapon_display_name": "Espada corta",
		"passive_description": "+0.8% de daño por nivel",
		"passive_stat": "damage", "passive_amount": 0.8,
		"unlock_cost": 0,
		"tint": Color(0.35, 0.51, 0.74),
	},
	{
		"id": "ash", "display_name": "Ash",
		"blurb": "Un ermitaño cubierto de hollín cuyo fuego se abre más en cada nivel.",
		"weapon_scene": "res://scenes/weapons/EmberWand.tscn",
		"weapon_node_name": "EmberWand",
		"weapon_display_name": "Vara de brasas",
		"passive_description": "+0.7% de área por nivel",
		"passive_stat": "area", "passive_amount": 0.7,
		"unlock_cost": 0, # 50
		"model_scene": "res://assets/models/fuego_character.tscn",
		"tint": Color(0.89, 0.45, 0.18),
	},
	{
		"id": "Yandere-chan", "display_name": "Yandere-chan",
		"blurb": "Termina tu juego yandere-dev.",
		"weapon_scene": "res://scenes/weapons/HuntingBow.tscn",
		"weapon_node_name": "HuntingBow",
		"weapon_display_name": "Arco de caza",
		"passive_description": "+0.6% de daño por cada 1% de velocidad extra",
		"passive_stat": "damage", "passive_amount": 0.6,
		"model_scene": "res://assets/models/yandere_character.tscn",
		"passive_kind": "speed_to_damage",
		"unlock_cost": 0, # 80
		"tint": Color(0.24, 0.55, 0.32),
	},
	{
		"id": "wisp", "display_name": "Wisp",
		"blurb": "Un espíritu a medias, rodeado de luces que solo le obedecen a él.",
		"weapon_scene": "res://scenes/weapons/SpiritOrbs.tscn",
		"weapon_node_name": "SpiritOrbs",
		"weapon_display_name": "Orbes espirituales",
		"passive_description": "+1.0% de xp por nivel",
		"passive_stat": "xp", "passive_amount": 1.0,
		"unlock_cost": 0, # 120
		"tint": Color(0.55, 0.85, 0.95),
	},
	{
		"id": "Electro Gato", "display_name": "Electro Gato",
		"blurb": "Un cazatormentas cuya suerte se lee como un parte del clima.",
		"weapon_scene": "res://scenes/weapons/StormRod.tscn",
		"weapon_node_name": "StormRod",
		"weapon_display_name": "Pararrayos",
		"passive_description": "+1 de suerte por nivel (cartas más raras)",
		"passive_stat": "luck", "passive_amount": 1.0,
		"model_scene": "res://assets/models/storm_cat_character.tscn",
		"unlock_cost": 0, # 130
		"tint": Color(0.35, 0.45, 0.85),
	},
	{
		"id": "doc", "display_name": "Doc",
		"blurb": "Un cirujano de campaña muy alegre que le cobra a cada paciente en sangre.",
		"weapon_scene": "res://scenes/weapons/BloodVial.tscn",
		"weapon_node_name": "BloodVial",
		"weapon_display_name": "Vial de sangre",
		"passive_description": "+1% de robo de vida por nivel (base +5%)",
		"passive_stat": "lifesteal", "passive_amount": 1.0,
		"passive_base": 5.0,
		"unlock_cost": 0, # 150
		"tint": Color(0.72, 0.16, 0.2),
	},
	# Iteration 43 roster: the slime, stench and beam starters.
	{
		"id": "Moka", "display_name": "Moka",
		"blurb": "Una foca muy watona.",
		"weapon_scene": "res://scenes/weapons/SlimeTrail.tscn",
		"weapon_node_name": "SlimeTrail",
		"weapon_display_name": "Rastro de baba",
		"passive_description": "+2% de duración de efectos por nivel",
		"passive_stat": "duration", "passive_amount": 2.0,
		"unlock_cost": 120,
		"tint": Color(0.35, 0.45, 0.85),
	},
	{
		"id": "bogg", "display_name": "Bogg",
		"blurb": "Nadie se sienta al lado de Bogg. Tampoco nadie sobrevive cerca de Bogg.",
		"weapon_scene": "res://scenes/weapons/Stench.tscn",
		"weapon_node_name": "Stench",
		"weapon_display_name": "Hedor",
		"passive_description": "+1% de área de ataque por nivel",
		"passive_stat": "area", "passive_amount": 1.0,
		"unlock_cost": 120,
		"tint": Color(0.6, 0.7, 0.3),
	},
	{
		"id": "Goku", "display_name": "Goku",
		"blurb": "Carga seis segundos y después reescribe el mapa.",
		"weapon_scene": "res://scenes/weapons/Kamehameha.tscn",
		"weapon_node_name": "Kamehameha",
		"weapon_display_name": "Kamehameha",
		"passive_description": "+1% de daño por nivel",
		"passive_stat": "damage", "passive_amount": 1.0,
		"model_scene": "res://assets/models/goku_character.tscn",
		"unlock_cost": 0,
		"tint": Color(0.4, 0.7, 1.0),
	},
	# Iteration 54 roster: the team's three picks. The display names are
	# their own words and ship verbatim — no sentence case, no translation
	# (GLOSARIO rule 5). All three cost 0, so starter_ids() grows from two
	# to five and SaveData appends them to existing saves on load.
	{
		"id": "boxer", "display_name": "Boxeador",
		"blurb": "Pega primero, pega dos veces y nunca pregunta nombres.",
		"weapon_scene": "res://scenes/weapons/TwinDaggers.tscn",
		"weapon_node_name": "TwinDaggers",
		"weapon_display_name": "Dagas gemelas",
		# Under Vex's 0.5 on purpose: the daggers swing far more often than
		# the pistol, so a point of crit is worth more per level here.
		"passive_description": "+0.4% de prob. de crítico por nivel",
		"passive_stat": "crit_chance", "passive_amount": 0.4,
		"unlock_cost": 0,
		"tint": Color(0.726, 0.299, 0.166, 1.0),
	},
	{
		"id": "gucci_morty", "display_name": "PNG gucci morty",
		"blurb": "Un recorte de baja resolución al que la suerte no deja de sonreírle.",
		"weapon_scene": "res://scenes/weapons/DartPistol.tscn",
		"weapon_node_name": "DartPistol",
		"weapon_display_name": "Pistola de dardos",
		# Torren keeps luck at 1.0 per level: a free starter matching him
		# would leave nothing to buy for his 130 esquirlas.
		"passive_description": "+0.6 de suerte por nivel",
		"passive_stat": "luck", "passive_amount": 0.6,
		"model_scene": "res://assets/models/gucci_morty.tscn",
		"unlock_cost": 0,
		"tint": Color(0.92, 0.34, 0.62),
	},
	{
		"id": "backyardigan", "display_name": "Backyardigan",
		"blurb": "No corre, coreografía; y todo lo que roza se prende.",
		"weapon_scene": "res://scenes/weapons/Aura.tscn",
		"weapon_node_name": "Aura",
		"weapon_display_name": "Aura",
		# Move speed IS the Aura's damage stat: a ring that only burns what
		# it touches scales with how much ground the raider covers.
		"passive_description": "+0.8% de velocidad de movimiento por nivel",
		"passive_stat": "move_speed", "passive_amount": 0.8,
		"unlock_cost": 0,
		"model_scene": "res://assets/models/tyrone_character.tscn",
		"tint_material_prefix": "Placeholder personaje",
		"tint": Color(0.14, 0.62, 0.6),
	},
]


## Lazily built lookups (see CatalogIndex): the select screen resolves a
## row per card per redraw, and the player spawn one per raider.
static var _by_id: Dictionary[String, Dictionary] = {}
static var _by_unlock_boss: Dictionary[String, Dictionary] = {}


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(character_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(CHARACTER_LIBRARY)
	return _by_id.get(character_id, {})


## Row for the given id, falling back to the default character so spawn
## paths always get a valid loadout (e.g. a stale or mistyped saved id).
static func by_id_or_default(character_id: String) -> Dictionary:
	var row := by_id(character_id)
	return row if not row.is_empty() else by_id(DEFAULT_ID)


## Row whose unlock_boss names the given hidden-miniboss id, or an empty
## Dictionary when no character unlocks off that boss.
static func by_unlock_boss(boss_id: String) -> Dictionary:
	if boss_id.is_empty():
		return {}
	if _by_unlock_boss.is_empty():
		_by_unlock_boss = CatalogIndex.build(CHARACTER_LIBRARY, "unlock_boss")
	return _by_unlock_boss.get(boss_id, {})


## Ids playable from the start (unlock_cost 0) — Rook and Vex from GDD 5,
## plus the iteration-54 trio.
## SaveData seeds a fresh save's unlocked list from this.
static func starter_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in CHARACTER_LIBRARY:
		if int(row.get("unlock_cost", 0)) == 0:
			ids.append(String(row.id))
	return ids
