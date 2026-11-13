class_name CollectionEntries
extends RefCounted
## Datos de la Colección: convierte las filas de los catálogos (raiders,
## bestiario, mapas, objetos, tomos, armas) en «entradas» con la misma forma,
## para que la carta y el detalle de la Colección las dibujen sin saber de qué
## catálogo vienen. No guarda nada: solo lee los catálogos y los contadores de
## SaveData.
##
## Forma de una entrada (Dictionary):
##   id: String        llave única dentro de su categoría.
##   name: String      nombre en pantalla ("???" si está sin descubrir).
##   locked: bool      sin descubrir: la carta muestra candado o silueta.
##   tint: Color       color de identidad (fondo del dibujo, borde del detalle).
##   caption: String   línea corta bajo el nombre (arma, rareza, tipo).
##   body: String      descripción; en una entrada sin descubrir, la pista.
##   lines: Array      filas {stat, text}: `stat` elige el icono (vacío = sin
##                     icono) y `text` es lo que se lee.
##   art: String       qué dibujo lleva: ART_RAIDER, ART_ENEMY, ART_MAP,
##                     ART_ICON o ART_GLYPH.
##   row / scene / palette / icon / glyph: lo que necesita ese dibujo.
##
## De dónde sale «descubierto» (contadores de SaveData, guardados al cerrar la
## partida):
##   raiders: SaveData.is_unlocked     enemigos: kills_<script>
##   mapas:   runs_on_<id>             objetos:  item_<id>
##   armas:   used_weapon_<id>         evoluciones: evo_<weapon_id>
##   tomos:   no hay contador en el guardado, así que se muestran todos.
##
## Es estático y nunca va en una escena: edita los valores aquí.

## Ids de categoría (los usan las tarjetas del submenú y CollectionBrowser).
const RAIDERS := "raiders"
const ENEMIES := "enemies"
const MAPS := "maps"
const ITEMS := "items"
const TOMES := "tomes"
const WEAPONS := "weapons"
const CATEGORY_IDS: Array[String] = [RAIDERS, ENEMIES, MAPS, ITEMS, TOMES, WEAPONS]

## Tipos de dibujo de una entrada.
const ART_RAIDER := "raider"
const ART_ENEMY := "enemy"
const ART_MAP := "map"
const ART_ICON := "icon"
const ART_GLYPH := "glyph"

## Edita aquí: título de cada categoría en la pantalla de la cuadrícula.
const CATEGORY_TITLES: Dictionary[String, String] = {
	RAIDERS: "PERSONAJES",
	ENEMIES: "ENEMIGOS",
	MAPS: "MAPAS",
	ITEMS: "OBJETOS",
	TOMES: "TOMOS",
	WEAPONS: "ARMAS",
}

## Edita aquí: filas del bestiario, en el orden en que aparecen.
##
## | campo        | regla                                                  |
## |--------------|--------------------------------------------------------|
## | id           | nombre del archivo del script del enemigo, sin ".gd"   |
## |              | (scripts/enemies/<id>.gd): EnemyBase suma kills_<id> al |
## |              | morir. Un id que no calce nunca se descubre. Su escena |
## |              | es scenes/enemies/<IdEnPascalCase>.tscn: de ahí salen  |
## |              | el cuerpo 3D (nodo Visual) y las estadísticas.         |
## | display_name | nombre en pantalla; en los jefes copia el boss_title de |
## |              | su escena (Rotking, Mythos, Sarcognath, Fenwraith,     |
## |              | Grubthing, CofferMimic .tscn): si cambias uno, cambia  |
## |              | el otro.                                               |
## | flavor       | texto corto bajo el nombre.                            |
## | tint         | color del fondo de su carta.                           |
const BESTIARY: Array[Dictionary] = [
	{"id": "grunt", "display_name": "Esbirro", "flavor": "la marea misma",
		"tint": Color(0.55, 0.3, 0.3)},
	{"id": "skirmisher", "display_name": "Hostigador",
		"flavor": "guarda distancia y lanza saetas", "tint": Color(0.4, 0.34, 0.6)},
	{"id": "tank", "display_name": "Mole", "flavor": "acorazado, lento, implacable",
		"tint": Color(0.36, 0.42, 0.5)},
	{"id": "sunspitter", "display_name": "Escupesol",
		"flavor": "artillería láser a línea de visión", "tint": Color(0.7, 0.5, 0.25)},
	{"id": "duneburrower", "display_name": "Excavadunas", "flavor": "embosca desde abajo",
		"tint": Color(0.62, 0.48, 0.32)},
	{"id": "rotking", "display_name": "Rey Pútrido", "flavor": "jefe del Bosque Hueco",
		"tint": Color(0.3, 0.46, 0.3)},
	{"id": "mythos", "display_name": "Mythos",
		"flavor": "el fénix que incendia el Bosque Hueco", "tint": Color(0.62, 0.24, 0.14)},
	{"id": "sarcognath", "display_name": "Sarcognato", "flavor": "jefe de las Dunas de Ceniza",
		"tint": Color(0.68, 0.4, 0.28)},
	{"id": "fenwraith", "display_name": "Espectro de la Ciénaga",
		"flavor": "jefe de la Ciénaga Lóbrega", "tint": Color(0.2, 0.4, 0.36)},
	{"id": "grubthing", "display_name": "Larvón", "flavor": "lo que duerme bajo el bosque",
		"tint": Color(0.5, 0.4, 0.3)},
	{"id": "coffer_mimic", "display_name": "Cofre Mímico",
		"flavor": "la cosa sepulcral de las dunas", "tint": Color(0.5, 0.36, 0.2)},
]
## Carpeta de las escenas de enemigo (ver la regla de `id` arriba).
const ENEMY_SCENE_FORMAT := "res://scenes/enemies/%s.tscn"

## Edita aquí: textos de las entradas.
## Nombre de cualquier entrada sin descubrir.
const UNKNOWN_NAME := "???"
## Pistas de las entradas sin descubrir, por categoría.
const HIDDEN_RAIDER := "Un raider que sigue allá afuera..."
const HIDDEN_ENEMY := "Algo que aún no enfrentas..."
const HIDDEN_MAP := "Un lugar que todavía no pisas..."
const HIDDEN_ITEM := "Un objeto que ningún cofre te ha dado..."
const HIDDEN_WEAPON := "Un arma sin reclamar..."
## Pista de una evolución sin descubrir de un arma ya llevada (%d = nivel).
const EVO_HINT_FORMAT := "Sube el arma al nivel %d para evolucionarla."
## Pista de una evolución sin descubrir de un arma nunca llevada.
const EVO_UNKNOWN := "Una forma evolucionada te espera."
## Líneas del detalle. Cada %s o %d se llena con el dato del catálogo.
const RAIDER_WEAPON_FORMAT := "Arma: %s"
const RAIDER_RUNS_FORMAT := "Incursiones: %d · Victorias: %d"
const ENEMY_HP_FORMAT := "HP base: %d"
const ENEMY_SPEED_FORMAT := "Velocidad: %s"
const ENEMY_DAMAGE_FORMAT := "Daño por contacto: %d"
const ENEMY_KILLS_FORMAT := "Abatidos: %d"
const ENEMY_CAPTION := "Enemigo"
const BOSS_CAPTION := "Jefe"
const MAP_CAPTION_FORMAT := "Etapa %d de la incursión"
const MAP_RUNS_FORMAT := "Incursiones: %d"
const MAP_WINS_FORMAT := "Victorias: %d"
const ITEM_CAPTION_FORMAT := "Objeto %s"
const ITEM_COUNT_FORMAT := "Recogido %d veces"
const TOME_CAPTION := "Tomo · sube con cada copia"
const WEAPON_CAPTION := "Arma"
const EVO_CAPTION_FORMAT := "Evolución de %s (Nv %d)"
## Colores de identidad de las categorías sin color propio en su catálogo.
const TOME_TINT := Color(0.3, 0.5, 0.68)
const WEAPON_TINT := Color(0.26, 0.5, 0.6)
const EVO_TINT := Color(0.72, 0.5, 0.16)
const LOCKED_TINT := Color(0.09, 0.2, 0.23)

## Estadísticas leídas de cada escena de enemigo, por ruta (no cambian en la
## sesión).
static var _enemy_stats: Dictionary[String, Dictionary] = {}


## Todas las entradas de esa categoría, en el orden de su catálogo.
static func entries(category: String) -> Array[Dictionary]:
	match category:
		RAIDERS:
			return _raiders()
		ENEMIES:
			return _enemies()
		MAPS:
			return _maps()
		ITEMS:
			return _items()
		TOMES:
			return _tomes()
		WEAPONS:
			return _weapons()
	return []


## Descubiertas y total de esa categoría, como (x = descubiertas, y = total).
static func progress(category: String) -> Vector2i:
	var found := 0
	var rows := entries(category)
	for entry: Dictionary in rows:
		if not bool(entry.locked):
			found += 1
	return Vector2i(found, rows.size())


## Ruta de la escena del enemigo con ese id del bestiario, o "" si no existe.
static func enemy_scene(enemy_id: String) -> String:
	var path := ENEMY_SCENE_FORMAT % enemy_id.to_pascal_case()
	return path if ResourceLoader.exists(path, "PackedScene") else ""


static func _entry(id: String, display_name: String, locked: bool, tint: Color,
		art: String) -> Dictionary:
	return {
		"id": id, "name": UNKNOWN_NAME if locked else display_name, "locked": locked,
		"tint": LOCKED_TINT if locked else tint, "caption": "", "body": "",
		"lines": [] as Array[Dictionary], "art": art,
	}


static func _line(stat: String, text: String) -> Dictionary:
	return {"stat": stat, "text": text}


static func _raiders() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		var id := String(row.id)
		var locked := not SaveData.is_unlocked(id)
		var entry := _entry(id, String(row.display_name), locked, Color(row.tint), ART_RAIDER)
		entry["row"] = row
		if locked:
			entry.body = HIDDEN_RAIDER
		else:
			entry.caption = RAIDER_WEAPON_FORMAT % String(row.weapon_display_name)
			entry.body = String(row.get("blurb", ""))
			entry.lines.append(_line(String(row.get("passive_stat", "")),
					String(row.passive_description)))
			entry.lines.append(_line("", RAIDER_RUNS_FORMAT % [
					SaveData.stat("runs_as_" + id), SaveData.stat("wins_as_" + id)]))
		out.append(entry)
	return out


static func _enemies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for beast: Dictionary in BESTIARY:
		var id := String(beast.id)
		var kills := SaveData.stat("kills_" + id)
		var locked := kills <= 0
		var entry := _entry(id, String(beast.display_name), locked,
				Color(beast.get("tint", WEAPON_TINT)), ART_ENEMY)
		entry["scene"] = enemy_scene(id)
		if locked:
			entry.body = HIDDEN_ENEMY
		else:
			var stats := _read_enemy_stats(String(entry.scene))
			entry.caption = BOSS_CAPTION if bool(stats.get("boss", false)) else ENEMY_CAPTION
			entry.body = _sentence(String(beast.flavor))
			if stats.has("max_hp"):
				entry.lines.append(_line("max_hp", ENEMY_HP_FORMAT % roundi(stats.max_hp)))
			if stats.has("move_speed"):
				entry.lines.append(_line("move_speed",
						ENEMY_SPEED_FORMAT % String.num(stats.move_speed, 1)))
			if stats.has("contact_damage"):
				entry.lines.append(_line("damage",
						ENEMY_DAMAGE_FORMAT % roundi(stats.contact_damage)))
			entry.lines.append(_line("", ENEMY_KILLS_FORMAT % kills))
		out.append(entry)
	return out


static func _maps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in MapCatalog.MAP_LIBRARY.size():
		var row := MapCatalog.MAP_LIBRARY[i]
		var id := String(row.id)
		var runs := SaveData.stat("runs_on_" + id)
		var palette: Array = row.get("palette", [])
		var tint: Color = palette[0] if not palette.is_empty() else WEAPON_TINT
		var entry := _entry(id, String(row.display_name), runs <= 0, tint, ART_MAP)
		entry["palette"] = palette
		if runs <= 0:
			entry.body = HIDDEN_MAP
		else:
			entry.caption = MAP_CAPTION_FORMAT % (i + 1)
			entry.body = String(row.get("blurb", ""))
			entry.lines.append(_line("", MAP_RUNS_FORMAT % runs))
			entry.lines.append(_line("", MAP_WINS_FORMAT % SaveData.stat("victories_" + id)))
		out.append(entry)
	return out


static func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Dictionary in ItemCatalog.ITEM_LIBRARY:
		var row := RowText.render(raw)
		var id := String(row.id)
		var count := SaveData.stat("item_" + id)
		var rarity := String(row.get("rarity", ""))
		var entry := _entry(id, String(row.display_name), count <= 0,
				_rarity_color(rarity), ART_ICON)
		entry["icon"] = ItemIcons.texture(row)
		entry["glyph"] = String(row.get("glyph", ""))
		if count <= 0:
			entry.body = HIDDEN_ITEM
		else:
			entry.caption = ITEM_CAPTION_FORMAT % Rarity.display_name(rarity).to_lower()
			entry.body = String(row.get("description", ""))
			_append_stat_lines(entry, row)
			entry.lines.append(_line("", ITEM_COUNT_FORMAT % count))
		out.append(entry)
	return out


static func _tomes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in Tome.TOME_LIBRARY:
		var entry := _entry(String(row.id), String(row.display_name), false, TOME_TINT, ART_ICON)
		entry["icon"] = ItemIcons.texture(row)
		entry["glyph"] = String(row.get("glyph", ""))
		entry.caption = TOME_CAPTION
		entry.body = _tome_text(row)
		_append_stat_lines(entry, row)
		out.append(entry)
	return out


static func _weapons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for weapon: Dictionary in UpgradePool.WEAPON_LIBRARY:
		var id := String(weapon.id)
		var carried := SaveData.stat("used_weapon_" + id) > 0
		var entry := _entry(id, String(weapon.display_name), not carried, WEAPON_TINT, ART_GLYPH)
		entry["glyph"] = String(weapon.get("glyph", ""))
		entry.caption = "" if not carried else WEAPON_CAPTION
		entry.body = _sentence(String(weapon.get("flavor", ""))) if carried else HIDDEN_WEAPON
		out.append(entry)
		var recipe := EvolutionCatalog.by_weapon_id(id)
		if recipe.is_empty():
			continue
		var evolved := SaveData.stat("evo_" + id) > 0
		var evo := _entry("evo_" + id, String(recipe.evolved_name), not evolved, EVO_TINT,
				ART_GLYPH)
		evo["glyph"] = String(recipe.get("glyph", ""))
		if evolved:
			evo.caption = EVO_CAPTION_FORMAT % [String(weapon.display_name),
					EvolutionCatalog.EVOLVE_AT_LEVEL]
			evo.body = _sentence(String(recipe.get("flavor", "")))
		elif carried:
			evo.body = EVO_HINT_FORMAT % EvolutionCatalog.EVOLVE_AT_LEVEL
		else:
			evo.body = EVO_UNKNOWN
		out.append(evo)
	return out


## Una línea con icono por cada stat principal de la fila (hasta 2).
static func _append_stat_lines(entry: Dictionary, row: Dictionary) -> void:
	for stat: String in StatIcons.main_stats(row.get("effects", []), 2):
		entry.lines.append(_line(stat, StatIcons.label(stat)))


## Texto de un tomo con su número a potencia Común (el amount del primer
## efecto), igual que la primera carta que se ofrece. Protegido: una fila sin
## %d se muestra tal cual.
static func _tome_text(row: Dictionary) -> String:
	var template := String(row.get("description", ""))
	if not template.contains("%d"):
		return template.replace("%%", "%")
	return template % roundi(RowText.value_of(row, "amount"))


static func _rarity_color(rarity: String) -> Color:
	for tier: Dictionary in Rarity.TIERS:
		if String(tier.name) == rarity:
			return Color(tier.color).darkened(0.25)
	return WEAPON_TINT


## El texto con mayúscula inicial y punto final, para los flavor en minúscula
## del catálogo.
static func _sentence(text: String) -> String:
	if text.is_empty():
		return text
	var out := text.left(1).to_upper() + text.substr(1)
	return out if out.ends_with(".") or out.ends_with("!") or out.ends_with("?") else out + "."


## HP, velocidad, daño por contacto y si es jefe, leídos de la escena del
## enemigo sin meterla al árbol (su IA nunca corre). Un dato que la escena no
## tiene simplemente no aparece.
static func _read_enemy_stats(scene_path: String) -> Dictionary:
	if scene_path.is_empty():
		return {}
	if _enemy_stats.has(scene_path):
		return _enemy_stats[scene_path]
	var stats: Dictionary = {}
	var scene := load(scene_path) as PackedScene
	var body: Node = scene.instantiate() if scene != null else null
	if body != null:
		for field: String in ["move_speed", "contact_damage"]:
			var value: Variant = body.get(field)
			if value is float or value is int:
				stats[field] = float(value)
		stats["boss"] = not String(body.get("boss_title")).is_empty() \
				if body.get("boss_title") != null else false
		var health := body.get_node_or_null("Health")
		if health != null and health.get("max_hp") != null:
			stats["max_hp"] = float(health.get("max_hp"))
		body.free()
	_enemy_stats[scene_path] = stats
	return stats
