class_name PetCatalog
extends RefCounted
## Static catalog of pets (iteration 43, reshaped in 54): immortal
## companions that trail the raider, carry an extra weapon of their own
## (outside the 5-weapon cap, never in the upgrade pool) and grant a stat
## that grows with the run level.
##
## ONE pet at a time. The run has a single companion slot, so a second pet
## REPLACES the first — weapon and stat swap together and nothing stacks.
## Copies went with it: granting the same pet twice changes nothing, which
## is why every row now declares BOTH a weapon and a stat. A pet is one
## whole package; a row missing half of it would make a swap a downgrade
## the player cannot undo.
##
## Pets come from exactly two places, both of them a choice the player
## makes: the pet box (PetBox) and the animal trafficker (Vendor, kind
## "animals"). Chests and the roulette no longer roll them — a companion
## you did not pick is a companion that replaced the one you did.
##
## Row fields:
##   id: identifier (also the pet node name suffix) — never shown.
##   display_name: player text.
##   glyph:           two-letter tile the HUD draws while there is no
##             sprite. DECLARED, and unique across the weapon, evolution,
##             tome, item and power-up glyph sets — the strip mixes them.
##   weapon_scene:    weapon scene instanced under the pet.
##   weapon_damage_scale: the pet weapon's damage vs the player version,
##             and the whole story now that no copies grow it.
##   stat/amount_per_level: PlayerStats effect gained per run level.
##   stat_label:      player text; the pet box and the trafficker print it
##             on every card, so a row without one sells a mystery.
##   shape/color/size: code-built body (sphere | capsule | box).
##   hover:           height above the ground the pet floats at.

const PET_LIBRARY: Array[Dictionary] = [
	{
		"id": "alien", "display_name": "Alienígena", "glyph": "AG",
		"weapon_scene": "res://scenes/weapons/EmberWand.tscn", "weapon_damage_scale": 0.5,
		"stat": "luck", "amount_per_level": 1.0, "stat_label": "suerte +1 por nivel",
		"shape": "sphere", "color": Color(0.55, 0.95, 0.5), "size": 0.45, "hover": 1.6,
	},
	{
		"id": "dinosaur", "display_name": "Dinosaurio", "glyph": "DN",
		"weapon_scene": "res://scenes/weapons/Shortsword.tscn", "weapon_damage_scale": 0.6,
		"stat": "max_hp", "amount_per_level": 2.0, "stat_label": "HP máx. +2 por nivel",
		"shape": "capsule", "color": Color(0.35, 0.65, 0.3), "size": 0.55, "hover": 0.7,
	},
	{
		"id": "angry_bird", "display_name": "Pájaro furioso", "glyph": "PF",
		"weapon_scene": "res://scenes/weapons/DartPistol.tscn", "weapon_damage_scale": 0.5,
		"stat": "crit_chance", "amount_per_level": 0.3, "stat_label": "crítico +0.3% por nivel",
		"shape": "sphere", "color": Color(0.9, 0.25, 0.2), "size": 0.4, "hover": 1.9,
	},
	{
		"id": "capybara", "display_name": "Capibara", "glyph": "CB",
		"weapon_scene": "res://scenes/weapons/StormRod.tscn", "weapon_damage_scale": 0.5,
		"stat": "cooldown", "amount_per_level": 0.4,
		"stat_label": "velocidad de ataque +0.4% por nivel",
		"shape": "box", "color": Color(0.6, 0.42, 0.25), "size": 0.5, "hover": 0.45,
	},
	# Iteration 54 wave: the five companions the team asked for by name.
	{
		"id": "doki", "display_name": "Doki", "glyph": "DK",
		"weapon_scene": "res://scenes/weapons/Boomerang.tscn", "weapon_damage_scale": 0.55,
		"stat": "xp_gain", "amount_per_level": 0.5, "stat_label": "ganancia de XP +0.5% por nivel",
		"shape": "capsule", "color": Color(0.95, 0.55, 0.2), "size": 0.42, "hover": 0.6,
	},
	{
		"id": "pony", "display_name": "Pony", "glyph": "PN",
		"weapon_scene": "res://scenes/weapons/HuntingBow.tscn", "weapon_damage_scale": 0.5,
		# Under the band's top on purpose: move speed also feeds Juno's
		# speed_to_damage passive, so it is worth more than it reads.
		"stat": "move_speed", "amount_per_level": 0.4, "stat_label": "velocidad +0.4% por nivel",
		"shape": "box", "color": Color(0.85, 0.7, 0.45), "size": 0.6, "hover": 0.55,
	},
	{
		"id": "cj7", "display_name": "Cj7", "glyph": "CJ",
		# Always-on weapons (Aura, Orbes espirituales) sit at the bottom of
		# the scale band: they never miss a window, so uptime pays the rest.
		"weapon_scene": "res://scenes/weapons/Aura.tscn", "weapon_damage_scale": 0.45,
		"stat": "lifesteal", "amount_per_level": 0.5, "stat_label": "robo de vida +0.5% por nivel",
		"shape": "sphere", "color": Color(0.6, 0.9, 0.75), "size": 0.35, "hover": 1.5,
	},
	{
		"id": "magic_pumpkin", "display_name": "Calabaza mágica", "glyph": "CM",
		"weapon_scene": "res://scenes/weapons/ThornWhip.tscn", "weapon_damage_scale": 0.55,
		"stat": "thorns", "amount_per_level": 1.0, "stat_label": "espinas +1 por nivel",
		"shape": "sphere", "color": Color(0.95, 0.5, 0.12), "size": 0.5, "hover": 1.1,
	},
	{
		"id": "pokemon", "display_name": "Pokemon", "glyph": "PK",
		"weapon_scene": "res://scenes/weapons/SpiritOrbs.tscn", "weapon_damage_scale": 0.45,
		"stat": "damage", "amount_per_level": 0.5, "stat_label": "daño +0.5% por nivel",
		"shape": "capsule", "color": Color(0.95, 0.85, 0.25), "size": 0.45, "hover": 0.9,
	},
]


## Lazily built id -> row index (see CatalogIndex): PlayerStats.recompute()
## resolves one row per following pet.
static var _by_id: Dictionary[String, Dictionary] = {}


static func by_id(pet_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(PET_LIBRARY)
	return _by_id.get(pet_id, {})


## Ids in catalog order (the pet box and the trafficker roll from these).
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in PET_LIBRARY:
		out.append(String(row.id))
	return out


## The pet's weapon under its CATALOG name. The scene file name is the
## node_name the weapon library keys on (StormRod.tscn -> "StormRod"); the
## live node is called "PetWeapon", so it cannot answer this.
static func weapon_display_name(row: Dictionary) -> String:
	var scene := String(row.get("weapon_scene", ""))
	if scene.is_empty():
		return ""
	return UpgradePool.weapon_display_name(scene.get_file().get_basename())
