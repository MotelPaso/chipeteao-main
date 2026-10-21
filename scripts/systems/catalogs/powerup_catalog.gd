class_name PowerUpCatalog
extends RefCounted
## Static catalog of temporary power-ups (iteration 53): the pickups that
## drop from kills, come out of a spring and are sold by the power-up
## vendor. Unlike tomes and items, a power-up is LOUD and BRIEF — twenty
## seconds where the run plays differently — so the roster is small and
## every row changes something you can feel without reading a number.
##
## Row fields:
##   id:            identifier (never shown; the log and the switches use it).
##   display_name:  player text.
##   description:   one line, player text.
##   duration:      seconds, before the raider's duration_multiplier.
##   weight:        roll weight. The star is deliberately ~2% of the total.
##   color:         pickup gem, HUD tile and toast tint.
##   glyph:         two letters for the placeholder art (unique across the
##                  weapon/tome/item/power-up glyph sets).
##   icon:          OPTIONAL explicit texture; otherwise the convention
##                  res://assets/icons/powerups/<id>.png applies.
##   effects:       [{stat, amount}] handed to PlayerStats.add_timed_boon.
##   kind:          behavior resolved by PowerUps, one branch each.
##
## Most rows are one or the other on purpose: a pure `effects` row needs no
## code at all (the timed-boon channel already exists), and a `kind` row
## gets exactly one branch in PowerUps. Adding "damage +200 for 20 s" must
## never mean writing a new behavior. Two rows carry both, and say why:
## the vampire's lifesteal is a plain stat riding alongside its per-kill
## behavior, and the star has a kind and no effects because it IS every
## other row at once.

const POWERUP_LIBRARY: Array[Dictionary] = [
	{
		"id": "haste", "display_name": "Celeridad total",
		"description": "Corres y atacas mucho más rápido.",
		"duration": 20.0, "weight": 1.0, "glyph": "VT",
		"color": Color(0.45, 0.95, 1.0),
		"effects": [{"stat": "move_speed", "amount": 60.0},
				{"stat": "cooldown", "amount": 40.0}],
	},
	{
		"id": "might", "display_name": "Furia",
		"description": "El doble de daño con todo lo que llevas.",
		"duration": 20.0, "weight": 1.0, "glyph": "FR",
		"color": Color(1.0, 0.4, 0.25),
		"effects": [{"stat": "damage", "amount": 100.0}],
	},
	{
		"id": "xp", "display_name": "Sabiduría brígida",
		"description": "Cada gema vale mucho más.",
		"duration": 20.0, "weight": 1.0, "glyph": "SB",
		"color": Color(0.55, 0.95, 0.55),
		"effects": [{"stat": "xp_gain", "amount": 150.0}],
	},
	{
		"id": "gold", "display_name": "Fiebre del oro",
		"description": "Cada baja paga el doble de puntos.",
		"duration": 20.0, "weight": 0.9, "glyph": "OR",
		"color": Color(1.0, 0.82, 0.3), "kind": "gold",
	},
	{
		"id": "reflect", "display_name": "Reflejo",
		"description": "Todo el daño que recibes vuelve a quien te lo hizo.",
		"duration": 20.0, "weight": 0.8, "glyph": "RJ",
		"color": Color(0.75, 0.55, 1.0), "kind": "reflect",
	},
	{
		"id": "vampire", "display_name": "Modo vampiro",
		"description": "Robas vida y cada baja te sube el HP máx. para siempre.",
		"duration": 20.0, "weight": 0.8, "glyph": "VP",
		"color": Color(0.85, 0.15, 0.35), "kind": "vampire",
		# The lifesteal is an ordinary timed boon; only the permanent HP
		# per kill needs the behavior branch.
		"effects": [{"stat": "lifesteal", "amount": 25.0}],
	},
	{
		"id": "flight", "display_name": "Vuelo",
		"description": "Mantén el salto para volar sobre el mapa.",
		"duration": 20.0, "weight": 0.8, "glyph": "VU",
		"color": Color(0.6, 0.85, 1.0), "kind": "flight",
	},
	{
		"id": "immortal", "display_name": "Inmortalidad",
		"description": "Nada te hace daño.",
		"duration": 20.0, "weight": 0.7, "glyph": "IN",
		"color": Color(1.0, 0.95, 0.7), "kind": "immortal",
	},
	{
		"id": "time_stop", "display_name": "Tiempo detenido",
		"description": "La horda se congela; tú no.",
		"duration": 20.0, "weight": 0.5, "glyph": "TD",
		"color": Color(0.7, 0.9, 1.0), "kind": "time_stop",
	},
	{
		# Shorter than the rest BECAUSE it is all of them: fifteen seconds
		# of everything reads as a jackpot, twenty starts to feel like the
		# normal state of the run.
		"id": "star", "display_name": "Estrella",
		"description": "Todos los power-ups a la vez, durante poco.",
		"duration": 15.0, "weight": 0.15, "glyph": "ES",
		"color": Color(1.0, 0.9, 0.35), "kind": "star",
	},
]

## Lazily built id -> row (see CatalogIndex).
static var _by_id: Dictionary[String, Dictionary] = {}


static func by_id(powerup_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(POWERUP_LIBRARY)
	return _by_id.get(powerup_id, {})


## Weighted roll. `exclude_star` is the DEFAULT for every source that is
## not a star sighting: the star is a thing you find roaming the map, not
## something a kill or a spring can hand you.
static func roll_id(exclude_star: bool = true) -> String:
	var total := 0.0
	for row: Dictionary in POWERUP_LIBRARY:
		if exclude_star and String(row.get("kind", "")) == "star":
			continue
		total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in POWERUP_LIBRARY:
		if exclude_star and String(row.get("kind", "")) == "star":
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return String(POWERUP_LIBRARY[0].id)


## Every row the star turns on, i.e. all of them except the star itself.
## Read by PowerUps.apply(); a row added above joins the star for free.
static func star_components() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in POWERUP_LIBRARY:
		if String(row.get("kind", "")) != "star":
			rows.append(row)
	return rows


static func color_of(powerup_id: String) -> Color:
	var row := by_id(powerup_id)
	return row.get("color", Color.WHITE) if not row.is_empty() else Color.WHITE


static func display_name_of(powerup_id: String) -> String:
	var row := by_id(powerup_id)
	return String(row.get("display_name", powerup_id))
