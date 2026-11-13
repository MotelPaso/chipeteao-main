class_name CharacterCatalog
extends RefCounted
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

## Filas como se editan (ver la cabecera). El juego lee CHARACTER_LIBRARY, que
## es esta lista con weapon_scene y weapon_display_name agregados.
const CHARACTER_ROWS: Array[Dictionary] = [
	{
		"id": "caballerita", "display_name": "Pequeña caballerita",
		"blurb": "No existe pastero mas duro que la pequeña caballerita.",
		"weapon_node_name": "Shortsword",
		"passive_description": "+0.5 de armadura por nivel",
		"passive_stat": "armor", "passive_amount": 0.5,
		"unlock_cost": 0,
		"tint": Color(0.35, 0.51, 0.74),
	},
	{
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
		"weapon_node_name": "SpiritOrbs",
		"passive_description": "+1.0% de xp por nivel",
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
		"model_scene": "res://assets/models/storm_cat_character.tscn",
		"unlock_cost": 0,
		"tint": Color(0.35, 0.45, 0.85),
	},
	{
		"id": "chupacabra", "display_name": "Chupacabras",
		"blurb": "Bart, no quiero asustarte pero creo que el chupacabras esta en el juego.",
		"weapon_node_name": "BloodVial",
		"passive_description": "+0.5% de robo de vida por nivel",
		"passive_stat": "lifesteal", "passive_amount": 0.5,
		"unlock_cost": 0,
		"tint": Color(0.72, 0.16, 0.2),
	},
	{
		"id": "moka", "display_name": "Moka",
		"blurb": "Una foca muy watona, muy azul y muy foca.",
		"weapon_node_name": "SlimeTrail",
		"passive_description": "+2% de duración de efectos por nivel",
		"passive_stat": "duration", "passive_amount": 2.0,
		"unlock_cost": 0,
		"tint": Color(0.35, 0.45, 0.85),
	},
	{
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
		"weapon_node_name": "Kamehameha",
		"passive_description": "+1% de daño por nivel",
		"passive_stat": "damage", "passive_amount": 1.0,
		"model_scene": "res://assets/models/goku_character.tscn",
		"unlock_cost": 0,
		"tint": Color(0.4, 0.7, 1.0),
	},
	# Los display_name de las tres filas siguientes son palabras textuales del
	# equipo: no se traducen ni se pasan a caja de oración (GLOSARIO, regla 5).
	{
		"id": "boxer", "display_name": "Boxeador",
		"blurb": "Yupitaison",
		# Pendiente: renombrar el arma a "Guantes de boxeo" en WeaponCatalog.
		"weapon_node_name": "TwinDaggers",
		# Bajo a propósito: el arma golpea muy seguido, así que cada punto
		# de crítico rinde más por nivel.
		"passive_description": "+1.0% de prob. de crítico por nivel",
		"passive_stat": "crit_chance", "passive_amount": 1.0,
		"passive_base": 50.0,
		"unlock_cost": 0,
		"tint": Color(0.726, 0.299, 0.166, 1.0),
	},
	{
		"id": "gucci_morty", "display_name": "PNG gucci morty",
		"blurb": "Un recorte de baja resolución al que la suerte no deja de sonreírle.",
		# Pendiente: renombrar el arma a "Pistola de portales" en WeaponCatalog.
		"weapon_node_name": "DartPistol",
		"passive_description": "+1 proyectil cada 3 niveles",
		"passive_stat": "projectiles", "passive_amount": 1.0,
		"passive_kind": "per_n_levels", "passive_every": 3,
		"model_scene": "res://assets/models/gucci_morty.tscn",
		"unlock_cost": 0,
		"tint": Color(0.92, 0.34, 0.62),
	},
	{
		"id": "backyardigan", "display_name": "Backyardigan",
		"blurb": "En nuestro patio hay un mundo por explorar...",
		"weapon_node_name": "Aura",
		"passive_description": "+2 de vida por nivel y +0.1% de daño por cada punto de vida máx.",
		"passive_stat": "max_hp", "passive_amount": 2.0,
		"passive_kind": "hp_to_damage", "passive_amount2": 0.1,
		"unlock_cost": 0,
		"model_scene": "res://assets/models/tyrone_character.tscn",
		"tint_material_prefix": "Placeholder personaje",
		"tint": Color(0.14, 0.62, 0.6),
	},
]


## Filas listas para el juego: CHARACTER_ROWS más weapon_scene y
## weapon_display_name, copiados de la fila de WeaponCatalog cuyo node_name es
## el weapon_node_name del personaje. Se arma una vez al cargar el script y es
## de solo lectura, como una const.
static var CHARACTER_LIBRARY: Array[Dictionary] = _with_weapon_fields(CHARACTER_ROWS)

## Índices armados al primer uso (ver CatalogIndex): la selección resuelve
## una fila por carta en cada redibujo y el spawn una por raider.
static var _by_id: Dictionary[String, Dictionary] = {}
static var _by_unlock_boss: Dictionary[String, Dictionary] = {}


## Fila con ese id, o un Dictionary vacío si no existe.
static func by_id(character_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(CHARACTER_LIBRARY)
	return _by_id.get(character_id, {})


## Fila con ese id, o la del personaje por defecto, así el spawn siempre
## recibe un equipo válido (por ejemplo, con un id viejo o mal escrito).
static func by_id_or_default(character_id: String) -> Dictionary:
	var row := by_id(character_id)
	return row if not row.is_empty() else by_id(DEFAULT_ID)


## Fila cuyo unlock_boss nombra ese minijefe oculto, o un Dictionary vacío
## si ningún personaje se desbloquea con él.
static func by_unlock_boss(boss_id: String) -> Dictionary:
	if boss_id.is_empty():
		return {}
	if _by_unlock_boss.is_empty():
		_by_unlock_boss = CatalogIndex.build(CHARACTER_LIBRARY, "unlock_boss")
	return _by_unlock_boss.get(boss_id, {})


## Ids jugables desde el inicio (unlock_cost 0). SaveData arma con esta
## lista los desbloqueos de un guardado nuevo y la agrega a cada guardado al
## cargarlo.
static func starter_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in CHARACTER_LIBRARY:
		if int(row.get("unlock_cost", 0)) == 0:
			ids.append(String(row.id))
	return ids


## Copia de `rows` donde cada fila suma weapon_scene y weapon_display_name de
## su arma en WeaponCatalog. Filas y lista quedan de solo lectura. Un
## weapon_node_name que no existe deja los dos campos vacíos y avisa.
static func _with_weapon_fields(rows: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		var full := row.duplicate(true)
		var weapon := _weapon_row(String(row.get("weapon_node_name", "")))
		if weapon.is_empty():
			push_warning("CharacterCatalog: weapon_node_name '%s' of '%s' is in no WeaponCatalog row"
					% [String(row.get("weapon_node_name", "")), String(row.get("id", "?"))])
		full["weapon_scene"] = String(weapon.get("scene", ""))
		full["weapon_display_name"] = String(weapon.get("display_name", ""))
		full.make_read_only()
		out.append(full)
	out.make_read_only()
	return out


## Fila de WeaponCatalog con ese node_name, o vacío. Recorre la const
## directamente porque corre al cargar este script.
static func _weapon_row(node_name: String) -> Dictionary:
	for weapon: Dictionary in WeaponCatalog.WEAPON_LIBRARY:
		if String(weapon.node_name) == node_name:
			return weapon
	return {}
