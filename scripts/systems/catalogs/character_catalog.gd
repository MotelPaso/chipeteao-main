class_name CharacterCatalog
extends RefCounted
<<<<<<< Updated upstream
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
=======
## Catálogo de personajes jugables: cada fila une un arma inicial con una
## pasiva que escala por nivel. Un personaje nuevo es una fila nueva aquí; la
## pantalla de selección y el spawn del jugador leen las filas, no hay código
## por personaje.
##
## Se puede cambiar libremente: display_name, blurb, weapon_node_name,
## passive_*, unlock_cost, tint, model_*.
## Llave interna, NUNCA la cambies: id (es la llave del guardado y de las
## misiones; usa minúsculas y guiones bajos). Si de verdad hay que
## renombrarlo, agrega la fila viejo -> nuevo en SaveData.ID_ALIASES para que
## los guardados existentes no pierdan el personaje ni sus contadores.
## Cuidado con unlock_cost: poner 0 lo deja gratis para siempre en los
## guardados existentes. SaveData agrega cada personaje gratis al guardado al
## cargarlo, y volver a ponerle precio después no lo bloquea de nuevo.
## weapon_node_name debe ser el node_name de una fila de WeaponCatalog: de esa
## fila salen la escena y el nombre del arma inicial.
##
## Campos de cada fila:
##   id: llave interna (ver arriba). SaveData guarda los desbloqueos por id y
##       cuenta runs_as_<id> / wins_as_<id>; las misiones nombran esos
##       contadores.
##   display_name, blurb: nombre y frase de la carta de selección.
##   weapon_node_name: arma inicial, por el node_name de su fila en
##       WeaponCatalog. El jugador la instancia bajo su montaje Weapons con
##       ese nombre, así el pool de mejoras la cuenta como poseída.
##   weapon_scene, weapon_display_name: NO se escriben aquí. CHARACTER_LIBRARY
##       los copia de la fila del arma (escena y nombre en la carta).
##   passive_description: texto de la pasiva en la carta; sus números deben
##       coincidir con passive_amount, passive_base y los demás campos passive_*.
##   passive_stat, passive_amount: efecto de la pasiva como dato, un stat de
##       PlayerStats._apply_effect y lo que gana por cada nivel después del 1
##       (porcentaje en los stats multiplicadores).
##   passive_kind (opcional, "per_level" por defecto): cómo la aplica
##       PlayerStats. "per_level" escala con el nivel de la incursión;
##       "per_n_levels" suma passive_amount cada passive_every niveles
##       completos (nivel 5, 10, ...) en vez de cada nivel;
##       "hp_to_damage" escala passive_stat por nivel como per_level y además
##       da passive_amount2 % de daño por cada punto de HP máx. total;
##       "speed_to_damage" convierte la velocidad de movimiento extra en daño
##       extra a razón de passive_amount (passive_stat no se usa);
##       "evasion_execute" escala por nivel y además cada esquive ejecuta a un
##       atacante debilitado que no sea jefe.
##   passive_base (opcional, 0 por defecto): cantidad que ya da en el nivel 1,
##       antes de los aumentos por nivel.
##   passive_stat2, passive_amount2 (opcionales): con "per_level", una
##       segunda stat que gana passive_amount2 por nivel igual que la primera.
##       Con "hp_to_damage", passive_amount2 es el % de daño por punto de HP
##       máx. y passive_stat2 no se usa.
##   passive_every (obligatorio con "per_n_levels"): cada cuántos niveles se
##       aplica el aumento.
##   unlock_cost: esquirlas para desbloquearlo en la selección; 0 = jugable
##       desde el inicio (ver el aviso de arriba). SaveData guarda los
##       desbloqueos; esto es solo el precio.
##   unlock_boss (opcional): secret_boss_id del minijefe oculto cuya muerte
##       regala el personaje sin esquirlas. SecretBossBase lo busca con
##       by_unlock_boss, así la relación vive aquí y no en el código del jefe.
##   unlock_hint (opcional): pista vaga para el camino del jefe, en la carta
##       bloqueada junto al precio.
##   tint: color de identidad del cuerpo (también la muestra de la carta).
##   model_scene (opcional): cuerpo cosmético de ESTE personaje, una escena
##       envoltorio (como foca_character.tscn) o un .glb crudo. Sin él, la
##       foca. La raíz del envoltorio puede llevar un script de caminata
##       (goku_walk_animation.gd, storm_cat_walk.gd) que mide cuánto se mueve
##       su nodo en cada tick de física, así las extremidades siguen el
##       movimiento real del jugador sin código por personaje.
##   model_scale (opcional): escala uniforme sobre la transformación propia
##       del modelo; las filas con .glb crudo declaran su tamaño (la foca usa
##       0.6) y los envoltorios traen el suyo. Ausente o <= 0 = sin reescalar.
##   tint_material_prefix (opcional): prefijo del resource_name de los
##       materiales teñibles de ESTE modelo; las superficies cuyo material no
##       lleva el prefijo no se tiñen. Ausente = "Azul personaje" de la foca.
## Texto que ve el jugador: display_name, blurb, passive_description y
## unlock_hint. El resto son identificadores.

## Personaje de respaldo cuando no hubo selección (arena arrancada directo).
const DEFAULT_ID: String = "caballerita"
>>>>>>> Stashed changes

const CHARACTER_LIBRARY: Array[Dictionary] = [
	{
<<<<<<< Updated upstream
		"id": "rook", "display_name": "Rook",
		"blurb": "Un muro con patas: sus golpes solo se ponen más feos.",
		"weapon_scene": "res://scenes/weapons/Shortsword.tscn",
		"weapon_node_name": "Shortsword",
		"weapon_display_name": "Espada corta",
		"passive_description": "+0.8% de daño por nivel",
		"passive_stat": "damage", "passive_amount": 0.8,
=======
		"id": "caballerita", "display_name": "Pequeña caballerita",
		"blurb": "No existe pastero mas duro que la pequeña caballerita.",
		"weapon_node_name": "Shortsword",
		"passive_description": "+0.5 de armadura por nivel",
		"passive_stat": "armor", "passive_amount": 0.5,
>>>>>>> Stashed changes
		"unlock_cost": 0,
		"tint": Color(0.35, 0.51, 0.74),
	},
	{
<<<<<<< Updated upstream
		"id": "ash", "display_name": "Ash",
		"blurb": "Un ermitaño cubierto de hollín cuyo fuego se abre más en cada nivel.",
		"weapon_scene": "res://scenes/weapons/EmberWand.tscn",
		"weapon_node_name": "EmberWand",
		"weapon_display_name": "Vara de brasas",
		"passive_description": "+0.7% de área por nivel",
		"passive_stat": "area", "passive_amount": 0.7,
		"unlock_cost": 0, # 50
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
=======
		"id": "fuego", "display_name": "Fuego",
		"blurb": "Del espacio le llego algo muy especial.",
		"weapon_node_name": "EmberWand",
		"passive_description": "+1.5% de área por nivel",
		"passive_stat": "area", "passive_amount": 1.5,
		"unlock_cost": 0,
		"model_scene": "res://assets/models/fuego_character.tscn",
		"tint": Color(0.89, 0.45, 0.18),
	},
	{
		"id": "ninja", "display_name": "Ninja",
		"blurb": "Pendiente.",
		# Pendiente: cambiar el arco de caza por kunais en WeaponCatalog y
		# apuntar weapon_node_name a esa fila nueva.
		"weapon_node_name": "HuntingBow",
		"passive_description": "+1.0% de velocidad de ataque por nivel",
		"passive_stat": "cooldown", "passive_amount": 1.0,
		"model_scene": "res://assets/models/yandere_character.tscn",
		"unlock_cost": 0,
		"tint": Color(0.24, 0.55, 0.32),
	},
	{
		"id": "meowl", "display_name": "Meowl",
		"blurb": "I'm a new soul, I came to this strange world hoping...",
>>>>>>> Stashed changes
		"weapon_node_name": "SpiritOrbs",
		"weapon_display_name": "Orbes espirituales",
		"passive_description": "+1.0% de xp por nivel",
<<<<<<< Updated upstream
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
=======
		"passive_stat": "xp_gain", "passive_amount": 1.0,
		"unlock_cost": 0,
		"tint": Color(0.55, 0.85, 0.95),
	},
	{
		"id": "electro_gato", "display_name": "Electro Gato",
		"blurb": "¿Cuantos gatos se necesitan para cambiar una bombilla?",
		"weapon_node_name": "StormRod",
		"passive_description": "+1.5 de suerte por nivel (cartas más raras)",
		"passive_stat": "luck", "passive_amount": 1.5,
>>>>>>> Stashed changes
		"model_scene": "res://assets/models/storm_cat_character.tscn",
		"unlock_cost": 0, # 130
		"tint": Color(0.35, 0.45, 0.85),
	},
	{
<<<<<<< Updated upstream
		"id": "doc", "display_name": "Doc",
		"blurb": "Un cirujano de campaña muy alegre que le cobra a cada paciente en sangre.",
		"weapon_scene": "res://scenes/weapons/BloodVial.tscn",
		"weapon_node_name": "BloodVial",
		"weapon_display_name": "Vial de sangre",
		"passive_description": "+1% de robo de vida por nivel (base +5%)",
		"passive_stat": "lifesteal", "passive_amount": 1.0,
		"passive_base": 5.0,
		"unlock_cost": 0, # 150
=======
		"id": "chupacabra", "display_name": "Chupacabras",
		"blurb": "Bart, no quiero asustarte pero creo que el chupacabras esta en el juego.",
		"weapon_node_name": "BloodVial",
		"passive_description": "+0.5% de robo de vida por nivel",
		"passive_stat": "lifesteal", "passive_amount": 0.5,
		"unlock_cost": 0,
>>>>>>> Stashed changes
		"tint": Color(0.72, 0.16, 0.2),
	},
	# Iteration 43 roster: the slime, stench and beam starters.
	{
<<<<<<< Updated upstream
		"id": "Moka", "display_name": "Moka",
		"blurb": "Una foca muy watona.",
		"weapon_scene": "res://scenes/weapons/SlimeTrail.tscn",
=======
		"id": "moka", "display_name": "Moka",
		"blurb": "Una foca muy watona, muy azul y muy foca.",
>>>>>>> Stashed changes
		"weapon_node_name": "SlimeTrail",
		"weapon_display_name": "Rastro de baba",
		"passive_description": "+2% de duración de efectos por nivel",
		"passive_stat": "duration", "passive_amount": 2.0,
		"unlock_cost": 0,
		"tint": Color(0.35, 0.45, 0.85),
	},
	{
<<<<<<< Updated upstream
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
=======
		"id": "barco_basurero", "display_name": "Bolsa de basura",
		"blurb": "Una bolsa de basura con patas.",
		"weapon_node_name": "Stench",
		"passive_description": "+0.5% de área y de duración por nivel",
		"passive_stat": "area", "passive_amount": 0.5,
		"passive_stat2": "duration", "passive_amount2": 0.5,
		"unlock_cost": 0,
		"tint": Color(0.6, 0.7, 0.3),
	},
	{
		"id": "goku", "display_name": "Goku",
		"blurb": "Kaaaaa meeeee haaaaaaa maaaaaaaa haaaaaaa!!!",
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
		"blurb": "Pega primero, pega dos veces y nunca pregunta nombres.",
		"weapon_scene": "res://scenes/weapons/TwinDaggers.tscn",
		"weapon_node_name": "TwinDaggers",
		"weapon_display_name": "Dagas gemelas",
		# Under Vex's 0.5 on purpose: the daggers swing far more often than
		# the pistol, so a point of crit is worth more per level here.
		"passive_description": "+0.4% de prob. de crítico por nivel",
		"passive_stat": "crit_chance", "passive_amount": 0.4,
=======
		"blurb": "Yupitaison",
		# Pendiente: renombrar el arma a "Guantes de boxeo" en WeaponCatalog.
		"weapon_node_name": "TwinDaggers",
		# Bajo a propósito: el arma golpea muy seguido, así que cada punto
		# de crítico rinde más por nivel.
		"passive_description": "+1.0% de prob. de crítico por nivel",
		"passive_stat": "crit_chance", "passive_amount": 1.0,
		"passive_base": 50.0,
>>>>>>> Stashed changes
		"unlock_cost": 0,
		"tint": Color(0.726, 0.299, 0.166, 1.0),
	},
	{
		"id": "gucci_morty", "display_name": "PNG gucci morty",
		"blurb": "Un recorte de baja resolución al que la suerte no deja de sonreírle.",
<<<<<<< Updated upstream
		"weapon_scene": "res://scenes/weapons/DartPistol.tscn",
		"weapon_node_name": "DartPistol",
		"weapon_display_name": "Pistola de dardos",
		# Torren keeps luck at 1.0 per level: a free starter matching him
		# would leave nothing to buy for his 130 esquirlas.
		"passive_description": "+0.6 de suerte por nivel",
		"passive_stat": "luck", "passive_amount": 0.6,
=======
		# Pendiente: renombrar el arma a "Pistola de portales" en WeaponCatalog.
		"weapon_node_name": "DartPistol",
		"passive_description": "+1 proyectil cada 3 niveles",
		"passive_stat": "projectiles", "passive_amount": 1.0,
		"passive_kind": "per_n_levels", "passive_every": 3,
>>>>>>> Stashed changes
		"model_scene": "res://assets/models/gucci_morty.tscn",
		"unlock_cost": 0,
		"tint": Color(0.92, 0.34, 0.62),
	},
	{
		"id": "backyardigan", "display_name": "Backyardigan",
<<<<<<< Updated upstream
		"blurb": "No corre, coreografía; y todo lo que roza se prende.",
		"weapon_scene": "res://scenes/weapons/Aura.tscn",
		"weapon_node_name": "Aura",
		"weapon_display_name": "Aura",
		# Move speed IS the Aura's damage stat: a ring that only burns what
		# it touches scales with how much ground the raider covers.
		"passive_description": "+0.8% de velocidad de movimiento por nivel",
		"passive_stat": "move_speed", "passive_amount": 0.8,
=======
		"blurb": "En nuestro patio hay un mundo por explorar...",
		"weapon_node_name": "Aura",
		"passive_description": "+2 de vida por nivel y +0.1% de daño por cada punto de vida máx.",
		"passive_stat": "max_hp", "passive_amount": 2.0,
		"passive_kind": "hp_to_damage", "passive_amount2": 0.1,
>>>>>>> Stashed changes
		"unlock_cost": 0,
		"model_scene": "res://assets/models/placeholder_character.tscn",
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
