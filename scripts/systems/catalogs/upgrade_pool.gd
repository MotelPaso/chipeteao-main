class_name UpgradePool
extends RefCounted
## Pool de mejoras de subida de nivel, con rareza ponderada. Cada elección de
## NIVEL sortea UN lado del pool, nunca una mezcla: armas (cartas de stats de
## las armas que se tienen + cartas new_weapon) o tomos/stats (cartas de tomo +
## GENERIC_POOL). roll_side() elige el lado, ponderado por cuántas entradas
## tiene cada uno, y nunca devuelve uno vacío; la UI de cartas lo nombra en el
## título. Las elecciones extra (cofres, altares) no pasan lado y mezclan todo.
## El pool se arma de nuevo en cada tirada con:
##   - GENERIC_POOL: ajustes de player/health/run_state, siempre disponibles.
##   - Cartas de tomo (Tome.TOME_LIBRARY): el siguiente stack de cada tomo que
##     el jugador aún puede tomar; aplicarla suma un stack en PlayerStats.
##   - Cartas de stats por cada arma QUE SE TIENE: las de WEAPON_STAT_CARDS
##     más los extra_entries de su fila en WeaponCatalog, así cada arma sigue
##     escalando.
##   - Cartas "new_weapon" para las armas de WeaponCatalog que el jugador NO
##     tiene, ocultas del todo al llegar a su tope Player.max_weapons.
## Campos de una entrada:
##   kind: "stat" (por defecto, se omite), "new_weapon" o "tome".
##   target: "player" | "health" | "run_state" | "weapon/<NodeName>" (las armas
##       se buscan bajo el montaje Weapons del jugador).
##   op: "mul_percent" (amount = +/- porcentaje) | "add" (cantidad plana).
##   effects: forma OPCIONAL de varios stats: una lista de
##       {property, op, amount} que se aplica junta sobre el mismo target, en
##       lugar del trío property/op/amount. La descripción lleva un "%d" por
##       efecto, en orden.
##   description: "%d" que se llena con la cantidad escalada por la rareza; las
##       descripciones de new_weapon se muestran tal cual.
##   offer_weight: probabilidad relativa de aparecer en una oferta (1.0 por
##       defecto).
##   rarity: fija la rareza de la carta por nombre en vez de sortearla.
## La rareza (Rarity) multiplica la cantidad base (una carta Epic de +25% sale
## con +50%), así un arma o tomo nuevo solo agrega entradas y la UI no cambia.
## La suerte del jugador (PlayerStats) inclina el sorteo de rareza.
##
## Texto que ve el jugador: title y description. id, target, property y los
## nombres de rareza son identificadores en inglés.

# --- Edita aquí --------------------------------------------------------------

## Peso de oferta de las cartas de arma de dos stats (algo menos que las de
## un stat).
const MULTI_STAT_OFFER_WEIGHT: float = 0.7
## Peso de oferta de las cartas de arma nueva (menos que las de stats).
const NEW_WEAPON_OFFER_WEIGHT: float = 0.6
## Peso de oferta de cada carta de tomo, algo bajo para que los tomos no
## llenen el pool.
const TOME_OFFER_WEIGHT: float = 0.8
## Rareza fija de las cartas de arma nueva (un name de Rarity.TIERS).
const NEW_WEAPON_RARITY: String = "Rare"

## Cartas de stats que genera CADA arma que se tiene, en este orden. Las
## cantidades son porcentajes a potencia Common (la rareza sorteada las
## escala). La descripción no nombra el arma: la UI de cartas muestra una
## etiqueta con el arma en toda carta con target "weapon/...".
## `suffix` arma el id de la carta (<id del arma> + suffix): es un
## identificador, no lo cambies. Una fila con `effects` es una carta de dos
## stats (un "%d" por efecto, en orden).
const WEAPON_STAT_CARDS: Array[Dictionary] = [
	{
		"suffix": "_damage", "title": "Afilado",
		"description": "Aumenta el daño en un %d%%",
		"property": "damage", "op": "mul_percent", "amount": 25.0,
	},
	{
		"suffix": "_cooldown", "title": "Mano rápida",
		"description": "Aumenta la velocidad de ataque en un %d%%",
		"property": "cooldown", "op": "mul_percent", "amount": -10.0,
	},
	{
		"suffix": "_range", "title": "Largo alcance",
		"description": "Aumenta el alcance en un %d%%",
		"property": "attack_range", "op": "mul_percent", "amount": 15.0,
	},
	{
		"suffix": "_tempered", "title": "Temple",
		"description": "Aumenta el daño en un %d%%\nAumenta el alcance en un %d%%",
		"effects": [
			{"property": "damage", "op": "mul_percent", "amount": 15.0},
			{"property": "attack_range", "op": "mul_percent", "amount": 10.0},
		],
		"offer_weight": MULTI_STAT_OFFER_WEIGHT,
	},
	{
		"suffix": "_rhythm", "title": "Ritmo de batalla",
		"description": "Aumenta la velocidad de ataque en un %d%%\nAumenta el daño en un %d%%",
		"effects": [
			{"property": "cooldown", "op": "mul_percent", "amount": -6.0},
			{"property": "damage", "op": "mul_percent", "amount": 10.0},
		],
		"offer_weight": MULTI_STAT_OFFER_WEIGHT,
	},
]

## Cartas de stats sin tomo equivalente, siempre disponibles en el lado de
## tomos. Los stats que tienen tomo (velocidad -> Tomo de Ligereza) viven solo
## en el catálogo de tomos.
const GENERIC_POOL: Array[Dictionary] = [
	{
		# Sube el máximo y cura SOLO lo ganado (ver _apply_property).
		"id": "max_hp", "title": "Corazón recio",
		"description": "HP máx. +%d (te cura lo que ganas)",
		"target": "health", "property": "max_hp",
		"op": "add", "amount": 20.0,
	},
	{
		"id": "pickup_radius", "title": "Aura de codicia",
		"description": "Radio de recolección +%d%%",
		"target": "run_state", "property": "pickup_radius_multiplier",
		"op": "mul_percent", "amount": 25.0,
	},
]

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

# --- Reenvíos: el código vive en WeaponCatalog, Rarity y AutoloadLookup -------
# Otros scripts todavía usan estos nombres en UpgradePool.

const WEAPON_LIBRARY: Array[Dictionary] = WeaponCatalog.WEAPON_LIBRARY
const RARITIES: Array[Dictionary] = Rarity.TIERS


## Sortea `count` mejoras distintas del pool válido para el equipo de este
## jugador, cada una con su propia rareza ponderada. Devuelve diccionarios
## listos para mostrar: entry, rarity, amount, title, description. Altares y
## cofres pasan luck_bonus (suerte temporal sobre la de PlayerStats) y/o
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
			# Carta de varios stats: una cantidad escalada por efecto, en orden.
			var amounts: Array[float] = []
			var shown: Array[int] = []
			for effect: Dictionary in entry.effects as Array:
				var scaled: float = roundf(float(effect.amount) * float(rarity.potency))
				amounts.append(scaled)
				shown.append(absi(roundi(scaled)))
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": amounts[0] if not amounts.is_empty() else 0.0,
				"amounts": amounts,
				"title": entry.title,
				"description": String(entry.description) % shown,
			})
			continue
		var amount: float = roundf(float(entry.amount) * float(rarity.potency))
		if bool(entry.get("gamble", false)):
			# Tomo del Azar: la cantidad de boons sale del rango de rareza, no
			# de amount x potencia. La carta y PlayerStats leen la misma
			# función, así la carta nunca promete menos boons de los que salen.
			amount = float(Tome.gamble_boon_count(float(rarity.potency)))
		offer.append({
			"entry": entry,
			"rarity": rarity,
			"amount": amount,
			"title": entry.title,
			"description": entry.description % absi(roundi(amount)),
		})
	return offer


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


## Qué lado ofrece una elección de nivel: al azar, ponderado por cuántas
## entradas tiene cada lado ahora. Nunca devuelve un lado vacío: una elección
## sin nada que mostrar trabaría el árbol pausado. Arma las dos mitades para
## contarlas (corre una vez por subida de nivel), así las reglas de topes
## viven solo en _tome_side / _weapon_side.
static func roll_side(player: Node) -> String:
	var weapons := _weapon_side(player).size()
	var tomes := _tome_side(player).size()
	if weapons <= 0:
		return SIDE_TOMES
	if tomes <= 0:
		return SIDE_WEAPONS
	return SIDE_WEAPONS if randf() * float(weapons + tomes) < float(weapons) \
			else SIDE_TOMES


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
			pool.append_array(_entries_for_weapon(weapon))
	if owned < _player_cap(player, "max_weapons"):
		for weapon: Dictionary in WeaponCatalog.WEAPON_LIBRARY:
			if not mount.has_node(String(weapon.node_name)):
				pool.append(_new_weapon_entry(weapon))
	return pool


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
	match op:
		"mul_percent":
			target.set(property, current * (1.0 + amount / 100.0))
		"add":
			target.set(property, current + amount)
		_:
			push_warning("UpgradePool: unknown op '%s' in '%s'" % [op, entry.id])
	if target is Health and property == "max_hp" and amount > 0.0:
		(target as Health).heal(amount)


## Las cartas de WEAPON_STAT_CARDS para un arma (con su id y su target) más
## los extra_entries de su fila, en ese orden.
static func _entries_for_weapon(weapon: Dictionary) -> Array[Dictionary]:
	var target: String = "weapon/" + String(weapon.node_name)
	var entries: Array[Dictionary] = []
	for card: Dictionary in WEAPON_STAT_CARDS:
		var entry: Dictionary = card.duplicate(true)
		entry.erase("suffix")
		entry["id"] = String(weapon.id) + String(card.suffix)
		entry["target"] = target
		entries.append(entry)
	for extra: Dictionary in weapon.get("extra_entries", [] as Array[Dictionary]):
		entries.append(extra)
	return entries


## Una carta por tomo disponible, que ofrece el SIGUIENTE stack (el título
## lleva el numeral, p. ej. «Tomo de Furia II»; Tome.stack_label lo arma para
## cualquier número). La potencia de la rareza sorteada escala las cantidades
## igual que en las cartas de stats.
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
		"description": String(weapon.flavor),
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
## recalcula todo desde cero, así lo mostrado coincide con lo aplicado.
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


## Elige hasta `count` entradas distintas, ponderadas por offer_weight.
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
		picked.append(remaining[chosen])
		remaining.remove_at(chosen)
	return picked
