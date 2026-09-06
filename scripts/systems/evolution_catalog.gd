class_name EvolutionCatalog
extends RefCounted
## Static catalog of weapon evolutions: the recipes that turn an invested
## weapon into a named, far stronger form. Data-driven like the other
## catalogs — a new evolution is one row here.
##
## The rule (iteration 38, replacing the chest + paired-tome ceremony):
## every upgrade card invested in a weapon is one weapon level; the moment
## a weapon reaches EVOLVE_AT_LEVEL it evolves on the spot, with the full
## ceremony (fanfare, banner, sparkle) run by try_evolve_by_level from
## UpgradePool.apply. Chests and tomes play no part any more.
##
## Row fields:
##   weapon_id/weapon_node: WEAPON_LIBRARY identity of the base weapon —
##             identifiers, never shown.
##   evolved_name: the new display name, announced and shown in Collection.
##   flavor: Collection line. evolved_name and flavor are player text.
##   glyph:  2-letter tile the HUD loadout strip draws for the evolved
##             weapon while there is no sprite. DECLARED, never derived from
##             evolved_name: initials of Spanish names collapse ("Cáliz de
##             peste" and "Corona de tempestad" would both give "CD"). Keep
##             it unique across this library, WEAPON_LIBRARY, TOME_LIBRARY
##             and ITEM_LIBRARY — the strip mixes all four.
##   mults: {property: factor} multiplied onto the weapon node on evolve.
##   adds:  {property: amount} added onto the weapon node on evolve.
##   flavor: Collection line describing what the evolved form does.
## Persistence: the ceremony bumps "evo_<weapon_id>" and "evolutions_total"
## (SaveData counters), which the Collection screen and quests read.

## Upgrade cards a weapon must have received (WeaponBase.upgrade_level)
## to evolve. Weapons WITHOUT a catalog row simply keep leveling.
const EVOLVE_AT_LEVEL: int = 6

const EVOLUTION_LIBRARY: Array[Dictionary] = [
	{
		"weapon_id": "shortsword", "weapon_node": "Shortsword",
		"evolved_name": "Mandoble del Caudillo", "glyph": "MC",
		"mults": {"damage": 2.2, "cooldown_scale": 0.85},
		"adds": {},
		"flavor": "un arco colosal que parte toda la primera línea",
	},
	{
		"weapon_id": "dart_pistol", "weapon_node": "DartPistol",
		"evolved_name": "Tormenta de agujas", "glyph": "TA",
		"mults": {"damage": 1.5, "cooldown_scale": 0.7},
		"adds": {"projectile_count": 2},
		"flavor": "una granizada de dardos que no deja de caer",
	},
	{
		"weapon_id": "ember_wand", "weapon_node": "EmberWand",
		"evolved_name": "Lanza solar", "glyph": "LS",
		"mults": {"damage": 1.8, "burst_radius": 1.6},
		"adds": {},
		"flavor": "detonaciones del tamaño de un claro",
	},
	{
		"weapon_id": "hunting_bow", "weapon_node": "HuntingBow",
		"evolved_name": "Perforacorazones", "glyph": "PC",
		"mults": {"damage": 1.8},
		"adds": {"pierce_count": 3},
		"flavor": "flechas que enhebran columnas enteras de enemigos",
	},
	{
		"weapon_id": "thorn_whip", "weapon_node": "ThornWhip",
		"evolved_name": "Guirnalda sepulcral", "glyph": "GS",
		"mults": {"damage": 1.7},
		"adds": {"slow_percent": 25.0},
		"flavor": "un zarzal que estrangula y casi detiene a la horda",
	},
	{
		"weapon_id": "boomerang", "weapon_node": "Boomerang",
		"evolved_name": "Sierra orbital", "glyph": "SO",
		"mults": {"damage": 1.8, "travel_scale": 1.3},
		"adds": {},
		"flavor": "una hoja aullante que talla al ir y al volver",
	},
	{
		"weapon_id": "twin_daggers", "weapon_node": "TwinDaggers",
		"evolved_name": "Colmillos fantasma", "glyph": "CF",
		"mults": {"damage": 1.5, "cooldown_scale": 0.6},
		"adds": {},
		"flavor": "estocadas más rápidas de lo que el ojo alcanza",
	},
	{
		"weapon_id": "blood_vial", "weapon_node": "BloodVial",
		"evolved_name": "Cáliz de peste", "glyph": "CP",
		"mults": {"damage": 1.8},
		"adds": {"pool_ticks": 2},
		"flavor": "charcos que siguen pudriéndose mucho después de que el frasco revienta",
	},
	{
		"weapon_id": "spirit_orbs", "weapon_node": "SpiritOrbs",
		"evolved_name": "Anillo de cometas", "glyph": "AN",
		"mults": {"damage": 1.8, "cooldown": 0.6},
		"adds": {"projectile_count": 1},
		"flavor": "un halo ardiente que nadie cruza y vive",
	},
	{
		"weapon_id": "storm_rod", "weapon_node": "StormRod",
		"evolved_name": "Corona de tempestad", "glyph": "CT",
		"mults": {"damage": 1.7},
		"adds": {"chain_count": 3},
		"flavor": "rayos que se bifurcan hasta que no queda nada en pie",
	},
	# Iteration 43 wave.
	{
		"weapon_id": "slime_trail", "weapon_node": "SlimeTrail",
		"evolved_name": "Marea ácida", "glyph": "MA",
		"mults": {"damage": 1.8, "puddle_radius": 1.4, "puddle_life": 1.5},
		"adds": {},
		"flavor": "una estela corrosiva que nunca termina de secarse",
	},
	{
		"weapon_id": "aura", "weapon_node": "Aura",
		"evolved_name": "Halo de ruina", "glyph": "HR",
		"mults": {"damage": 1.8, "attack_range": 1.35, "cooldown": 0.7},
		"adds": {},
		"flavor": "un sol adentro del cual nadie aguanta",
	},
	{
		"weapon_id": "stench", "weapon_node": "Stench",
		"evolved_name": "Miasma", "glyph": "MI",
		"mults": {"damage": 1.6, "poison_duration": 1.8, "attack_range": 1.3},
		"adds": {},
		"flavor": "una nube de podredumbre que se queda en todo lo que toca",
	},
	{
		"weapon_id": "kamehameha", "weapon_node": "Kamehameha",
		"evolved_name": "Resplandor Final", "glyph": "RF",
		"mults": {"damage": 2.0, "beam_width": 1.6, "cooldown": 0.75},
		"adds": {},
		"flavor": "un rayo tan ancho que acaba una horda de un solo aliento",
	},
]


## Lazily built lookups (see CatalogIndex); the Collection screen resolves
## one recipe per weapon row it draws.
static var _by_weapon_id: Dictionary[String, Dictionary] = {}
static var _by_weapon_node: Dictionary[String, Dictionary] = {}


## Row for the given base weapon id, or an empty Dictionary if none.
static func by_weapon_id(weapon_id: String) -> Dictionary:
	if _by_weapon_id.is_empty():
		_by_weapon_id = CatalogIndex.build(EVOLUTION_LIBRARY, "weapon_id")
	return _by_weapon_id.get(weapon_id, {})


## Row for a live weapon node (matched by mount node name), or empty.
static func by_weapon_node(node_name: String) -> Dictionary:
	if _by_weapon_node.is_empty():
		_by_weapon_node = CatalogIndex.build(EVOLUTION_LIBRARY, "weapon_node")
	return _by_weapon_node.get(node_name, {})


## Evolves `weapon` if it just reached EVOLVE_AT_LEVEL and has a recipe:
## applies the row, runs the ceremony (fanfare, banner, sparkle on the
## carrier, shake), bumps the Collection/quest counters and prints the
## soak log line. Returns true when an evolution happened.
static func try_evolve_by_level(weapon: WeaponBase, player: Node) -> bool:
	if weapon == null or weapon.evolved or weapon.upgrade_level < EVOLVE_AT_LEVEL:
		return false
	var row := by_weapon_node(weapon.name)
	if row.is_empty():
		return false
	weapon.evolve(row)
	var weapon_id := String(row.weapon_id)
	_celebrate(row, weapon.evolved_name, player)
	# One-line log (RunManager convention) for headless soaks.
	print("Weapon evolved: %s -> %s" % [weapon_id, weapon.evolved_name])
	return true


## The payoff moment: fanfare, sparkle on the carrier, banner, and the
## Collection/quest counters. Split out of try_evolve_by_level so the
## catalog side stays testable, and every autoload is reached through the
## same guarded helper — a `-s` harness has no autoloads instanced, and the
## old direct Sfx/Juice calls aborted it before a single assert ran.
static func _celebrate(row: Dictionary, evolved_name: String, player: Node) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var sfx := UpgradePool.autoload_node(&"Sfx")
	if sfx != null:
		sfx.play(&"secret_fanfare")
	var juice := UpgradePool.autoload_node(&"Juice")
	if juice != null:
		if player is Node3D:
			juice.sparkle((player as Node3D).global_position + Vector3.UP * 1.2)
		juice.shake(0.25, 0.5)
	# The banner names the weapon the way every other screen does — from
	# WEAPON_LIBRARY. It used to prettify the internal id instead
	# (weapon_id.capitalize()), which only ever matched the English names
	# by accident and could never be translated.
	loop.call_group("boss_ui", "announce_major", "¡%s evolucionó a %s!"
			% [UpgradePool.weapon_display_name(String(row.weapon_node)), evolved_name])
	var save_data := UpgradePool.autoload_node(&"SaveData")
	if save_data != null:
		save_data.bump("evo_" + String(row.weapon_id))
		save_data.bump("evolutions_total")
