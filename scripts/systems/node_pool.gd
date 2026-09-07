class_name NodePool
extends Node
## Reusable instance pool for ONE PackedScene whose root extends Node3D.
## Contract (kept tiny on purpose): pooled scene scripts implement
## pool_reset(), called on every acquire AFTER the node is (re)parented, to
## restore just-spawned state (flight counters, hit sets, stale tweens).
## Parked nodes are held OUT of the tree — no processing, no physics
## presence, and they survive scene changes for free — while in-flight
## nodes are children of the current scene and simply die with it; the
## deferred release path guards that race. Owned and configured by the
## Pools autoload; not meant to be scattered through gameplay scenes.
##
## release()/acquire() are strictly symmetric: whatever release() switches
## off it first RECORDS on the node, and acquire() puts that exact value
## back. The pool never invents state (it used to force processing on
## every node, waking up FX scenes that define neither callback) and it
## never leaves a parked Area3D listening (a spent projectile kept
## reporting overlaps until its deferred reparent landed).

const META_OWNER: StringName = &"_node_pool_owner"
## Per-node snapshot of what release() switched off; presence of the first
## one is what tells acquire() this node has been parked before.
const META_PROCESS: StringName = &"_node_pool_process"
const META_PHYSICS_PROCESS: StringName = &"_node_pool_physics_process"
const META_MONITORING: StringName = &"_node_pool_monitoring"
const META_MONITORABLE: StringName = &"_node_pool_monitorable"

## Scene this pool instantiates; its root must be a Node3D.
@export var scene: PackedScene
## Instances created up front so early-run spawns never hitch.
@export var preload_count: int = 0
## Soft cap: released nodes beyond this many parked are freed instead of
## kept, bounding worst-case memory after a spike.
@export var max_free: int = 64

## Instances ever created (monotonic): the churn metric — in steady state
## it stops growing because every spawn is served from the parked list.
var total_created: int = 0
## Most nodes ever parked at once (post-spike high-water mark).
var peak_parked: int = 0

var _parked: Array[Node3D] = []
## Instance ids released this frame but not yet reparented (see release()).
var _pending_release: Dictionary[int, bool] = {}
## Instances currently OUT in the world (acquired and not yet parked).
## Tracked since iteration 49 because a stage swap has to reclaim them:
## before, an in-flight dart simply died with the scene, which is exactly
## the leak a persistent pool cannot afford — the node would be freed
## while the pool still counted it as created and never parked again.
var _live: Dictionary[int, Node3D] = {}


func _ready() -> void:
	for i: int in preload_count:
		var node := _create_instance()
		if node == null:
			break
		_parked.append(node)
	peak_parked = _parked.size()


func _notification(what: int) -> void:
	# Parked nodes live outside the tree, so nothing frees them implicitly;
	# do it when the pool itself is destroyed (app shutdown) to exit clean.
	if what == NOTIFICATION_PREDELETE:
		for node: Node3D in _parked:
			if is_instance_valid(node):
				node.free()
		_parked.clear()


## Hands out a pooled instance under `parent` (reusing a parked one when
## available, growing the pool otherwise), re-enabled and pool_reset().
func acquire(parent: Node) -> Node3D:
	if parent == null:
		return null
	var node: Node3D
	if _parked.is_empty():
		node = _create_instance()
		if node == null:
			return null
	else:
		node = _parked.pop_back()
	parent.add_child(node)
	# Put back exactly what release() recorded; script state is pool_reset's
	# job. A never-parked node keeps whatever entering the tree derived for
	# it, so FX scenes with no _process stay out of the process lists.
	node.visible = true
	if node.has_meta(META_PROCESS):
		node.set_process(node.get_meta(META_PROCESS))
		node.set_physics_process(node.get_meta(META_PHYSICS_PROCESS))
	var area := node as Area3D
	if area != null and node.has_meta(META_MONITORING):
		# Deferred to mirror release(): both sides land in call order, so a
		# same-frame release/acquire round trip ends up monitoring again.
		area.set_deferred(&"monitoring", node.get_meta(META_MONITORING))
		area.set_deferred(&"monitorable", node.get_meta(META_MONITORABLE))
	if node.has_method(&"pool_reset"):
		node.call(&"pool_reset")
	_live[node.get_instance_id()] = node
	return node


## Returns a node to the pool. Safe against double release (repeat calls
## are no-ops) and safe from inside physics callbacks: the node goes inert
## immediately, but the reparent is deferred because remove_child during an
## Area3D in/out signal flush is not allowed.
func release(node: Node3D) -> void:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	var id := node.get_instance_id()
	# Already pending, or already parked (parked nodes have no parent).
	if _pending_release.has(id) or node.get_parent() == null:
		return
	_pending_release[id] = true
	node.visible = false
	node.set_meta(META_PROCESS, node.is_processing())
	node.set_meta(META_PHYSICS_PROCESS, node.is_physics_processing())
	node.set_physics_process(false)
	node.set_process(false)
	var area := node as Area3D
	if area != null:
		# A released Area3D used to keep its shapes live until the deferred
		# reparent, so it still collected overlaps for the rest of the frame.
		# Deferred because monitoring cannot be touched during a signal flush.
		node.set_meta(META_MONITORING, area.monitoring)
		node.set_meta(META_MONITORABLE, area.monitorable)
		area.set_deferred(&"monitoring", false)
		area.set_deferred(&"monitorable", false)
	_finish_release.call_deferred(node, id)


## Reclaims every instance still out in the world, immediately (no
## deferred hop): a stage swap frees the arena those nodes are parented
## to, and anything left there would be freed behind the pool's back.
## Safe to call at any time — it is a no-op when nothing is out.
func release_all_live() -> void:
	for id: int in _live.keys():
		var node: Node3D = _live[id]
		_live.erase(id)
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		# A release is already in flight for this one; its deferred
		# _finish_release will park it. Touching it here would park it
		# twice.
		if _pending_release.has(id):
			continue
		var parent := node.get_parent()
		if parent == null:
			continue
		node.visible = false
		node.set_meta(META_PROCESS, node.is_processing())
		node.set_meta(META_PHYSICS_PROCESS, node.is_physics_processing())
		node.set_physics_process(false)
		node.set_process(false)
		var area := node as Area3D
		if area != null:
			node.set_meta(META_MONITORING, area.monitoring)
			node.set_meta(META_MONITORABLE, area.monitorable)
			area.monitoring = false
			area.monitorable = false
		parent.remove_child(node)
		if _parked.size() >= max_free:
			node.queue_free()
			continue
		_parked.append(node)
		peak_parked = maxi(peak_parked, _parked.size())


## Counters for the perf probe and soak harnesses.
func stats() -> Dictionary[String, int]:
	return {
		"created": total_created,
		"parked": _parked.size(),
		"pending": _pending_release.size(),
		"peak_parked": peak_parked,
	}


func parked_count() -> int:
	return _parked.size()


func _finish_release(node: Node3D, id: int) -> void:
	_pending_release.erase(id)
	_live.erase(id)
	# The node's scene may have been torn down between release() and this
	# deferred call (quit-to-menu with shots in flight); it died with it.
	if not is_instance_valid(node):
		return
	# Already parked (a stage swap reclaimed it synchronously between the
	# release and this deferred call): parking it twice would put the same
	# instance in _parked twice and hand it out to two callers at once.
	var parent := node.get_parent()
	if parent == null:
		return
	parent.remove_child(node)
	if _parked.size() >= max_free:
		# queue_free, not free: Pools.release hands over ownership, but a
		# caller that still holds the reference this frame must not be left
		# with a dangling pointer mid deferred-call flush.
		node.queue_free()
		return
	_parked.append(node)
	peak_parked = maxi(peak_parked, _parked.size())


func _create_instance() -> Node3D:
	if scene == null:
		push_error("NodePool '%s': no scene assigned." % name)
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		push_warning("NodePool '%s': scene root is not a Node3D." % name)
		return null
	node.set_meta(META_OWNER, self)
	total_created += 1
	return node
