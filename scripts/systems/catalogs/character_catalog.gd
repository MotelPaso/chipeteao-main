class_name CharacterCatalog
extends RefCounted
## Catálogo de personajes jugables: cada fila une un arma inicial con una
## pasiva que escala por nivel. Un personaje nuevo es una fila nueva aquí; la
## pantalla de selección y el spawn del jugador leen las filas, no hay código
## por personaje.
##
## Se puede cambiar libremente: display_name, blurb, passive_*, unlock_cost,
## tint, model_*.
## Llave interna, NUNCA la cambies: id (es la llave del guardado y de las
## misiones; usa minúsculas y guiones bajos). Si de verdad hay que
## renombrarlo, agrega la fila viejo -> nuevo en SaveData.ID_ALIASES para que
## los guardados existentes no pierdan el personaje ni sus contadores.
## Cuidado con unlock_cost: poner 0 lo deja gratis para siempre en los
## guardados existentes. SaveData agrega cada personaje gratis al guardado al
## cargarlo, y volver a ponerle precio después no lo bloquea de nuevo.
## weapon_node_name debe ser el node_name de una fila de WEAPON_LIBRARY.
##
## Campos de cada fila:
##   id: llave interna (ver arriba). SaveData guarda los desbloqueos por id y
##       cuenta runs_as_<id> / wins_as_<id>; las misiones nombran esos
##       contadores.
##   display_name, blurb: nombre y frase de la carta de selección.
##   weapon_scene: escena del arma inicial, instanciada bajo el montaje
##       Weapons del jugador.
##   weapon_node_name: nombre del nodo del arma inicial; debe ser el node_name
##       de su fila en WEAPON_LIBRARY para que el pool de mejoras la cuente
##       como poseída.
##   weapon_display_name: nombre del arma en la carta de selección.
##   passive_description: texto de la pasiva en la carta; sus números deben
##       coincidir con passive_amount y passive_base.
##   passive_stat, passive_amount: efecto de la pasiva como dato, un stat de
##       PlayerStats._apply_effect y lo que gana por cada nivel después del 1
##       (porcentaje en los stats multiplicadores).
##   passive_kind (opcional, "per_level" por defecto): cómo la aplica
##       PlayerStats. "per_level" escala con el nivel de la incursión;
##       "speed_to_damage" convierte la velocidad de movimiento extra en daño
##       extra a razón de passive_amount (passive_stat no se usa);
##       "evasion_execute" escala por nivel y además cada esquive ejecuta a un
##       atacante debilitado que no sea jefe.
##   passive_base (opcional, 0 por defecto): cantidad que ya da en el nivel 1,
##       antes de los aumentos por nivel.
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
## Texto que ve el jugador: display_name, blurb, weapon_display_name,
## passive_description y unlock_hint. El resto son identificadores.

## Personaje de respaldo cuando no hubo selección (arena arrancada directo).
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
		"unlock_cost": 0,
		"model_scene": "res://assets/models/fuego_character.tscn",
		"tint": Color(0.89, 0.45, 0.18),
	},
	{
		"id": "yandere_chan", "display_name": "Yandere-chan",
		"blurb": "Termina tu juego yandere-dev.",
		"weapon_scene": "res://scenes/weapons/HuntingBow.tscn",
		"weapon_node_name": "HuntingBow",
		"weapon_display_name": "Arco de caza",
		"passive_description": "+0.6% de daño por cada 1% de velocidad extra",
		"passive_stat": "damage", "passive_amount": 0.6,
		"model_scene": "res://assets/models/yandere_character.tscn",
		"passive_kind": "speed_to_damage",
		"unlock_cost": 0,
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
		"unlock_cost": 0,
		"tint": Color(0.55, 0.85, 0.95),
	},
	{
		"id": "electro_gato", "display_name": "Electro Gato",
		"blurb": "Un cazatormentas cuya suerte se lee como un parte del clima.",
		"weapon_scene": "res://scenes/weapons/StormRod.tscn",
		"weapon_node_name": "StormRod",
		"weapon_display_name": "Pararrayos",
		"passive_description": "+1 de suerte por nivel (cartas más raras)",
		"passive_stat": "luck", "passive_amount": 1.0,
		"model_scene": "res://assets/models/storm_cat_character.tscn",
		"unlock_cost": 0,
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
		"unlock_cost": 0,
		"tint": Color(0.72, 0.16, 0.2),
	},
	{
		"id": "moka", "display_name": "Moka",
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
		"id": "goku", "display_name": "Goku",
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
	# Los display_name de las tres filas siguientes son palabras textuales del
	# equipo: no se traducen ni se pasan a caja de oración (GLOSARIO, regla 5).
	{
		"id": "boxer", "display_name": "Boxeador",
		"blurb": "Pega primero, pega dos veces y nunca pregunta nombres.",
		"weapon_scene": "res://scenes/weapons/TwinDaggers.tscn",
		"weapon_node_name": "TwinDaggers",
		"weapon_display_name": "Dagas gemelas",
		# Bajo a propósito: las dagas golpean muy seguido, así que cada punto
		# de crítico rinde más por nivel.
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
		# Menos suerte por nivel que Electro Gato (1.0) a propósito.
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
		# La velocidad ES el stat de daño del Aura: un anillo que solo quema
		# lo que toca rinde según cuánto terreno cubre el raider.
		"passive_description": "+0.8% de velocidad de movimiento por nivel",
		"passive_stat": "move_speed", "passive_amount": 0.8,
		"unlock_cost": 0,
		"model_scene": "res://assets/models/tyrone_character.tscn",
		"tint_material_prefix": "Placeholder personaje",
		"tint": Color(0.14, 0.62, 0.6),
	},
]


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
