class_name ItemBag
extends Node
## Objetos de un raider, montado en el Player junto a Stats. Cuenta cada
## objeto de ItemCatalog recogido en la partida (copias ilimitadas), pasa los
## de stats a PlayerStats (que lee count(id) en su recompute) y ejecuta los
## de comportamiento:
##   magnet        — aspiradora de XP de todo el mapa cada cierto tiempo, por
##                   el grupo "run_systems"
##   poison_on_hit — cada golpe de arma envenena al blanco (on_weapon_hit)
##   spiders       — las bajas lanzan arañas venenosas teledirigidas
##                   (on_weapon_kill)
##   saiyan        — cada N bajas, un aura temporal de stats
## Los demás kinds (demonic_boost, charge_boost, portal_recharge) son
## contadores que leen los santuarios con count_kind().
## Los números de cada comportamiento viven en la fila del objeto en
## ItemCatalog (ItemCatalog.kind_row), junto al texto que los muestra.
## Las armas reportan golpes y bajas por WeaponBase.deal_damage.
## El comportamiento se resuelve por el `kind` de la fila, nunca por un id
## fijo: renombrar una fila no debe apagar su comportamiento en silencio
## mientras el objeto sigue en el HUD.

signal items_changed(item_id: String, count: int)

## Etiqueta de los boons temporales del aura, para que volver a dispararla
## REEMPLACE su copia en vez de sumar una segunda aura encima. El harness la
## busca por este texto (arena_probe.gd, SAIYAN_TAG).
const SAIYAN_TAG: String = "saiyan"

@export_group("Textos")
## Aviso del HUD cuando la Sangre sayayin enciende el aura.
@export var saiyan_aura_text: String = "¡Aura sayayin!"

var _saiyan_kills: int = 0
var _aura_left: float = 0.0
var _aura_overlays: Array[MeshInstance3D] = []
var _counts: Dictionary[String, int] = {}
var _magnet_timer: float = 0.0
## Presupuesto de arañas: la cuenta y el frame de física al que pertenece.
var _spiders_this_frame: int = 0
var _spider_frame: int = -1


func _physics_process(delta: float) -> void:
	if _aura_left > 0.0:
		_aura_left -= delta
		if _aura_left <= 0.0:
			_apply_aura_shell(false)
	# Casi todos los raiders no llevan nada casi toda la partida: se salta la
	# búsqueda por tipo.
	if _counts.is_empty() or count_kind("magnet") <= 0:
		return
	_magnet_timer -= delta
	if _magnet_timer > 0.0:
		return
	_magnet_timer = _magnet_interval()
	get_tree().call_group("run_systems", "vacuum_pickups")
	var body := get_parent() as Node3D
	if body != null:
		Juice.sparkle(body.global_position + Vector3.UP * 1.0)


## El ItemBag de un cuerpo, o null.
static func find_in(body: Node) -> ItemBag:
	if body == null:
		return null
	for child in body.get_children():
		if child is ItemBag:
			return child
	return null


func count(item_id: String) -> int:
	return int(_counts.get(item_id, 0))


## Copias sumadas de todos los objetos con este `kind` de comportamiento: la
## forma en que se activan los comportamientos de abajo.
func count_kind(kind: String) -> int:
	var total := 0
	for item_id: String in ItemCatalog.ids_of_kind(kind):
		total += count(item_id)
	return total


## Ids de cada objeto llevado, en orden de recolección (franja del HUD).
func carried_ids() -> Array[String]:
	var ids: Array[String] = []
	for item_id: String in _counts:
		if _counts[item_id] > 0:
			ids.append(item_id)
	return ids


## Da una copia. Los ids desconocidos se ignoran con un aviso.
func add_item(item_id: String) -> void:
	var row := ItemCatalog.by_id(item_id)
	if row.is_empty():
		push_warning("ItemBag: unknown item '%s'" % item_id)
		return
	_counts[item_id] = count(item_id) + 1
	match String(row.get("kind", "")):
		"magnet":
			if count_kind("magnet") == 1:
				_magnet_timer = _magnet_interval()
	# Los efectos de stats viven en el recompute de PlayerStats (lee esta bolsa).
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()
	items_changed.emit(item_id, count(item_id))
	# Aviso de botín: UNA llamada para toda fuente (cofres, ruleta, lo que
	# venga), porque esta es la única puerta por la que entra un objeto.
	var owner_index: Variant = get_parent().get("player_index") \
			if get_parent() != null else null
	get_tree().call_group("hud", "show_loot", String(row.display_name),
			String(row.get("description", "")),
			ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
			int(owner_index) if owner_index != null else 0)
	# Contador de descubrimiento tipo bestiario para la Colección.
	SaveData.bump("item_" + item_id)


## Devuelve UNA copia (el pozo del bloque de la suerte cambia un objeto por
## otro mejor). False si el raider no lo lleva, para que el llamador
## distinga un cambio rechazado de uno hecho.
func remove_item(item_id: String) -> bool:
	var held := count(item_id)
	if held <= 0:
		return false
	if held == 1:
		_counts.erase(item_id)
	else:
		_counts[item_id] = held - 1
	# Los mismos pasos que add_item: la capa de stats lee esta bolsa.
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()
	items_changed.emit(item_id, count(item_id))
	return true


## Gancho de WeaponBase: un arma de este raider acaba de golpear a `target`.
func on_weapon_hit(target: Node3D) -> void:
	var stacks := count_kind("poison_on_hit")
	if stacks <= 0:
		return
	var enemy := target as EnemyBase
	if enemy == null:
		return
	var row := ItemCatalog.kind_row("poison_on_hit")
	var stats := PlayerStats.find_in(get_parent())
	var duration := float(row.poison_duration) \
			* (stats.duration_multiplier if stats != null else 1.0)
	enemy.apply_poison(float(row.poison_dps_per_copy) * float(stacks), duration)


## Gancho de WeaponBase: un arma de este raider acaba de matar algo en `at`.
## Cuenta para la Sangre sayayin y, con
## Máscara de superhéroe, lanza arañas desde el cadáver hacia otros enemigos.
func on_weapon_kill(at: Vector3, weapon: WeaponBase) -> void:
	_tick_saiyan_kill()
	var stacks := count_kind("spiders")
	if stacks <= 0 or weapon == null:
		return
	var row := ItemCatalog.kind_row("spiders")
	var wanted := mini(int(row.spiders_per_copy) * stacks, _spider_budget(row))
	if wanted <= 0:
		return
	var targets := _nearest_enemies(at, wanted)
	if targets.is_empty():
		return
	var stats := PlayerStats.find_in(get_parent())
	var duration := float(row.spider_poison_duration) \
			* (stats.duration_multiplier if stats != null else 1.0)
	var spider_range := float(row.spider_range)
	var spider_color: Color = row.spider_color
	for i in wanted:
		var target := targets[i % targets.size()]
		var spider := Pools.acquire_scene(Pools.DART_SCENE) as Projectile
		if spider == null:
			return
		_spiders_this_frame += 1
		spider.global_position = at + Vector3.UP * 0.6
		var aim := target.global_position + Vector3.UP * 0.6
		_aim_spider(spider, aim)
		spider.launch(weapon, spider_range, target)
		# Projectile lee un extra_on_hit asignado como "esto viene de un
		# objeto" y retiene los ganchos de baja: una baja de araña no lanza
		# más arañas.
		spider.extra_on_hit = _poison_spider_victim.bind(duration)
		spider.tint(spider_color)


func _magnet_interval() -> float:
	var row := ItemCatalog.kind_row("magnet")
	return float(row.pull_interval) \
			* pow(float(row.interval_per_extra_copy), float(count_kind("magnet") - 1))


## --- Sangre sayayin ---------------------------------------------------------

## Bajas necesarias para la próxima aura con estas copias.
func _aura_threshold(copies: int) -> int:
	var row := ItemCatalog.kind_row("saiyan")
	var wanted := float(int(row.kills_per_aura)) \
			* pow(float(row.kills_scale_per_extra_copy), float(copies - 1))
	return maxi(roundi(wanted), int(row.kills_floor))


func _tick_saiyan_kill() -> void:
	var copies := count_kind("saiyan")
	if copies <= 0:
		return
	_saiyan_kills += 1
	if _saiyan_kills < _aura_threshold(copies):
		return
	_saiyan_kills = 0
	_start_aura(copies)


func _start_aura(copies: int) -> void:
	var stats := PlayerStats.find_in(get_parent())
	if stats == null:
		return
	var row := ItemCatalog.kind_row("saiyan")
	var scale := float(copies)
	# La duración de efectos del raider alarga el aura, como al veneno.
	var duration := float(row.aura_duration) * stats.duration_multiplier
	# CON ETIQUETA, y limpiada primero: add_timed_boon AGREGA y solo
	# clear_timed_boons quita por etiqueta. Sin esta línea una segunda aura
	# dentro de la primera se sumaría a ella y la primera expiración
	# quitaría solo la mitad. El mismo patrón que PowerUps._apply_row.
	stats.clear_timed_boons(SAIYAN_TAG)
	stats.add_timed_boon("damage", float(row.aura_damage) * scale, duration, SAIYAN_TAG)
	stats.add_timed_boon("cooldown", float(row.aura_attack_speed) * scale, duration, SAIYAN_TAG)
	stats.add_timed_boon("move_speed", float(row.aura_move_speed) * scale, duration, SAIYAN_TAG)
	_aura_left = duration
	_apply_aura_shell(true)
	var body := get_parent() as Node3D
	if body != null:
		Juice.burst(body.global_position + Vector3.UP * 1.0, row.aura_color as Color,
				int(row.get("aura_burst", 24)))
	get_tree().call_group("hud", "announce", saiyan_aura_text)
	print("Saiyan aura: kills=%d" % _aura_threshold(copies))


## Cáscara dorada sobre las mallas del sello, como lo hace Juice.flash:
## material_overlay, restaurado al salir. NUNCA SealRig.apply_tint, que es
## el color de identidad del personaje y quedaría cambiado. La lista se
## vacía antes de rellenarla, para que redisparar no duplique mallas.
func _apply_aura_shell(on: bool) -> void:
	if on:
		_aura_overlays.clear()
	if not on:
		for mesh: MeshInstance3D in _aura_overlays:
			if is_instance_valid(mesh):
				mesh.material_overlay = null
		_aura_overlays.clear()
		return
	var rig := get_parent().get_node_or_null("SealRig") as Node3D
	if rig == null:
		return
	var row := ItemCatalog.kind_row("saiyan")
	var tint: Color = row.aura_color
	# Sin sombreado, como Juice.flash: la cáscara se ve solo con su albedo.
	var shell := StandardMaterial3D.new()
	shell.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.albedo_color = Color(tint, float(row.get("aura_alpha", 0.4)))
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			mesh.material_overlay = shell
			_aura_overlays.append(mesh)


## --- Máscara de superhéroe --------------------------------------------------

## Arañas que aún se permiten en este frame de física (la cuenta se reinicia
## cuando pregunta un frame nuevo). `row` es la fila de la Máscara.
func _spider_budget(row: Dictionary) -> int:
	var frame := int(Engine.get_physics_frames())
	if frame != _spider_frame:
		_spider_frame = frame
		_spiders_this_frame = 0
	return maxi(int(row.max_spiders_per_frame) - _spiders_this_frame, 0)


## Apunta una araña del pool hacia `aim`. Hay dos casos degenerados: el
## blanco puede estar justo sobre el cadáver, o justo encima (un trepador en
## un muro, un excavador que sale debajo), donde look_at no puede armar una
## base con UP; y un nodo del pool que no se orienta conserva la base de su
## vuelo anterior y sale disparado por el mapa.
func _aim_spider(spider: Projectile, aim: Vector3) -> void:
	var to_aim := aim - spider.global_position
	if to_aim.length_squared() <= WeaponBase.DEGENERATE_LENGTH_SQ:
		# Sin dirección utilizable: salta hacia afuera en el plano del
		# cadáver en vez de heredar lo que dejó el pool.
		to_aim = Vector3.FORWARD
	spider.look_at(spider.global_position + to_aim, WeaponBase.safe_up(to_aim.normalized()))


func _poison_spider_victim(body: Node3D, duration: float) -> void:
	var enemy := body as EnemyBase
	if enemy != null:
		enemy.apply_poison(float(ItemCatalog.kind_row("spiders").spider_poison_dps), duration)


## Hasta `limit` enemigos vivos más cercanos a `at`, el más cercano primero
## (los moribundos ya dejaron el grupo). Lleva una lista acotada de los
## mejores en vez de ordenar toda la horda: `limit` es un puñado de arañas,
## el grupo puede tener cientos de cuerpos y esto corre una vez por baja.
func _nearest_enemies(at: Vector3, limit: int) -> Array[Node3D]:
	var best: Array[Node3D] = []
	if limit <= 0:
		return best
	var distances := PackedFloat32Array()
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var distance := body.global_position.distance_squared_to(at)
		if distances.size() >= limit and distance >= distances[distances.size() - 1]:
			continue
		var slot := distances.size()
		while slot > 0 and distances[slot - 1] > distance:
			slot -= 1
		best.insert(slot, body)
		distances.insert(slot, distance)
		if best.size() > limit:
			best.resize(limit)
			distances.resize(limit)
	return best
