extends Node
## Autoload "Pools": one NodePool per high-churn scene (XP gems, health
## orbs, player projectiles, enemy bolts, FX bursts, damage popups,
## telegraph discs) so late-run hordes stop paying per-spawn
## allocation/free costs.
## Call sites swap instantiate/add_child for acquire_scene() and
## queue_free() for release(); everything else about the spawned node
## (transform, launch params) is still the caller's business.
## acquire_scene() parents to the ARENA of the current stage, so in-flight
## nodes die with the map while parked ones (out of tree) carry over
## clean; release_all_live() reclaims the in-flight ones before a stage
## swap frees that arena.
##
## Adding a pooled scene is ONE row in POOLS below — the const preload, the
## registration and the sizes used to be three parallel lists that drifted
## apart in silence (a name typo just fell back to a default size).

const XP_GEM_SCENE: PackedScene = preload("res://scenes/systems/XpGem.tscn")
const HEALTH_ORB_SCENE: PackedScene = preload("res://scenes/systems/HealthOrb.tscn")
const DART_SCENE: PackedScene = preload("res://scenes/weapons/Projectile.tscn")
const ARROW_SCENE: PackedScene = preload("res://scenes/weapons/Arrow.tscn")
const BOOMERANG_SCENE: PackedScene = preload("res://scenes/weapons/BoomerangProjectile.tscn")
const ENEMY_BOLT_SCENE: PackedScene = preload("res://scenes/enemies/EnemyBolt.tscn")
const DEATH_BURST_SCENE: PackedScene = preload("res://scenes/fx/DeathBurst.tscn")
const DAMAGE_POPUP_SCENE: PackedScene = preload("res://scenes/fx/DamagePopup.tscn")
const TELEGRAPH_DISC_SCENE: PackedScene = preload("res://scenes/fx/TelegraphDisc.tscn")
const SLASH_ARC_SCENE: PackedScene = preload("res://scenes/fx/SlashArc.tscn")
const MUZZLE_FLASH_SCENE: PackedScene = preload("res://scenes/fx/MuzzleFlash.tscn")
const WHIP_CRACK_SCENE: PackedScene = preload("res://scenes/fx/WhipCrack.tscn")
const EMBER_BURST_SCENE: PackedScene = preload("res://scenes/fx/EmberBurst.tscn")
const BLOOD_POOL_SCENE: PackedScene = preload("res://scenes/fx/BloodPool.tscn")

## The pooled roster: name, scene, `warm` (instances built at boot so early
## spawns never hitch) and `cap` (max parked kept, bounding memory after a
## late-T3 multi-weapon spike). One row per pooled scene.
const POOLS: Array[Dictionary] = [
	{"name": "gem", "scene": XP_GEM_SCENE, "warm": 48, "cap": 256},
	{"name": "health_orb", "scene": HEALTH_ORB_SCENE, "warm": 4, "cap": 16},
	{"name": "dart", "scene": DART_SCENE, "warm": 16, "cap": 96},
	{"name": "arrow", "scene": ARROW_SCENE, "warm": 16, "cap": 96},
	{"name": "boomerang", "scene": BOOMERANG_SCENE, "warm": 4, "cap": 24},
	{"name": "enemy_bolt", "scene": ENEMY_BOLT_SCENE, "warm": 16, "cap": 96},
	{"name": "death_burst", "scene": DEATH_BURST_SCENE, "warm": 12, "cap": 64},
	{"name": "damage_popup", "scene": DAMAGE_POPUP_SCENE, "warm": 48, "cap": 256},
	{"name": "telegraph_disc", "scene": TELEGRAPH_DISC_SCENE, "warm": 6, "cap": 32},
	{"name": "slash_arc", "scene": SLASH_ARC_SCENE, "warm": 8, "cap": 32},
	{"name": "muzzle_flash", "scene": MUZZLE_FLASH_SCENE, "warm": 6, "cap": 24},
	{"name": "whip_crack", "scene": WHIP_CRACK_SCENE, "warm": 4, "cap": 16},
	{"name": "ember_burst", "scene": EMBER_BURST_SCENE, "warm": 4, "cap": 16},
	{"name": "blood_pool", "scene": BLOOD_POOL_SCENE, "warm": 4, "cap": 16},
]

## Optional per-name (warm, cap) override for tuning experiments; rows not
## listed keep the POOLS values.
@export var pool_size_overrides: Dictionary[String, Vector2i] = {}

var _pools_by_path: Dictionary[String, NodePool] = {}


## Stage-swap hook (RunRoot): every pool reclaims what it has out in the
## world, so the arena about to be freed takes nothing pooled with it.
func release_all_live() -> void:
	for path: String in _pools_by_path:
		_pools_by_path[path].release_all_live()


func _ready() -> void:
	for row: Dictionary in POOLS:
		_register(String(row["name"]), row["scene"] as PackedScene,
				Vector2i(int(row["warm"]), int(row["cap"])))


## Pooled replacement for scene.instantiate() + add_child(current scene):
## returns a live, reset instance already inside the tree, or null only
## when the tree itself is unavailable. Scenes without a registered pool
## fall back to a plain parented instantiate, so call sites never care.
func acquire_scene(packed: PackedScene) -> Node3D:
	if packed == null:
		return null
	var parent := _spawn_parent()
	if parent == null:
		return null
	var pool: NodePool = _pools_by_path.get(packed.resource_path, null)
	if pool != null:
		return pool.acquire(parent)
	var node := packed.instantiate() as Node3D
	if node != null:
		parent.add_child(node)
		# The fallback must honour the same contract as a pooled acquire:
		# XpGem/HealthOrb join their live group inside pool_reset(), so an
		# unregistered gem variant used to be invisible to the magnet and to
		# the health-orb soft cap.
		if node.has_method(&"pool_reset"):
			node.call(&"pool_reset")
	return node


## Pooled replacement for queue_free(): routes the node back to the pool
## that created it (double-release safe); non-pooled nodes just queue_free.
func release(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var pool := node.get_meta(NodePool.META_OWNER, null) as NodePool
	if pool != null and is_instance_valid(pool):
		pool.release(node)
	elif not node.is_queued_for_deletion():
		node.queue_free()


## name -> NodePool.stats() for every pool (perf probe, soak harnesses).
func pool_stats() -> Dictionary[String, Dictionary]:
	var out: Dictionary[String, Dictionary] = {}
	for path: String in _pools_by_path:
		var pool: NodePool = _pools_by_path[path]
		out[String(pool.name)] = pool.stats()
	return out


## Compact one-line "name created/parked" readout for the perf probe.
func stats_line() -> String:
	var parts := PackedStringArray()
	for path: String in _pools_by_path:
		var pool: NodePool = _pools_by_path[path]
		parts.append("%s %d/%d" % [pool.name, pool.total_created, pool.parked_count()])
	return " | ".join(parts)


func _register(pool_name: String, packed: PackedScene, size: Vector2i) -> void:
	if packed == null:
		push_error("Pools: pool '%s' has no scene; skipped." % pool_name)
		return
	if pool_size_overrides.has(pool_name):
		size = pool_size_overrides[pool_name]
	var pool := NodePool.new()
	pool.name = pool_name
	pool.scene = packed
	pool.preload_count = size.x
	pool.max_free = size.y
	add_child(pool)
	_pools_by_path[packed.resource_path] = pool


## Where pooled nodes are parented: the ARENA of the current stage
## (iteration 49), so an in-flight dart dies with the map it was fired in
## instead of following the party to the next one. Falls back to
## current_scene where there is no run root — the menus, and any future
## scene that pools something outside a run.
func _spawn_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.get_first_node_in_group("run_root")
	if root != null and root.has_method("arena_root"):
		var arena: Variant = root.call("arena_root")
		if arena is Node3D and is_instance_valid(arena):
			return arena
	return tree.current_scene if tree.current_scene != null else tree.root
