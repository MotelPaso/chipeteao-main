class_name ItemBag
extends Node
## Per-raider item holder (iteration 40), mounted on the Player beside
## Stats. Counts every ItemCatalog item picked up this run (unlimited
## copies), feeds the stat-effect items into the sibling PlayerStats
## (which reads count(id) in its recompute) and runs the behavioral ones:
## Pets are NOT here any more (iteration 54): the run has one companion
## slot, owned by Player.set_pet(), and it is filled only by the pet box
## and the animal trafficker — never by a chest or a roulette roll.
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

## --- iteration 56 items -----------------------------------------------------
## Zenkai stacks, read by PlayerStats as a permanent all-stat channel.
## Public because that is exactly what the stat layer needs to see.
var zenkai_stacks: int = 0

@export_group("Electric belt")
## Damage of the first bolt and the growth per extra copy live on BeltBolt;
## this is only how far the chain reaches for its first target.
@export var belt_first_range: float = 10.0
@export_group("Saiyan blood")
@export var kills_per_aura: int = 40
## Each extra copy shortens the count; never below the floor, or the aura
## would be permanent and stop reading as an event.
@export var aura_kills_per_copy_scale: float = 0.85
@export var aura_kills_floor: int = 15
@export var aura_duration: float = 12.0
@export var aura_damage: float = 40.0
@export var aura_cooldown: float = 25.0
@export var aura_move_speed: float = 20.0
@export_group("Zenkai")
## Arms below this share of max HP, triggers on getting back above the
## other one. Two thresholds and not one: the raider has to actually be
## brought back, not wobble across a single line.
@export var zenkai_arm_ratio: float = 0.1
@export var zenkai_trigger_ratio: float = 0.5

## Tag for the aura's timed boons, so re-triggering REPLACES its own copy
## instead of stacking a second aura on top of the first.
const SAIYAN_TAG: String = "saiyan"
const AURA_TINT := Color(1.0, 0.85, 0.25)

var _belt: BeltBolt = null
var _saiyan_kills: int = 0
var _aura_left: float = 0.0
var _aura_overlays: Array[MeshInstance3D] = []
var _zenkai_armed: bool = false

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


func _ready() -> void:
	var body := get_parent()
	if body == null:
		return
	if body.has_signal("slide_started"):
		body.connect("slide_started", _on_slide_started)
	var health := Health.find_in(body)
	if health != null:
		# damaged() is the ONLY signal a combat dip raises: take_damage
		# never emits hp_changed. Arming there and triggering on hp_changed
		# is what makes "went low AND came back" two separate facts.
		health.damaged.connect(_on_health_damaged)
		health.hp_changed.connect(_on_health_hp_changed)


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
	# Stat effects live in PlayerStats' recompute (it reads this bag).
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()
	items_changed.emit(item_id, count(item_id))
	# Loot toast (iteration 47): ONE call for every source — chests, the
	# roulette, anything later — because this is the single door every
	# item comes through. A source-side announce would have to be written
	# again for each new source, and the roulette's never was.
	var owner_index: Variant = get_parent().get("player_index") \
			if get_parent() != null else null
	get_tree().call_group("hud", "show_loot", String(row.display_name),
			String(row.get("description", "")),
			ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
			int(owner_index) if owner_index != null else 0)
	# Bestiary-style discovery counter for future Collection pages.
	SaveData.bump("item_" + item_id)


## Gives ONE copy back (the lucky block's well trades an item for a better
## one). False when the raider does not carry it, so a caller can tell a
## refused trade from a completed one.
func remove_item(item_id: String) -> bool:
	var held := count(item_id)
	if held <= 0:
		return false
	if held == 1:
		_counts.erase(item_id)
	else:
		_counts[item_id] = held - 1
	# Same three follow-ups add_item does, in the same order: the visual
	# scale is derived from the count, and the stat layer reads this bag.
	if String(ItemCatalog.by_id(item_id).get("kind", "")) == "titan":
		_apply_titan_scale()
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()
	items_changed.emit(item_id, count(item_id))
	return true


func _physics_process(delta: float) -> void:
	if _aura_left > 0.0:
		_aura_left -= delta
		if _aura_left <= 0.0:
			_apply_aura_shell(false)
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
## --- electric belt ----------------------------------------------------------

## The dash IS the trigger. The chain starts from the RAIDER's position,
## never from this node: ItemBag extends Node and has no transform, so a
## Node3D child of it sits at the world origin.
func _on_slide_started(_direction: Vector3) -> void:
	var copies := count_kind("shock_dash")
	if copies <= 0:
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	if _belt == null or not is_instance_valid(_belt):
		_belt = BeltBolt.new()
		_belt.name = "BeltBolt"
		_belt.first_range = belt_first_range
		# Under the BAG, not the Weapons mount: everything that enumerates
		# weapons walks that mount, so a bolt parked there would show up in
		# the HUD strip, count against the five-weapon cap and enter the
		# level-up pool.
		add_child(_belt)
	var hits := _belt.zap_chain(body.global_position, copies)
	if hits > 0:
		# One line per dash, and dashes are rare enough for that to stay
		# readable in a soak.
		print("Belt bolt: hits=%d" % hits)


## --- saiyan blood -----------------------------------------------------------

## Kills needed for the next aura at this many copies.
func _aura_threshold(copies: int) -> int:
	var wanted := float(kills_per_aura) * pow(aura_kills_per_copy_scale, float(copies - 1))
	return maxi(roundi(wanted), aura_kills_floor)


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
	var scale := float(copies)
	# TAGGED: a second aura replaces the first instead of stacking with it,
	# which is what keeps a long run from ending in a permanent tripled
	# raider.
	stats.add_timed_boon("damage", aura_damage * scale, aura_duration, SAIYAN_TAG)
	stats.add_timed_boon("cooldown", aura_cooldown * scale, aura_duration, SAIYAN_TAG)
	stats.add_timed_boon("move_speed", aura_move_speed * scale, aura_duration, SAIYAN_TAG)
	_aura_left = aura_duration
	_apply_aura_shell(true)
	var body := get_parent() as Node3D
	if body != null:
		Juice.burst(body.global_position + Vector3.UP * 1.0, AURA_TINT, 24)
	get_tree().call_group("hud", "announce", "¡Aura sayayin!")
	print("Saiyan aura: kills=%d" % _aura_threshold(copies))


## Golden shell over the seal's meshes, the way Juice.flash does it —
## material_overlay, restored on the way out. NEVER SealRig.apply_tint,
## which is the character's identity colour and would stay changed.
func _apply_aura_shell(on: bool) -> void:
	if not on:
		for mesh: MeshInstance3D in _aura_overlays:
			if is_instance_valid(mesh):
				mesh.material_overlay = null
		_aura_overlays.clear()
		return
	var rig := get_parent().get_node_or_null("SealRig") as Node3D
	if rig == null:
		return
	var shell := StandardMaterial3D.new()
	shell.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell.albedo_color = Color(AURA_TINT, 0.4)
	shell.emission_enabled = true
	shell.emission = AURA_TINT
	shell.emission_energy_multiplier = 2.0
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			mesh.material_overlay = shell
			_aura_overlays.append(mesh)


## --- zenkai -----------------------------------------------------------------

## Arms on a real combat dip. take_damage never emits hp_changed, so this
## signal is the only one that means "something hurt me".
func _on_health_damaged(_amount: float, current: float) -> void:
	if count_kind("zenkai") <= 0:
		return
	var health := Health.find_in(get_parent())
	if health != null and current <= health.max_hp * zenkai_arm_ratio:
		_zenkai_armed = true


## Triggers when the raider is back on their feet. Signals raised DURING a
## recompute are ignored: _push_bonus_max_hp_to_health writes max_hp and
## heals from inside that body, which would read as "healed back" and let
## Zenkai trigger off its own stat rebuild, forever.
func _on_health_hp_changed(current: float, max_hp: float) -> void:
	if not _zenkai_armed or count_kind("zenkai") <= 0:
		return
	var stats := PlayerStats.find_in(get_parent())
	if stats != null and stats.is_recomputing():
		return
	if current < max_hp * zenkai_trigger_ratio:
		return
	_zenkai_armed = false
	zenkai_stacks += count_kind("zenkai")
	# Deferred: this runs from inside a signal the stat layer may be about
	# to read, and recomputing in place would re-enter it.
	_request_recompute.call_deferred()
	get_tree().call_group("hud", "announce",
			"¡Zenkai! Todo +%d%%" % roundi(float(zenkai_stacks)
					* PlayerStats.ZENKAI_PERCENT_PER_STACK))
	print("Zenkai triggered: stacks=%d" % zenkai_stacks)


func _request_recompute() -> void:
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()


func on_weapon_kill(at: Vector3, weapon: WeaponBase) -> void:
	# Power-ups relay off the same hook (iteration 53): this is already
	# THE "a weapon of mine just killed something" callback, and giving
	# Modo vampiro its own would mean a second wiring in WeaponBase.
	var powerups := PowerUps.find_in(get_parent())
	if powerups != null:
		powerups.on_kill()
	_tick_saiyan_kill()
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
