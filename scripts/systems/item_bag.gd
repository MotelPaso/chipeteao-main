class_name ItemBag
extends Node
## Per-raider item holder (iteration 40), mounted on the Player beside
## Stats. Counts every ItemCatalog item picked up this run (unlimited
## copies), feeds the stat-effect items into the sibling PlayerStats
## (which reads count(id) in its recompute) and runs the behavioral ones:
##   magnet        — timed map-wide XP vacuum through the "run_systems" group
##   poison_on_hit — every weapon hit poisons the target (on_weapon_hit)
##   titan         — the seal grows per copy (visual rig scale)
##   spiders       — kills launch venomous homing spiders (on_weapon_kill)
##   hook          — a plain counter other systems read (altars, portals)
## Weapons report hits/kills through WeaponBase.deal_damage.
## Behavior is resolved by the row's `kind`, never by a hardcoded item id:
## renaming a catalog row must not silently switch its behavior off while
## the item keeps showing in the HUD.

signal items_changed(item_id: String, count: int)

@export_group("Magnet")
## Seconds between pulls with one magnet; each extra copy multiplies it.
@export var magnet_base_interval: float = 24.0
@export var magnet_interval_per_extra: float = 0.8
@export_group("Fart Bag")
## Poison damage per second per copy, and base duration (x duration stat).
@export var poison_dps_per_copy: float = 3.0
@export var poison_duration: float = 3.0
@export_group("Titan Blood")
@export var titan_scale_per_copy: float = 0.08
@export var titan_max_scale: float = 2.2
@export_group("Superhero Mask")
## Spiders per kill per copy, their flight range, and their poison.
@export var spiders_per_copy: int = 2
@export var spider_range: float = 16.0
@export var spider_poison_dps: float = 4.0
@export var spider_poison_duration: float = 2.5
@export var spider_color: Color = Color(0.55, 0.2, 0.75)
## Ceiling on spiders spawned in a single physics frame. One area weapon
## can kill a dozen bodies in one swing, and every corpse would otherwise
## drain the dart pool and re-scan the whole horde for targets.
@export var max_spiders_per_frame: int = 12

var _counts: Dictionary[String, int] = {}
var _magnet_timer: float = 0.0
## Spider budget bookkeeping: the count and the physics frame it belongs to.
var _spiders_this_frame: int = 0
var _spider_frame: int = -1


## Finds the ItemBag on a body, or null.
static func find_in(body: Node) -> ItemBag:
	if body == null:
		return null
	for child in body.get_children():
		if child is ItemBag:
			return child
	return null


func count(item_id: String) -> int:
	return int(_counts.get(item_id, 0))


## Copies carried across every item with this behavioral `kind` — the form
## the behaviors below gate on (see the class comment).
func count_kind(kind: String) -> int:
	var total := 0
	for item_id: String in ItemCatalog.ids_of_kind(kind):
		total += count(item_id)
	return total


## Ids of every carried item, in pickup order (HUD strip).
func carried_ids() -> Array[String]:
	var ids: Array[String] = []
	for item_id: String in _counts:
		if _counts[item_id] > 0:
			ids.append(item_id)
	return ids


## Grants one copy. Unknown ids are ignored with a warning.
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
		"titan":
			_apply_titan_scale()
		"pet":
			_spawn_or_grow_pet(String(row.get("pet_id", "")), count(item_id))
	# Stat effects live in PlayerStats' recompute (it reads this bag).
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()
	items_changed.emit(item_id, count(item_id))
	# Bestiary-style discovery counter for future Collection pages.
	SaveData.bump("item_" + item_id)


func _physics_process(delta: float) -> void:
	# Most raiders carry nothing for most of a run; skip the kind lookup.
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


func _magnet_interval() -> float:
	return magnet_base_interval * pow(magnet_interval_per_extra, float(count_kind("magnet") - 1))


## Pets (iteration 43): the first copy spawns the companion under the
## player; later copies just feed its weapon.
func _spawn_or_grow_pet(pet_id: String, copies: int) -> void:
	var row := PetCatalog.by_id(pet_id)
	if row.is_empty():
		push_warning("ItemBag: unknown pet '%s'" % pet_id)
		return
	var existing := get_parent().get_node_or_null("Pet_" + pet_id) as Pet
	if existing != null:
		existing.set_copies(copies)
		return
	var pet := Pet.new()
	pet.setup(row, copies)
	get_parent().add_child(pet)
	print("Pet joined: %s" % pet_id)


## Seal grows with every Titan Blood; capped so the camera arm still works.
func _apply_titan_scale() -> void:
	var rig := get_parent().get_node_or_null("SealRig") as Node3D
	if rig == null:
		return
	var factor := minf(1.0 + titan_scale_per_copy * float(count_kind("titan")), titan_max_scale)
	rig.scale = Vector3.ONE * factor


## WeaponBase hook: a weapon carried by this raider just hit `target`.
func on_weapon_hit(target: Node3D) -> void:
	var stacks := count_kind("poison_on_hit")
	if stacks <= 0:
		return
	var enemy := target as EnemyBase
	if enemy == null:
		return
	var stats := PlayerStats.find_in(get_parent())
	var duration := poison_duration * (stats.duration_multiplier if stats != null else 1.0)
	enemy.apply_poison(poison_dps_per_copy * float(stacks), duration)


## WeaponBase hook: a weapon carried by this raider just killed something
## at `at`. Superhero Mask: spiders leap from the corpse at other enemies.
func on_weapon_kill(at: Vector3, weapon: WeaponBase) -> void:
	var stacks := count_kind("spiders")
	if stacks <= 0 or weapon == null:
		return
	var wanted := mini(spiders_per_copy * stacks, _spider_budget())
	if wanted <= 0:
		return
	var targets := _nearest_enemies(at, wanted)
	if targets.is_empty():
		return
	var stats := PlayerStats.find_in(get_parent())
	var duration := spider_poison_duration * (stats.duration_multiplier if stats != null else 1.0)
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
		# Projectile reads a set extra_on_hit as "this came from an item" and
		# withholds the kill hooks, so spider kills cannot spawn spiders.
		spider.extra_on_hit = _poison_spider_victim.bind(duration)
		spider.tint(spider_color)


## Spiders still allowed this physics frame (the counter resets whenever a
## new frame asks).
func _spider_budget() -> int:
	var frame := int(Engine.get_physics_frames())
	if frame != _spider_frame:
		_spider_frame = frame
		_spiders_this_frame = 0
	return maxi(max_spiders_per_frame - _spiders_this_frame, 0)


## Points a pooled spider at `aim`. Both degenerate cases matter here: the
## target can sit exactly on the corpse, and it can sit straight above it
## (a climber on a wall, a burrower surfacing underneath), where look_at
## cannot build a basis from UP — and a pooled node that fails to orient
## keeps the previous flight's basis and shoots off across the map.
func _aim_spider(spider: Projectile, aim: Vector3) -> void:
	var to_aim := aim - spider.global_position
	if to_aim.length_squared() <= WeaponBase.DEGENERATE_LENGTH_SQ:
		# No usable direction at all: leap outward along the corpse's plane
		# rather than inheriting whatever the pool handed us.
		to_aim = Vector3.FORWARD
	spider.look_at(spider.global_position + to_aim, WeaponBase.safe_up(to_aim.normalized()))


func _poison_spider_victim(body: Node3D, duration: float) -> void:
	var enemy := body as EnemyBase
	if enemy != null:
		enemy.apply_poison(spider_poison_dps, duration)


## Up to `limit` live enemies closest to `at`, nearest first (dying bodies
## already left the group). Keeps a bounded best-of list instead of sorting
## the whole horde: `limit` is a handful of spiders while the group can hold
## hundreds of bodies, and this runs once per kill.
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
