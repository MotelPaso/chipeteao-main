class_name SecretTrigger
extends Interactable
## Base for the hidden-boss triggers (GDD 6): a disguised world object
## that, once its activation condition is met (subclass-defined), spends
## itself and spawns its miniboss nearby with a warning banner — the one
## awaken flow both secrets share. One use per run (consume pattern);
## scene reload resets it naturally. No meta stat: the quest counters ride
## on the miniboss KILL (SecretBossBase), not on the trigger.

## Hidden miniboss scene (root must extend BossBase) this trigger awakens.
@export var miniboss_scene: PackedScene
## Where the miniboss lands, relative to the trigger (world axes) — point
## it toward open ground/arena center.
@export var spawn_offset: Vector3 = Vector3(4.0, 0.1, -4.0)
## Boss-warning banner line shown through the "boss_ui" group on awaken.
@export var awaken_text: String = "Algo oculto se remueve..."

## The awakened miniboss instance (null until spawned; test hook).
var spawned_boss: BossBase = null


## Spends the trigger and brings out the miniboss. Idempotent guard on
## `available` so a subclass can never double-awaken.
func _awaken() -> void:
	if not available:
		return
	consume()
	dim_visuals()
	_emit_completed()
	get_tree().call_group("boss_ui", "announce", awaken_text)
	_spawn_miniboss()


func _spawn_miniboss() -> void:
	if miniboss_scene == null:
		return
	# The ARENA, not current_scene (iteration 49): a miniboss belongs to
	# the stage that woke it, and follows the map when the party leaves.
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null:
		return
	var node := miniboss_scene.instantiate()
	var boss := node as BossBase
	if boss == null:
		node.free()
		push_warning("SecretTrigger: miniboss scene root does not extend BossBase.")
		return
	spawned_boss = boss
	scene_root.add_child(boss)
	boss.global_position = global_position + spawn_offset
	# One-line log (spawner convention) so headless runs can confirm it.
	print("Secret miniboss awakened: %s" % boss.boss_title)


## Short floating flavor line above the trigger (the damage-popup styling,
## warmer color); parented to the scene root so it outlives state changes.
func show_flavor(line: String) -> void:
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null:
		return
	var label := Label3D.new()
	label.text = line
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.outline_size = 12
	label.modulate = Color(0.9, 0.98, 0.7)
	scene_root.add_child(label)
	label.global_position = global_position + Vector3.UP * 2.2
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.0, 1.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tween.chain().tween_callback(label.queue_free)
