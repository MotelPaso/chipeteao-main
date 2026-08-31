extends Node
## Autoload "Pools": one NodePool per high-churn scene (XP gems, player
## projectiles, enemy bolts, death bursts, damage popups, telegraph discs)
## so late-run hordes stop paying per-spawn allocation/free costs.
## Call sites swap instantiate/add_child for acquire_scene() and
## queue_free() for release(); everything else about the spawned node
## (transform, launch params) is still the caller's business.
## acquire_scene() parents to the current scene, so in-flight nodes die
## with a scene change while parked ones (out of tree) carry over clean.

const XP_GEM_SCENE: PackedScene = preload("res://scenes/systems/XpGem.tscn")
const DART_SCENE: PackedScene = preload("res://scenes/weapons/Projectile.tscn")
const ARROW_SCENE: PackedScene = preload("res://scenes/weapons/Arrow.tscn")
const BOOMERANG_SCENE: PackedScene = preload("res://scenes/weapons/BoomerangProjectile.tscn")
const ENEMY_BOLT_SCENE: PackedScene = preload("res://scenes/enemies/EnemyBolt.tscn")
const DEATH_BURST_SCENE: PackedScene = preload("res://scenes/fx/DeathBurst.tscn")
const DAMAGE_POPUP_SCENE: PackedScene = preload("res://scenes/fx/DamagePopup.tscn")
const TELEGRAPH_DISC_SCENE: PackedScene = preload("res://scenes/fx/TelegraphDisc.tscn")

## Per-pool (warm preload count, max parked kept) tunables. Preloads cover
## a normal early game; caps absorb the worst late-T3 multi-weapon spikes.
@export var pool_sizes: Dictionary[String, Vector2i] = {
	"gem": Vector2i(48, 256),
	"dart": Vector2i(16, 96),
	"arrow": Vector2i(16, 96),
	"boomerang": Vector2i(4, 24),
	"enemy_bolt": Vector2i(16, 96),
	"death_burst": Vector2i(12, 64),
	"damage_popup": Vector2i(48, 256),
	"telegraph_disc": Vector2i(6, 32),
}

var _pools_by_path: Dictionary[String, NodePool] = {}


func _ready() -> void:
	_register("gem", XP_GEM_SCENE)
	_register("dart", DART_SCENE)
	_register("arrow", ARROW_SCENE)
	_register("boomerang", BOOMERANG_SCENE)
	_register("enemy_bolt", ENEMY_BOLT_SCENE)
	_register("death_burst", DEATH_BURST_SCENE)
	_register("damage_popup", DAMAGE_POPUP_SCENE)
	_register("telegraph_disc", TELEGRAPH_DISC_SCENE)


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


func _register(pool_name: String, packed: PackedScene) -> void:
	var size: Vector2i = pool_sizes.get(pool_name, Vector2i(0, 64))
	var pool := NodePool.new()
	pool.name = pool_name
	pool.scene = packed
	pool.preload_count = size.x
	pool.max_free = size.y
	add_child(pool)
	_pools_by_path[packed.resource_path] = pool


func _spawn_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root
