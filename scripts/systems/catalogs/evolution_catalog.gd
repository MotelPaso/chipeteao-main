class_name EvolutionCatalog
extends RefCounted
## Catálogo de evoluciones de arma: la receta que convierte un arma invertida
## en una forma con nombre propio y mucho más fuerte. Una evolución nueva es
## una fila aquí.
##
## Regla: cada carta de mejora invertida en un arma es un nivel de arma, y cada
## EVOLVE_AT_LEVEL niveles hay un HITO que corre try_advance_by_level (lo llama
## UpgradePool.apply). El primer hito evoluciona el arma si tiene receta aquí;
## cada hito siguiente, y el primero de un arma sin receta, es un ascenso
## (WeaponBase.ascend), así ninguna arma deja de mejorar. Los dos comparten la
## misma ceremonia (fanfarria, cartel, destello).
##
## Se puede cambiar libremente: evolved_name, glyph, mults, adds, flavor.
## Llaves internas, NUNCA las cambies: weapon_id y weapon_node (deben ser el id
## y el node_name de la fila del arma en WEAPON_LIBRARY).
##
## Campos de cada fila:
##   weapon_id, weapon_node: id y node_name del arma base en WEAPON_LIBRARY.
##       Nunca se muestran.
##   evolved_name: nombre nuevo, anunciado en el cartel y mostrado en Colección.
##   glyph: sigla de dos letras que dibuja la tira de armas del HUD mientras no
##       hay ícono. Se DECLARA, no se deriva de evolved_name: las iniciales de
##       los nombres en español chocan («Cáliz de peste» y «Corona de
##       tempestad» darían «CD»). No debe repetirse en esta biblioteca,
##       WEAPON_LIBRARY, TOME_LIBRARY ni ITEM_LIBRARY (la tira las mezcla).
##   mults: {propiedad: factor} que se multiplica sobre el nodo del arma al
##       evolucionar. La propiedad debe existir en la escena del arma.
##   adds: {propiedad: cantidad} que se suma sobre el nodo del arma al
##       evolucionar.
##   flavor: línea de Colección que describe lo que hace la forma evolucionada.
## Texto que ve el jugador: evolved_name y flavor.
## Guardado: la ceremonia suma "evo_<weapon_id>" y "evolutions_total" en
## SaveData; Colección y las misiones los leen.

## Cartas que un arma debe recibir (WeaponBase.upgrade_level) por hito: los
## primeros EVOLVE_AT_LEVEL niveles compran la evolución y cada múltiplo
## siguiente un ascenso. Es UN número a propósito: si el umbral de evolución y
## el período de ascenso se separaran, quedaría un tramo de niveles sin premio.
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
		"weapon_id": "necro_staff", "weapon_node": "NecroStaff",
		"evolved_name": "Corona del Rey Lich", "glyph": "CN",
		"mults": {"damage": 1.6},
		"adds": {"possess_duration": 4.0, "max_possessed": 6},
		"flavor": "un ejército que ya no cabe en el campo",
	},
	{
		"weapon_id": "storm_rod", "weapon_node": "StormRod",
		"evolved_name": "Corona de tempestad", "glyph": "CT",
		"mults": {"damage": 1.7},
		"adds": {"chain_count": 3},
		"flavor": "rayos que se bifurcan hasta que no queda nada en pie",
	},
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


## Índices armados al primer uso (ver CatalogIndex): Colección resuelve una
## receta por cada fila de arma que dibuja.
static var _by_weapon_id: Dictionary[String, Dictionary] = {}
static var _by_weapon_node: Dictionary[String, Dictionary] = {}


## Fila del arma base con ese id, o un Dictionary vacío si no tiene receta.
static func by_weapon_id(weapon_id: String) -> Dictionary:
	if _by_weapon_id.is_empty():
		_by_weapon_id = CatalogIndex.build(EVOLUTION_LIBRARY, "weapon_id")
	return _by_weapon_id.get(weapon_id, {})


## Fila de un arma viva (por el nombre de su nodo en el montaje), o vacío.
static func by_weapon_node(node_name: String) -> Dictionary:
	if _by_weapon_node.is_empty():
		_by_weapon_node = CatalogIndex.build(EVOLUTION_LIBRARY, "weapon_node")
	return _by_weapon_node.get(node_name, {})


## Corre el hito que `weapon` acaba de alcanzar, si hay uno: la evolución en
## el primero (si hay receta) y un ascenso en cada uno de los siguientes y en
## el primero de un arma sin receta. Aplica el cambio, corre la ceremonia
## (fanfarria, cartel, destello sobre quien la lleva, sacudida), suma los
## contadores de Colección y misiones e imprime la línea de log del soak.
## Devuelve true cuando hubo hito.
static func try_advance_by_level(weapon: WeaponBase, player: Node) -> bool:
	if weapon == null:
		return false
	# División entera: los niveles 10-19 son el escalón 1, 20-29 el 2, etc.
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
			# Línea de log de formato fijo para los soaks headless.
			print("Weapon evolved: %s -> %s" % [String(row.weapon_id), weapon.evolved_name])
			return true
	weapon.ascend(tier)
	_celebrate(player)
	_announce("¡%s asciende!" % weapon_display(weapon))
	print("Weapon ascended: %s tier %d"
			% [WeaponCatalog.id_for_node(weapon.name), tier])
	return true


## Nombre que usa el cartel de un hito: la forma evolucionada si el arma ya
## la tiene, si no su display_name de WEAPON_LIBRARY. Nunca el id interno.
static func weapon_display(weapon: WeaponBase) -> String:
	if weapon.evolved and not weapon.evolved_name.is_empty():
		return weapon.evolved_name
	return WeaponCatalog.display_name_for_node(weapon.name)


## Celebración común de evoluciones y ascensos: fanfarria, destello sobre
## quien lleva el arma y sacudida de cámara. Los autoloads se buscan con
## AutoloadLookup: un harness `-s` no los tiene y debe seguir sin ellos en
## vez de abortar.
static func _celebrate(player: Node) -> void:
	var sfx := AutoloadLookup.find(&"Sfx")
	if sfx != null:
		sfx.play(&"secret_fanfare")
	var juice := AutoloadLookup.find(&"Juice")
	if juice != null:
		if player is Node3D:
			juice.sparkle((player as Node3D).global_position + Vector3.UP * 1.2)
		juice.shake(0.25, 0.5)


## El cartel grande, por el grupo "boss_ui" (announce_major).
static func _announce(message: String) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	loop.call_group("boss_ui", "announce_major", message)


## Contadores de Colección y misiones de una evolución (los ascensos no
## tienen contadores propios).
static func _record_evolution(weapon_id: String) -> void:
	var save_data := AutoloadLookup.find(&"SaveData")
	if save_data != null:
		save_data.bump("evo_" + weapon_id)
		save_data.bump("evolutions_total")
