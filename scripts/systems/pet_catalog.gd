class_name PetCatalog
extends RefCounted
## Static catalog of pets (iteration 43): immortal companions that trail
## the raider, carry an extra weapon of their own (outside the 5-weapon
## cap, never in the upgrade pool) and/or grant a stat that grows with
## the run level. Pets arrive as items (ItemCatalog rows with
## kind "pet" + pet_id) so chests and the roulette hand them out; extra
## copies of the same pet item boost its weapon.
## Row fields:
##   id: identifier (also the pet node name suffix) — never shown.
##   display_name: player text.
##   weapon_scene:    OPTIONAL weapon scene instanced under the pet.
##   weapon_damage_scale: the pet weapon's damage vs the player version.
##   stat/amount_per_level: OPTIONAL PlayerStats effect gained per run level.
##   stat_label:      HUD/announce text for the stat (player text; no
##             screen prints it yet — see the HUD loadout strip TODO).
##   shape/color/size: code-built body (sphere | capsule | box).
##   hover:           height above the ground the pet floats at.

const PET_LIBRARY: Array[Dictionary] = [
	{
		"id": "alien", "display_name": "Alienígena",
		"weapon_scene": "res://scenes/weapons/StormRod.tscn", "weapon_damage_scale": 0.5,
		"stat": "luck", "amount_per_level": 1.0, "stat_label": "suerte +1 por nivel",
		"shape": "sphere", "color": Color(0.55, 0.95, 0.5), "size": 0.45, "hover": 1.6,
	},
	{
		"id": "dinosaur", "display_name": "Dinosaurio",
		"weapon_scene": "res://scenes/weapons/Shortsword.tscn", "weapon_damage_scale": 0.6,
		"stat": "max_hp", "amount_per_level": 2.0, "stat_label": "HP máx. +2 por nivel",
		"shape": "capsule", "color": Color(0.35, 0.65, 0.3), "size": 0.55, "hover": 0.7,
	},
	{
		"id": "angry_bird", "display_name": "Pájaro furioso",
		"weapon_scene": "res://scenes/weapons/DartPistol.tscn", "weapon_damage_scale": 0.5,
		"stat": "crit_chance", "amount_per_level": 0.3, "stat_label": "crítico +0.3% por nivel",
		"shape": "sphere", "color": Color(0.9, 0.25, 0.2), "size": 0.4, "hover": 1.9,
	},
	{
		"id": "capybara", "display_name": "Capibara",
		"weapon_scene": "", "weapon_damage_scale": 1.0,
		"stat": "xp_gain", "amount_per_level": 0.6, "stat_label": "ganancia de XP +0.6% por nivel",
		"shape": "box", "color": Color(0.6, 0.42, 0.25), "size": 0.5, "hover": 0.45,
	},
]


## Lazily built id -> row index (see CatalogIndex): PlayerStats.recompute()
## resolves one row per following pet.
static var _by_id: Dictionary[String, Dictionary] = {}


static func by_id(pet_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(PET_LIBRARY)
	return _by_id.get(pet_id, {})
