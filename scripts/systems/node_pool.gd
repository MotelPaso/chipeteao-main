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

const META_OWNER: StringName = &"_node_pool_owner"

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
	# Mirror exactly what release() disabled; script state is pool_reset's job.
	node.visible = true
	node.set_physics_process(true)
	node.set_process(true)
	if node.has_method(&"pool_reset"):
		node.call(&"pool_reset")
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
	node.set_physics_process(false)
	node.set_process(false)
	_finish_release.call_deferred(node, id)


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
	# The node's scene may have been torn down between release() and this
	# deferred call (quit-to-menu with shots in flight); it died with it.
	if not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	if _parked.size() >= max_free:
		node.free()
		return
	_parked.append(node)
	peak_parked = maxi(peak_parked, _parked.size())


func _create_instance() -> Node3D:
	var node := scene.instantiate() as Node3D
	if node == null:
		push_warning("NodePool '%s': scene root is not a Node3D." % name)
		return null
	node.set_meta(META_OWNER, self)
	total_created += 1
	return node
