class_name PetCatalog
extends RefCounted
## Catálogo de mascotas: compañeras inmortales que siguen al raider, llevan un
## arma propia (fuera del tope de armas y nunca en el pool de mejoras) y dan un
## stat que crece con el nivel de la incursión.
##
## UNA mascota a la vez: hay un solo espacio de compañera, así que una segunda
## REEMPLAZA a la primera (arma y stat cambian juntos, nada se apila) y repetir
## la misma no cambia nada. Por eso cada fila declara un arma Y un stat: una
## fila a medias haría del cambio una pérdida sin vuelta atrás. Las mascotas
## salen solo de la caja de mascotas (PetBox) y del traficante de animales
## (Vendor, tipo "animals"), siempre por elección del jugador.
##
## Se puede cambiar libremente: display_name, glyph, weapon_damage_scale,
## stat, amount_per_level, stat_label, shape, color, size, hover.
## Llave interna, NUNCA la cambies: id (el nodo de la mascota se llama
## "Pet_<id>").
## weapon_scene: el nombre del archivo sin .tscn debe ser el node_name de una
## fila de WEAPON_LIBRARY (StormRod.tscn -> "StormRod"); así se resuelve el
## nombre del arma que ve el jugador.
##
## Campos de cada fila:
##   id: llave interna (ver arriba). Nunca se muestra.
##   display_name: texto del jugador.
##   glyph: sigla de dos letras que dibuja el HUD mientras no hay ícono. Se
##       DECLARA (no se deriva del nombre) y no debe repetirse entre los glifos
##       de armas, evoluciones, tomos, objetos y power-ups.
##   weapon_scene: escena del arma que se instancia bajo la mascota.
##   weapon_damage_scale: daño del arma de la mascota respecto de la versión
##       del jugador (0-1).
##   stat, amount_per_level: efecto de PlayerStats que gana por cada nivel de
##       la incursión.
##   stat_label: texto del jugador; la caja de mascotas y el traficante lo
##       muestran en cada carta. Su número debe coincidir con amount_per_level.
##   shape, color, size: cuerpo hecho en código (sphere | capsule | box); size
##       en metros.
##   hover: altura sobre el suelo a la que flota la mascota, en metros.

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
	{
		"id": "doki", "display_name": "Doki", "glyph": "DK",
		"weapon_scene": "res://scenes/weapons/Boomerang.tscn", "weapon_damage_scale": 0.55,
		"stat": "xp_gain", "amount_per_level": 0.5, "stat_label": "ganancia de XP +0.5% por nivel",
		"shape": "capsule", "color": Color(0.95, 0.55, 0.2), "size": 0.42, "hover": 0.6,
	},
	{
		"id": "pony", "display_name": "Pony", "glyph": "PN",
		"weapon_scene": "res://scenes/weapons/HuntingBow.tscn", "weapon_damage_scale": 0.5,
		# Bajo a propósito: la velocidad también alimenta la pasiva
		# speed_to_damage de Yandere-chan, así que vale más de lo que se lee.
		"stat": "move_speed", "amount_per_level": 0.4, "stat_label": "velocidad +0.4% por nivel",
		"shape": "box", "color": Color(0.85, 0.7, 0.45), "size": 0.6, "hover": 0.55,
	},
	{
		"id": "cj7", "display_name": "Cj7", "glyph": "CJ",
		# Las armas siempre activas (Aura, Orbes espirituales) van al fondo de
		# la banda de escala: nunca pierden una ventana de ataque.
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


## Índice id -> fila armado al primer uso (ver CatalogIndex):
## PlayerStats.recompute() resuelve una fila por cada mascota que lo sigue.
static var _by_id: Dictionary[String, Dictionary] = {}


## Fila con ese id, o un Dictionary vacío si no existe.
static func by_id(pet_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(PET_LIBRARY)
	return _by_id.get(pet_id, {})


## Ids en el orden del catálogo.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in PET_LIBRARY:
		out.append(String(row.id))
	return out


## Nombre del arma de la mascota según el catálogo de armas. Sale del nombre
## del archivo de la escena, que es el node_name de WEAPON_LIBRARY
## (StormRod.tscn -> "StormRod"); el nodo vivo se llama "PetWeapon" y no sirve.
static func weapon_display_name(row: Dictionary) -> String:
	var scene := String(row.get("weapon_scene", ""))
	if scene.is_empty():
		return ""
	return WeaponCatalog.display_name_for_node(scene.get_file().get_basename())
