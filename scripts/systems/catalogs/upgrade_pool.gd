class_name UpgradePool
extends RefCounted
## Pool de mejoras de subida de nivel, con rareza ponderada. Cada elección de
## NIVEL sortea UN lado del pool, nunca una mezcla: armas (cartas de stats de
## las armas que se tienen + cartas new_weapon) o tomos/stats (cartas de tomo +
## GENERIC_POOL). roll_side() elige el lado 50-50 (WEAPON_SIDE_CHANCE), sin
## repetir el mismo lado más de MAX_SAME_SIDE_STREAK veces seguidas, y nunca
## devuelve uno vacío; la UI de cartas lo nombra en el
## título. Las elecciones extra (open_bonus_pick, hoy el Altar de codicia) no pasan lado y mezclan todo.
## El pool se arma de nuevo en cada tirada con:
##   - GENERIC_POOL: ajustes de player/health/run_state, siempre disponibles.
##   - Cartas de tomo (Tome.TOME_LIBRARY): el siguiente stack de cada tomo que
##     el jugador aún puede tomar; aplicarla suma un stack en PlayerStats.
##   - UNA carta de stats por cada arma QUE SE TIENE. Cada carta lleva de 1 a
##     STAT_COUNT_WEIGHTS.size() stats distintas, elegidas al azar entre las que
##     figuran en WEAPON_UPGRADE_STATS para esa arma Y cuya propiedad existe de
##     verdad en el nodo. Los valores son FIJOS y propios de cada arma y
##     rareza; se suman, salvo las stats con "op": "mul_percent" (el tamaño),
##     que multiplican el valor actual.
##     Un arma sin entrada en la tabla usa FALLBACK_WEAPON_STATS (y avisa en consola).
##     El tope de armas lo da Player.max_weapons: mientras no se llegue a él, el
##     lado de armas mezcla armas nuevas y mejoras de las que ya se tienen; al
##     llegar al tope, solo mejoras de las que se tienen.
##     Los extra_entries de WeaponCatalog ya NO se usan.
##   - Cartas "new_weapon" para las armas de WeaponCatalog que el jugador NO
##     tiene, ocultas del todo al llegar a su tope Player.max_weapons.
## En una oferta sale como máximo UNA carta por arma (ver _weighted_pick).
## Campos de una entrada:
##   kind: "stat" (por defecto, se omite), "new_weapon" o "tome".
##   target: "player" | "health" | "run_state" | "weapon/<NodeName>" (las armas
##       se buscan bajo el montaje Weapons del jugador).
##   op: "mul_percent" (amount = +/- porcentaje) | "add" (cantidad plana).
##   effects: forma OPCIONAL de varios stats: una lista de
##       {property, op, amount} que se aplica junta sobre el mismo target, en
##       lugar del trío property/op/amount. La descripción lleva un "%d" por
##       efecto, en orden (salvo las cartas con `preview`, que arman su texto).
##   description: "%d" que se llena con la cantidad escalada por la rareza; las
##       descripciones de new_weapon se muestran tal cual.
##   offer_weight: probabilidad relativa de aparecer en una oferta (1.0 por
##       defecto).
##   rarity: fija la rareza de la carta por nombre en vez de sortearla.
##   values: OPCIONAL. Cantidad FIJA por rareza, en el orden de Rarity.TIERS
##       (Común, Raro, Épico, Legendario). Si existe, sustituye a
##       amount x potency; si no, se usa el escalado por potencia de siempre.
## La suerte del jugador (PlayerStats) inclina el sorteo de rareza.
##
## Texto que ve el jugador: title y description. id, target, property y los
## nombres de rareza son identificadores en inglés.

# --- Edita aquí --------------------------------------------------------------

## Probabilidad de que una subida de nivel ofrezca el lado de armas cuando
## ambos lados pueden mostrar una oferta completa (0.5 = 50-50).
const WEAPON_SIDE_CHANCE: float = 0.5
## Máximo de subidas seguidas que pueden ofrecer el mismo lado.
const MAX_SAME_SIDE_STREAK: int = 3

## MEJORAS MÚLTIPLES: cuántas stats distintas puede traer UNA carta de arma.
## Cada posición es el PESO de que la carta traiga ese número de stats:
##   índice 0 = 1 stat, índice 1 = 2 stats, índice 2 = 3 stats.
## El MÁXIMO de stats lo da la cantidad de valores del array (3 valores = máx. 3).
## Los pesos son relativos, no hace falta que sumen 1 ni 100.
## Ejemplos:
##   [1.0]                  -> siempre 1 stat (sin mejoras múltiples)
##   [0.55, 0.30, 0.15]     -> 55% una, 30% dos, 15% tres (valor actual)
##   [0.0, 0.5, 0.5]        -> nunca una sola; 2 o 3 a partes iguales
##   [0.4, 0.3, 0.2, 0.1]   -> permite hasta 4 stats
## Si el arma tiene menos stats válidas que el máximo, se limita a las que tenga.
const STAT_COUNT_WEIGHTS: Array[float] = [0.55, 0.30, 0.15]

## Peso de oferta de las cartas de arma nueva (menos que las de stats).
const NEW_WEAPON_OFFER_WEIGHT: float = 0.6
## Peso de oferta de cada carta de tomo, algo bajo para que los tomos no
## llenen el pool.
const TOME_OFFER_WEIGHT: float = 0.8
## Rareza fija de las cartas de arma nueva (un name de Rarity.TIERS).
const NEW_WEAPON_RARITY: String = "Rare"

## Nombre, título de carta y formato de cada stat de arma. AQUÍ NO HAY NÚMEROS:
## lo que sube cada stat está por arma en WEAPON_UPGRADE_STATS.
##   percent: true -> la carta muestra el valor como % del valor original del
##            arma (100% -> 114%); se usa con el tamaño ("op": "mul_percent").
##   suffix:  texto tras el número ("%" para crítico: son puntos porcentuales).
##   scale:   factor solo para mostrar (el robo de vida se guarda en 0-1).
## Velocidad de ataque y alcance NO están a propósito: no salen como mejora de
## arma (la velocidad de ataque llega por el Tomo de Celeridad).
const WEAPON_STAT_DEFS: Dictionary = {
	"damage": {"label": "Daño", "title": "Afilado"},
	"size": {"label": "Tamaño", "title": "Expansión", "percent": true},
	"count": {"label": "Cantidad", "title": "Multiplicar"},
	"crit": {"label": "Prob. crítico", "title": "Ojo certero", "suffix": "%"},
	"crit_damage": {"label": "Daño crítico", "title": "Golpe letal", "suffix": "%"},
	"bounces": {"label": "Rebotes", "title": "Rebote"},
	"projectile_speed": {"label": "Vel. de proyectil", "title": "Impulso"},
	"duration": {"label": "Duración", "title": "Resistencia"},
	"lifesteal": {"label": "Robo de vida", "title": "Sed de sangre", "suffix": "%", "scale": 100.0},
	# Sin armas todavía: falta la API de empuje en EnemyBase.
	"knockback": {"label": "Empuje", "title": "Impacto"},
}

## MEJORAS POR ARMA. Cada arma (id de WeaponCatalog) tiene su propio bloque, y
## cada stat dentro de él lleva:
##   property: la propiedad del nodo del arma que sube.
##   values:   cuánto sube por rareza, en el orden [Común, Raro, Épico, Legendario].
##   op:       opcional. "add" (por defecto, suma el valor tal cual) o
##             "mul_percent" (el valor es un % que multiplica el actual).
## Para que una arma no ofrezca una stat, borra esa línea de SU bloque. Para
## que ofrezca otra, añade la línea (la stat debe existir en WEAPON_STAT_DEFS).
## Un arma que no esté aquí no ofrece mejoras.
## !! Los ids de arma y los nombres de propiedad son SUPOSICIONES (salvo damage,
## puddle_radius y puddle_life). Si una propiedad no existe en el nodo, esa
## stat no entra al pool y la consola avisa "has no property 'X'". Si el id del
## arma no coincide, la consola avisa "weapon id 'X' has no ... entry".
## Los números son de EJEMPLO: ajústalos a la escala de cada arma.
const WEAPON_UPGRADE_STATS: Dictionary = {
	"aura": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "attack_range", "op": "mul_percent", "values": [5, 8, 14, 20]},
	},
	"blood_vial": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "pool_radius", "op": "mul_percent", "values": [6, 10, 14, 20]},
		"duration": {"property": "pool_ticks", "values": [1, 1, 2, 2]},
		"lifesteal": {"property": "heal_fraction", "values": [0.02, 0.03, 0.04, 0.06]},
		"projectile_speed": {"property": "projectile_speed", "values": [0.1, 0.15, 0.2, 0.3]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
	},
	"boomerang": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "blade_scale", "op": "mul_percent", "values": [6, 10, 14, 20]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
	},
	"dart_pistol": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
		"crit": {"property": "crit_chance_bonus", "values": [2, 3, 5, 7]},
		"crit_damage": {"property": "crit_damage_bonus", "values": [5, 7, 15, 20]},
		"bounces": {"property": "bounces", "values": [1, 2, 3, 4]},
	},
	"ember_wand": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "burst_radius", "op": "mul_percent", "values": [6, 10, 14, 20]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
	},
	"kamehameha": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "beam_width", "op": "mul_percent", "values": [6, 10, 14, 20]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
	},
	"shortsword": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "attack_range", "op": "mul_percent", "values": [6, 10, 14, 20]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
	},
	"slime_trail": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"duration": {"property": "puddle_life", "values": [0.1, 0.2, 0.3, 0.4]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
		"size": {"property": "puddle_radius", "op": "mul_percent", "values": [6, 10, 14, 20]},
	},
	"spirit_orbs": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "hit_radius", "op": "mul_percent", "values": [6, 10, 14, 20]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
	},
	"storm_rod": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
		"bounces": {"property": "chain_count", "values": [1, 1, 2, 2]},
	},
	"twin_daggers": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "slash_radius", "op": "mul_percent", "values": [6, 10, 14, 20]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
		"crit": {"property": "crit_chance_bonus", "values": [2, 3, 5, 7]},
		"crit_damage": {"property": "crit_damage_bonus", "values": [5, 7, 15, 20]},
	},
	"stench": {
		"damage": {"property": "damage", "values": [1, 2, 3, 4]},
		"size": {"property": "attack_range", "op": "mul_percent", "values": [2, 5, 8, 14]},
		"count": {"property": "projectile_count", "values": [1, 1.4, 1.7, 2]},
		"duration": {"property": "poison_duration", "values": [0.1, 0.2, 0.3, 0.4]},
	},
}

## Mejoras de respaldo para un arma que el jugador TIENE pero que no figura en
## WEAPON_UPGRADE_STATS (id que no coincide, arma nueva sin configurar). Así un
## arma poseída siempre puede mejorarse y el lado de armas nunca se queda corto.
const FALLBACK_WEAPON_STATS: Dictionary = {
	"damage": {"property": "damage", "values": [1, 2, 3, 4]},
}

## Cartas de stats sin tomo equivalente, siempre disponibles en el lado de
## tomos. Hoy está vacío: HP máx. (Tomo de Vitalidad) y radio de recolección
## (Tomo de Codicia) pasaron a Tome.TOME_LIBRARY. Si añades una carta aquí,
## el código de _generic_preview y del target sigue funcionando como antes.
const GENERIC_POOL: Array[Dictionary] = []

# --- Identificadores y respaldos ----------------------------------------------

## Los dos lados del pool. Son identificadores, no texto: SIDE_LABELS los
## traduce para el título de la carta.
const SIDE_WEAPONS: String = "weapons"
const SIDE_TOMES: String = "tomes"
const SIDE_LABELS: Dictionary[String, String] = {
	SIDE_WEAPONS: "Armas", SIDE_TOMES: "Tomos"}

## NO es el tope de armas ni de tomos del juego: los topes reales son los
## exports Player.max_weapons y Player.max_tomes. Este valor solo se usa si el
## nodo que llega como jugador no tiene esos exports.
const CAP_IF_PLAYER_HAS_NO_EXPORT: int = 5

## Historial de la incursión: último lado ofrecido y cuántas veces seguidas.
## Llama a reset_side_history() al empezar cada incursión.
static var _last_side: String = ""
static var _streak: int = 0

# --- Reenvíos: el código vive en WeaponCatalog, Rarity y AutoloadLookup -------
# Otros scripts todavía usan estos nombres en UpgradePool.

const WEAPON_LIBRARY: Array[Dictionary] = WeaponCatalog.WEAPON_LIBRARY
const RARITIES: Array[Dictionary] = Rarity.TIERS


## Sortea `count` mejoras distintas del pool válido para el equipo de este
## jugador, cada una con su propia rareza ponderada. Devuelve diccionarios
## listos para mostrar: entry, rarity, amount, title, description. Una elección
## extra (open_bonus_pick) pasa luck_bonus (suerte temporal sobre la de PlayerStats) y/o
## min_rarity (nombre de la rareza mínima, que sube también las fijas). `side`
## limita el pool a SIDE_WEAPONS o SIDE_TOMES; "" (por defecto, lo que pasan
## las elecciones extra) mezcla.
static func roll_offer(player: Node, count: int = 3, luck_bonus: float = 0.0,
		min_rarity: String = "", side: String = "") -> Array[Dictionary]:
	var offer: Array[Dictionary] = []
	var stats := PlayerStats.find_in(player)
	var luck := (stats.luck if stats != null else 0.0) + luck_bonus
	var floor_index := Rarity.index_of(min_rarity)
	for entry: Dictionary in _weighted_pick(build_pool(player, side), count):
		var rarity := Rarity.resolve(String(entry.get("rarity", "")), luck, floor_index)
		if String(entry.get("kind", "stat")) == "new_weapon":
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": 0.0,
				"title": entry.title,
				"description": entry.description,
			})
			continue
		if entry.has("effects"):
			# Carta de varios stats: una cantidad por efecto, en orden.
			var amounts: Array[float] = []
			var shown: Array[int] = []
			for effect: Dictionary in entry.effects as Array:
				var scaled: float = _amount_for(effect, rarity)
				amounts.append(scaled)
				shown.append(absi(roundi(scaled)))
			var effects_text: String
			if bool(entry.get("preview", false)):
				effects_text = _weapon_preview(entry, amounts, player)
			else:
				effects_text = String(entry.description) % shown
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": amounts[0] if not amounts.is_empty() else 0.0,
				"amounts": amounts,
				"title": entry.title,
				"description": effects_text,
			})
			continue
		var amount: float = _amount_for(entry, rarity)
		if bool(entry.get("gamble", false)):
			# Tomo del Azar: la cantidad de boons sale del rango de rareza, no
			# de amount x potencia. La carta y PlayerStats leen la misma
			# función, así la carta nunca promete menos boons de los que salen.
			amount = float(Tome.gamble_boon_count(float(rarity.potency)))
		var description: String = entry.description % absi(roundi(amount))
		if String(entry.get("kind", "stat")) == "tome" \
				and not bool(entry.get("gamble", false)) and stats != null:
			# Los tomos muestran solo el cambio ("8% -> 16%"), no lo que da el stack.
			description = _tome_preview(
					stats, String(entry.tome_id), float(rarity.potency))
		elif entry.has("label"):
			description = _generic_preview(entry, amount, player)
		offer.append({
			"entry": entry,
			"rarity": rarity,
			"amount": amount,
			"title": entry.title,
			"description": description,
		})
	return offer


## Cantidad de una entrada o efecto para una rareza: la tabla `values` (valor
## fijo por rareza, en el orden de Rarity.TIERS) si existe; si no, la cantidad
## base escalada por la potencia, como antes. Con `values` no se redondea.
static func _amount_for(source: Dictionary, rarity: Dictionary) -> float:
	var values: Array = source.get("values", [])
	if not values.is_empty():
		var index := mini(Rarity.index_of(String(rarity.name)), values.size() - 1)
		return float(values[index])
	return roundf(float(source.amount) * float(rarity.potency))


## El pool del que el jugador puede sortear ahora. `side` lo limita a una
## mitad (SIDE_WEAPONS / SIDE_TOMES); "" devuelve las dos, como quieren las
## elecciones extra.
static func build_pool(player: Node, side: String = "") -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if side != SIDE_WEAPONS:
		pool.append_array(_tome_side(player))
	if side != SIDE_TOMES:
		pool.append_array(_weapon_side(player))
	return pool


## Qué lado ofrece una elección de nivel. Corre una vez por subida de nivel:
## decide con _pick_side() y recuerda el historial para que el mismo lado no
## salga más de MAX_SAME_SIDE_STREAK veces seguidas.
static func roll_side(player: Node) -> String:
	var side := _pick_side(player)
	if side == _last_side:
		_streak += 1
	else:
		_last_side = side
		_streak = 1
	return side


## Olvida la racha. Llamar al empezar cada incursión: las static var
## sobreviven entre partidas mientras el juego siga abierto.
static func reset_side_history() -> void:
	_last_side = ""
	_streak = 0


## Elige el lado sin tocar el historial. Nunca devuelve un lado vacío: una
## elección sin nada que mostrar trabaría el árbol pausado. Arma las dos
## mitades para contarlas, así las reglas de topes viven solo en
## _tome_side / _weapon_side. Un lado vacío o incompleto manda sobre la racha;
## después manda la racha, y por último el sorteo 50-50.
static func _pick_side(player: Node) -> String:
	var weapons := _distinct_cards(_weapon_side(player))
	var tomes := _distinct_cards(_tome_side(player))
	if weapons <= 0:
		return SIDE_TOMES
	if tomes <= 0:
		return SIDE_WEAPONS
	# Racha al límite: obliga al lado contrario.
	if _streak >= MAX_SAME_SIDE_STREAK:
		return SIDE_TOMES if _last_side == SIDE_WEAPONS else SIDE_WEAPONS
	return SIDE_WEAPONS if randf() < WEAPON_SIDE_CHANCE else SIDE_TOMES


## Nombre de un lado para el título del selector de cartas.
static func side_label(side: String) -> String:
	return SIDE_LABELS.get(side, "")


## Aplica una oferta sorteada a los nodos vivos que cuelgan de `player`.
## Devuelve los boons que acaba de sortear un tomo de apuesta (Tomo del Azar),
## para que quien llama muestre lo que pagó; vacío para cualquier otra carta.
static func apply(offer: Dictionary, player: Node) -> Array[Dictionary]:
	var entry: Dictionary = offer.entry
	var rolled: Array[Dictionary] = []
	match String(entry.get("kind", "stat")):
		"new_weapon":
			_grant_weapon(entry, player)
			return rolled
		"tome":
			return _grant_tome(entry, offer, player)
	var target := _resolve_target(entry.target, player)
	if target == null:
		push_warning("UpgradePool: target '%s' not found for '%s'" % [entry.target, entry.id])
		return rolled
	if entry.has("effects"):
		var amounts: Array[float] = offer.get("amounts", [] as Array[float])
		var effects: Array = entry.effects
		for i in effects.size():
			var effect: Dictionary = effects[i]
			_apply_property(target, String(effect.property), String(effect.op),
					amounts[i] if i < amounts.size() else float(effect.amount), entry)
	else:
		_apply_property(target, String(entry.property), String(entry.op),
				float(offer.amount), entry)
	# Cada carta invertida en un arma es un nivel de arma; en cada umbral de
	# EvolutionCatalog evoluciona o asciende en el acto.
	if target is WeaponBase:
		var weapon := target as WeaponBase
		weapon.upgrade_level += 1
		EvolutionCatalog.try_advance_by_level(weapon, player)
	return rolled


# --- Reenvíos (ver el bloque de constantes) -----------------------------------

## Reenvía a Rarity.display_name().
static func rarity_display(rarity_name: String) -> String:
	return Rarity.display_name(rarity_name)


## Reenvía a Rarity.index_of().
static func rarity_index(rarity_name: String) -> int:
	return Rarity.index_of(rarity_name)


## Reenvía a Rarity.potency_rank().
static func potency_rank(potency: float) -> int:
	return Rarity.potency_rank(potency)


## Reenvía a Rarity.roll().
static func roll_rarity(luck: float, floor_index: int = 0) -> Dictionary:
	return Rarity.roll(luck, floor_index)


## Reenvía a WeaponCatalog.by_id().
static func weapon_by_id(weapon_id: String) -> Dictionary:
	return WeaponCatalog.by_id(weapon_id)


## Reenvía a WeaponCatalog.by_node().
static func weapon_by_node(node_name: String) -> Dictionary:
	return WeaponCatalog.by_node(node_name)


## Reenvía a WeaponCatalog.id_for_node().
static func weapon_id_for_node(node_name: String) -> String:
	return WeaponCatalog.id_for_node(node_name)


## Reenvía a WeaponCatalog.display_name_for_node().
static func weapon_display_name(node_name: String) -> String:
	return WeaponCatalog.display_name_for_node(node_name)


## Reenvía a AutoloadLookup.find().
static func autoload_node(node_name: StringName) -> Node:
	return AutoloadLookup.find(node_name)


# --- Privado ------------------------------------------------------------------

## Mitad de tomos/stats: las cartas genéricas, siempre disponibles, más el
## siguiente stack de cada tomo que el jugador aún puede tomar.
static func _tome_side(player: Node) -> Array[Dictionary]:
	var pool: Array[Dictionary] = GENERIC_POOL.duplicate()
	if player == null:
		return pool
	pool.append_array(_tome_entries(player))
	return pool


## Mitad de armas: cartas de stats por cada arma que se tiene más cartas
## new_weapon para las que no (ninguna al llegar al tope de armas).
static func _weapon_side(player: Node) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if player == null:
		return pool
	var mount := player.get_node_or_null("Weapons")
	if mount == null:
		return pool
	var owned := 0
	for weapon: Dictionary in WeaponCatalog.WEAPON_LIBRARY:
		if mount.has_node(String(weapon.node_name)):
			owned += 1
			var weapon_node := mount.get_node(String(weapon.node_name))
			var weapon_entries := _entries_for_weapon(weapon, weapon_node)
			# DEPURACIÓN: borrar cuando las tablas estén corregidas. Lista las
			# variables reales del script del arma, para escribir bien las
			# propiedades de WEAPON_UPGRADE_STATS.
			var var_names: PackedStringArray = []
			for info: Dictionary in weapon_node.get_property_list():
				if int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var_names.append(String(info.name))
			var stat_status: PackedStringArray = []
			var table: Dictionary = WEAPON_UPGRADE_STATS.get(String(weapon.id), {})
			for stat_id: String in table:
				var prop := String((table[stat_id] as Dictionary).get("property", ""))
				var status := "OK"
				if weapon_node.get(prop) == null:
					status = "FALTA"
					var maybe := _candidate_vars(stat_id, var_names)
					if not maybe.is_empty():
						status += " -> quizá: " + maybe
				stat_status.append("%s(%s)=%s" % [stat_id, prop, status])
			print("[UpgradePool] ", weapon.id, " -> ", ", ".join(stat_status))
			print("[UpgradePool]   vars reales: ", ", ".join(var_names))
			pool.append_array(weapon_entries)
	if owned < _player_cap(player, "max_weapons"):
		for weapon: Dictionary in WeaponCatalog.WEAPON_LIBRARY:
			if not mount.has_node(String(weapon.node_name)):
				pool.append(_new_weapon_entry(weapon))
	return pool


## DEPURACIÓN (junto con los print de _weapon_side): palabras que suelen llevar
## los nombres reales de cada stat, para sugerir cuál variable del arma usar.
const STAT_NAME_HINTS: Dictionary = {
	"damage": ["damage", "dmg"],
	"size": ["size", "radius", "width", "area", "scale"],
	"count": ["count", "amount", "num"],
	"crit": ["crit"],
	"crit_damage": ["crit"],
	"bounces": ["bounce", "ricochet", "chain"],
	"projectile_speed": ["speed"],
	"duration": ["duration", "life", "time", "tick"],
	"lifesteal": ["steal", "leech"],
	"knockback": ["knock", "push"],
}


static func _candidate_vars(stat_id: String, var_names: PackedStringArray) -> String:
	var found: PackedStringArray = []
	var hints: Array = STAT_NAME_HINTS.get(stat_id, [])
	for hint: String in hints:
		for var_name: String in var_names:
			if var_name.to_lower().contains(hint) and not found.has(var_name):
				found.append(var_name)
	return ", ".join(found)


## Valor de la propiedad antes de la primera mejora; sirve de 100% para mostrar
## el tamaño como porcentaje (se guarda como metadato del nodo del arma).
static func _base_value(target: Object, property: String, current: float) -> float:
	var key := "base_" + property
	if not target.has_meta(key):
		target.set_meta(key, current)
	return maxf(float(target.get_meta(key)), 0.0001)


## Un cambio de propiedad sobre un objetivo vivo. Subir max_hp de un Health
## también cura lo ganado (nunca una curación completa).
static func _apply_property(target: Object, property: String, op: String,
		amount: float, entry: Dictionary) -> void:
	# Object.get() devuelve null para una propiedad que no existe, y asignarlo
	# a un `float` tipado sería un error duro a mitad de carta, con el árbol
	# pausado. Una fila mal escrita debe quedar en advertencia y no congelar la
	# incursión (WeaponBase.evolve hace lo mismo).
	var raw: Variant = target.get(property)
	if raw == null:
		push_warning("UpgradePool: no property '%s' on target for '%s'"
				% [property, entry.get("id", "?")])
		return
	var current := float(raw)
	# Fija el 100% del tamaño antes del primer cambio.
	_base_value(target, property, current)
	match op:
		"mul_percent":
			target.set(property, current * (1.0 + amount / 100.0))
		"add":
			target.set(property, current + amount)
		_:
			push_warning("UpgradePool: unknown op '%s' in '%s'" % [op, entry.id])
	if target is Health and property == "max_hp" and amount > 0.0:
		(target as Health).heal(amount)


## Carta de un arma: UNA sola, con de 1 a STAT_COUNT_WEIGHTS.size() stats
## distintas elegidas al azar entre las de WEAPON_UPGRADE_STATS cuya propiedad
## exista en el nodo y que tengan sus valores. Todas las stats válidas tienen
## la misma opción de salir. Un arma sin tabla usa FALLBACK_WEAPON_STATS.
static func _entries_for_weapon(weapon: Dictionary, node: Node) -> Array[Dictionary]:
	var configured: Dictionary = WEAPON_UPGRADE_STATS.get(String(weapon.id), {})
	if configured.is_empty():
		push_warning("UpgradePool: weapon id '%s' has no WEAPON_UPGRADE_STATS entry, using fallback"
				% String(weapon.id))
		configured = FALLBACK_WEAPON_STATS
	var props: Dictionary = {}
	for stat_id: String in configured:
		var cfg: Dictionary = configured[stat_id]
		var property := String(cfg.get("property", ""))
		if not WEAPON_STAT_DEFS.has(stat_id) or (cfg.get("values", []) as Array).is_empty():
			push_warning("UpgradePool: weapon '%s' stat '%s' is missing its def or values"
					% [String(weapon.id), stat_id])
			continue
		if node.get(property) == null:
			push_warning("UpgradePool: weapon '%s' has no property '%s' (stat '%s')"
					% [String(weapon.id), property, stat_id])
			continue
		props[stat_id] = cfg
	var entries: Array[Dictionary] = []
	if props.is_empty():
		return entries
	var target := "weapon/" + String(weapon.node_name)
	var ids: Array = props.keys()
	ids.shuffle()
	var n := _roll_stat_count(ids.size())
	entries.append(_weapon_stat_entry(weapon, target, ids.slice(0, n), props, 1.0))
	return entries


## Cuántas stats lleva la carta (1 a STAT_COUNT_WEIGHTS.size()), limitado por
## las stats que el arma tiene disponibles.
static func _roll_stat_count(available: int) -> int:
	# Se sortea con TODOS los pesos y después se limita a lo disponible: si sale
	# "3 stats" pero el arma solo tiene 2 válidas, lleva esas 2.
	var total := 0.0
	for weight: float in STAT_COUNT_WEIGHTS:
		total += weight
	var wanted := 1
	if total > 0.0:
		var roll := randf() * total
		wanted = STAT_COUNT_WEIGHTS.size()
		for i in STAT_COUNT_WEIGHTS.size():
			roll -= STAT_COUNT_WEIGHTS[i]
			if roll <= 0.0:
				wanted = i + 1
				break
	return clampi(wanted, 1, maxi(available, 1))


## Una carta de arma con uno o más stats; el valor es fijo por rareza y se
## suma ("add") o multiplica ("mul_percent") según la tabla.
static func _weapon_stat_entry(weapon: Dictionary, target: String, stat_ids: Array,
		props: Dictionary, weight: float) -> Dictionary:
	var effects: Array[Dictionary] = []
	for stat_id: String in stat_ids:
		var cfg: Dictionary = props[stat_id]
		effects.append({
			"stat": stat_id,
			"property": String(cfg.property),
			"op": String(cfg.get("op", "add")),
			"amount": float((cfg.values as Array)[0]),
			"values": cfg.values,
		})
	var title := "Perfeccionar"
	if stat_ids.size() == 1:
		title = String(WEAPON_STAT_DEFS[stat_ids[0]].title)
	return {
		"id": String(weapon.id) + "_" + "_".join(PackedStringArray(stat_ids)),
		"title": title,
		"description": "",
		"target": target,
		"effects": effects,
		"preview": true,
		"offer_weight": weight,
	}


## "Daño 7 -> 9" por efecto, con el valor actual del arma y el que tendrá.
## El tamaño se muestra como % del valor original ("Tamaño 100% -> 114%") y
## el crítico con su signo "%" ("Prob. crítico 5% -> 10%").
static func _weapon_preview(entry: Dictionary, amounts: Array[float],
		player: Node) -> String:
	var weapon := _resolve_target(String(entry.target), player)
	var lines: PackedStringArray = []
	var effects: Array = entry.effects
	for i in effects.size():
		var effect: Dictionary = effects[i]
		var def: Dictionary = WEAPON_STAT_DEFS[String(effect.stat)]
		var raw: Variant = weapon.get(String(effect.property)) if weapon != null else null
		if raw == null:
			push_warning("UpgradePool: no property '%s' for '%s'"
					% [effect.property, entry.id])
			continue
		var current := float(raw)
		var amount := amounts[i] if i < amounts.size() else float(effect.amount)
		var next := current * (1.0 + amount / 100.0) \
				if String(effect.op) == "mul_percent" else current + amount
		if bool(def.get("percent", false)):
			var base := _base_value(weapon, String(effect.property), current)
			lines.append("%s %d%% -> %d%%" % [String(def.label),
					roundi(current / base * 100.0), roundi(next / base * 100.0)])
			continue
		var shown_scale := float(def.get("scale", 1.0))
		lines.append("%s %s -> %s" % [String(def.label),
				_fmt_weapon_value(current * shown_scale, def),
				_fmt_weapon_value(next * shown_scale, def)])
	return "\n".join(lines)


static func _fmt_weapon_value(value: float, def: Dictionary) -> String:
	var suffix := String(def.get("suffix", ""))
	if absf(value - roundf(value)) < 0.05:
		return "%d%s" % [roundi(value), suffix]
	return "%.1f%s" % [value, suffix]


## Una carta por tomo disponible, que ofrece el SIGUIENTE stack (el título
## lleva el numeral, p. ej. «Tomo de Furia II»; Tome.stack_label lo arma para
## cualquier número). Si el efecto principal trae `values`, la carta muestra
## ese valor fijo por rareza; si no, la potencia escala la cantidad.
static func _tome_entries(player: Node) -> Array[Dictionary]:
	var stats := PlayerStats.find_in(player)
	var entries: Array[Dictionary] = []
	# Tope de tomos distintos: con max_tomes tomos diferentes, solo se
	# ofrecen más stacks de esos.
	var owned_distinct := stats.distinct_tome_count() if stats != null else 0
	var at_cap := owned_distinct >= _player_cap(player, "max_tomes")
	for tome: Dictionary in Tome.TOME_LIBRARY:
		var tome_id := String(tome.id)
		var owned_stacks := stats.stack_count(tome_id) if stats != null else 0
		if at_cap and owned_stacks == 0:
			continue
		# Sin tope de stacks: solo se limita la cantidad de tomos DISTINTOS,
		# así un tomo favorito sigue creciendo toda la incursión.
		var next_stack := owned_stacks + 1
		var effects: Array = tome.effects
		var primary: Dictionary = effects[0]
		entries.append({
			"id": tome_id,
			"kind": "tome",
			"tome_id": tome_id,
			"title": Tome.display_title(tome, next_stack),
			"description": String(tome.description),
			# El efecto principal da el número que muestra la carta.
			"amount": float(primary.amount),
			"values": primary.get("values", []),
			# Los tomos de apuesta cuentan boons en su lugar (ver roll_offer).
			"gamble": bool(tome.get("gamble", false)),
			"offer_weight": TOME_OFFER_WEIGHT,
		})
	return entries


## Carta para ganar un arma que el jugador todavía no tiene.
static func _new_weapon_entry(weapon: Dictionary) -> Dictionary:
	return {
		"id": "gain_" + String(weapon.id),
		"kind": "new_weapon",
		"title": String(weapon.display_name),
		"description": "Nuevo",
		"scene": String(weapon.scene),
		"weapon_name": String(weapon.node_name),
		"weapon_id": String(weapon.id),
		"rarity": NEW_WEAPON_RARITY,
		"offer_weight": NEW_WEAPON_OFFER_WEIGHT,
	}


static func _grant_weapon(entry: Dictionary, player: Node) -> void:
	var mount := player.get_node_or_null("Weapons")
	if mount == null:
		push_warning("UpgradePool: no Weapons mount on player for '%s'" % entry.id)
		return
	# Las ofertas ya filtran las armas que se tienen, pero una tirada vieja en
	# cola podría llegar tarde.
	if mount.has_node(String(entry.weapon_name)):
		return
	var scene := load(String(entry.scene)) as PackedScene
	if scene == null:
		push_warning("UpgradePool: bad weapon scene '%s' in '%s'" % [entry.scene, entry.id])
		return
	var weapon := scene.instantiate() as Node3D
	weapon.name = String(entry.weapon_name)
	mount.add_child(weapon)
	# Colección: «llevó esta arma alguna vez» (se guarda al cerrar la
	# incursión, como todo contador).
	var weapon_id := String(entry.get("weapon_id", ""))
	if not weapon_id.is_empty():
		var save_data := AutoloadLookup.find(&"SaveData")
		if save_data != null:
			save_data.bump("used_weapon_" + weapon_id)


## Suma un stack con la potencia de la rareza sorteada; PlayerStats
## recalcula todo desde cero (usando Tome.effect_amount), así lo mostrado
## coincide con lo aplicado.
## Devuelve los boons que sorteó un tomo de apuesta (vacío para los demás).
static func _grant_tome(entry: Dictionary, offer: Dictionary,
		player: Node) -> Array[Dictionary]:
	var stats := PlayerStats.find_in(player)
	if stats == null:
		push_warning("UpgradePool: no PlayerStats on player for '%s'" % entry.id)
		return [] as Array[Dictionary]
	var rarity: Dictionary = offer.rarity
	return stats.add_tome(String(entry.tome_id), float(rarity.potency))


## El tope exportado `property` del jugador (max_weapons, max_tomes), o
## CAP_IF_PLAYER_HAS_NO_EXPORT si el nodo no lo tiene.
static func _player_cap(player: Node, property: String) -> int:
	if player == null:
		return CAP_IF_PLAYER_HAS_NO_EXPORT
	var value: Variant = player.get(property)
	return int(value) if value != null else CAP_IF_PLAYER_HAS_NO_EXPORT


static func _resolve_target(target_path: String, player: Node) -> Object:
	match target_path:
		"player":
			return player
		"health":
			return Health.find_in(player)
		"run_state":
			return AutoloadLookup.find(&"RunState")
	if target_path.begins_with("weapon/"):
		var mount := player.get_node_or_null("Weapons")
		if mount != null:
			return mount.get_node_or_null(target_path.get_slice("/", 1))
	return null


## Tomo nuevo: "Nuevo" y debajo "Prob. crítico 6%". Tomo que ya tienes:
## "Prob. crítico 6% -> 14%". Solo cuenta lo que dan los tomos, con la misma
## fórmula que PlayerStats._apply_tomes.
static func _tome_preview(stats: PlayerStats, tome_id: String, potency: float) -> String:
	var primary: Dictionary = (Tome.by_id(tome_id).effects as Array)[0]
	var stat := String(primary.stat)
	var stat_name := String(Tome.STAT_NAMES.get(stat, stat))
	var unit := "%" if Tome.PERCENT_STATS.has(stat) else ""
	var current := 0.0
	for owned: float in stats._tome_stacks.get(tome_id, PackedFloat32Array()):
		current += roundf(Tome.effect_amount(primary, owned))
	var next := current + roundf(Tome.effect_amount(primary, potency))
	if stats.stack_count(tome_id) == 0:
		return "Nuevo\n%s %d%s" % [stat_name, int(next), unit]
	return "%s %d%s -> %d%s" % [stat_name, int(current), unit, int(next), unit]


## Cartas genéricas: "Radio de recolección 100% -> 125%", o "Nuevo" y debajo
## el valor si el stat sigue en su base (new_value).
static func _generic_preview(entry: Dictionary, amount: float, player: Node) -> String:
	var fallback: String = entry.description % absi(roundi(amount))
	var target := _resolve_target(String(entry.target), player)
	if target == null:
		return fallback
	var raw: Variant = target.get(String(entry.property))
	if raw == null:
		return fallback
	var current := float(raw)
	var next := current * (1.0 + amount / 100.0) \
			if String(entry.op) == "mul_percent" else current + amount
	var scale := float(entry.get("display_scale", 1.0))
	var def := {"suffix": String(entry.get("suffix", ""))}
	var label := String(entry.label)
	if entry.has("new_value") and is_equal_approx(current, float(entry.new_value)):
		return "Nuevo\n%s %s" % [label, _fmt_weapon_value(next * scale, def)]
	return "%s %s -> %s" % [label, _fmt_weapon_value(current * scale, def),
			_fmt_weapon_value(next * scale, def)]


## Elige hasta `count` entradas distintas, ponderadas por offer_weight.
## Como máximo una entrada por arma: al elegir una carta de un arma, las
## demás cartas de esa misma arma salen de la tirada.
static func _weighted_pick(entries: Array[Dictionary], count: int) -> Array[Dictionary]:
	var remaining := entries.duplicate()
	var picked: Array[Dictionary] = []
	while picked.size() < count and not remaining.is_empty():
		var total := 0.0
		for entry: Dictionary in remaining:
			total += float(entry.get("offer_weight", 1.0))
		var roll := randf() * total
		var chosen := remaining.size() - 1
		for i in remaining.size():
			roll -= float(remaining[i].get("offer_weight", 1.0))
			if roll <= 0.0:
				chosen = i
				break
		var chosen_entry: Dictionary = remaining[chosen]
		picked.append(chosen_entry)
		remaining.remove_at(chosen)
		var group := _weapon_group(chosen_entry)
		if not group.is_empty():
			remaining = remaining.filter(
					func(e: Dictionary) -> bool: return _weapon_group(e) != group)
	return picked


## Arma a la que pertenece una carta de stats ("weapon/<Nodo>"), o "" si no
## es de un arma (tomos, genéricas y new_weapon no se agrupan).
static func _weapon_group(entry: Dictionary) -> String:
	var target := String(entry.get("target", ""))
	return target if target.begins_with("weapon/") else ""


## Cartas que de verdad pueden salir juntas: una por arma, más las que no son de arma.
static func _distinct_cards(entries: Array[Dictionary]) -> int:
	var groups := {}
	var singles := 0
	for entry: Dictionary in entries:
		var group := _weapon_group(entry)
		if group.is_empty():
			singles += 1
		else:
			groups[group] = true
	return singles + groups.size()
