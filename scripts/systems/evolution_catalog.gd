class_name EvolutionCatalog
extends RefCounted
## Static catalog of weapon evolutions: the recipes that turn an invested
## weapon into a named, far stronger form. Data-driven like the other
## catalogs — a new evolution is one row here.
##
## The rule (iteration 46, deepening iteration 38's card-only ceremony):
## every upgrade card invested in a weapon is one weapon level, and every
## EVOLVE_AT_LEVEL-th level is a MILESTONE run by try_advance_by_level from
## UpgradePool.apply. The first milestone evolves the weapon when it has a
## recipe here; every milestone after that — and the first one for a weapon
## with no recipe at all — is an ascension (WeaponBase.ascend), so no weapon
## ever stops improving. Both share one ceremony (fanfare, banner, sparkle).
## Chests and tomes play no part any more.
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
## per milestone: the first EVOLVE_AT_LEVEL levels buy the evolution, and
## every further multiple buys an ascension. ONE number on purpose — an
## evolution threshold that drifted from the ascension period would leave
## a dead stretch of levels where a weapon gains nothing.
const EVOLVE_AT_LEVEL: int = 10

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


## Runs the milestone `weapon` just reached, if any: the evolution at the
## first one (when a recipe exists), an ascension at every later one and at
## the first one for a recipe-less weapon. Applies the change, runs the
## ceremony (fanfare, banner, sparkle on the carrier, shake), bumps the
## Collection/quest counters and prints the soak log line.
## Returns true when a milestone fired.
static func try_advance_by_level(weapon: WeaponBase, player: Node) -> bool:
	if weapon == null:
		return false
	# Integer division: level 10-19 is tier 1, 20-29 tier 2, and so on.
	var tier := weapon.upgrade_level / EVOLVE_AT_LEVEL
	if tier <= weapon.ascension_tier:
		return false
	weapon.ascension_tier = tier
	if tier == 1 and not weapon.evolved:
		var row := by_weapon_node(weapon.name)
		if not row.is_empty():
			weapon.evolve(row)
			_celebrate(player)
			_announce("¡%s evolucionó a %s!" % [
					weapon_display(weapon), weapon.evolved_name])
			_record_evolution(String(row.weapon_id))
			# One-line log (RunManager convention) for headless soaks.
			print("Weapon evolved: %s -> %s" % [String(row.weapon_id), weapon.evolved_name])
			return true
	weapon.ascend(tier)
	_celebrate(player)
	_announce("¡%s asciende!" % weapon_display(weapon))
	print("Weapon ascended: %s tier %d"
			% [UpgradePool.weapon_id_for_node(weapon.name), tier])
	return true


## The name a milestone banner uses: the evolved form once the weapon has
## one, otherwise its WEAPON_LIBRARY display name. Never the internal id.
static func weapon_display(weapon: WeaponBase) -> String:
	if weapon.evolved and not weapon.evolved_name.is_empty():
		return weapon.evolved_name
	return UpgradePool.weapon_display_name(weapon.name)


## The payoff moment shared by evolutions and ascensions: fanfare, sparkle
## on the carrier, shake. Split out of try_advance_by_level so the catalog
## side stays testable, and every autoload is reached through the same
## guarded helper — a `-s` harness has no autoloads instanced, and the old
## direct Sfx/Juice calls aborted it before a single assert ran.
static func _celebrate(player: Node) -> void:
	var sfx := UpgradePool.autoload_node(&"Sfx")
	if sfx != null:
		sfx.play(&"secret_fanfare")
	var juice := UpgradePool.autoload_node(&"Juice")
	if juice != null:
		if player is Node3D:
			juice.sparkle((player as Node3D).global_position + Vector3.UP * 1.2)
		juice.shake(0.25, 0.5)


## The banner. Names the weapon the way every other screen does — from
## WEAPON_LIBRARY (it used to prettify the internal id, which only ever
## matched the English names by accident and could never be translated).
static func _announce(message: String) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	loop.call_group("boss_ui", "announce_major", message)


## Collection/quest bookkeeping for an evolution (ascensions have no
## counters of their own: the weapon level already carries them).
static func _record_evolution(weapon_id: String) -> void:
	var save_data := UpgradePool.autoload_node(&"SaveData")
	if save_data != null:
		save_data.bump("evo_" + weapon_id)
		save_data.bump("evolutions_total")
