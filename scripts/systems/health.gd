class_name Health
extends Node
## Reusable health component. Attach as a child of any body; bodies in the
## "enemies" group with a Health child are damageable by weapons.
## Emits died once when HP reaches zero; heal_full() re-arms it.

signal damaged(amount: float, current: float)
## Non-damage HP changes (max_hp raises, full heals) so health bars can
## re-read both values; damage keeps the dedicated signal above.
signal hp_changed(current: float, max_hp: float)
signal died

@export var max_hp: float = 50.0:
	set(value):
		max_hp = value
		hp_changed.emit(current_hp, max_hp)
@export var show_damage_popups: bool = true
## Flat damage reduction applied before HP loss; the player's PlayerStats
## layer writes this from Tome of Stone stacks. A hit always chips at least
## 1 HP (or the raw amount when it was already below 1).
@export var armor: float = 0.0

var current_hp: float
var is_dead: bool = false


func _ready() -> void:
	current_hp = max_hp


## Finds the Health component on a body, or null if it has none.
static func find_in(body: Node) -> Health:
	for child in body.get_children():
		if child is Health:
			return child
	return null


func take_damage(amount: float, is_crit: bool = false) -> void:
	if is_dead or amount <= 0.0:
		return
	var final_amount := minf(amount, maxf(amount - armor, 1.0))
	current_hp = maxf(current_hp - final_amount, 0.0)
	if show_damage_popups:
		_spawn_damage_popup(final_amount, is_crit)
	damaged.emit(final_amount, current_hp)
	if current_hp <= 0.0:
		is_dead = true
		died.emit()


## Partial heal (lifesteal etc.): clamped to max_hp, no-op once dead.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)


func heal_full() -> void:
	current_hp = max_hp
	is_dead = false
	hp_changed.emit(current_hp, max_hp)


func _spawn_damage_popup(amount: float, is_crit: bool) -> void:
	var scene_root := get_tree().current_scene
	var body := get_parent() as Node3D
	if scene_root == null or body == null:
		return
	var label := Label3D.new()
	label.text = str(roundi(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 88 if is_crit else 64
	label.outline_size = 16
	label.modulate = Color(1.0, 0.3, 0.15) if is_crit else Color(1.0, 0.85, 0.25)
	# Parented to the scene root so the popup survives the body dying.
	scene_root.add_child(label)
	label.global_position = body.global_position \
			+ Vector3(randf_range(-0.3, 0.3), 2.0, randf_range(-0.3, 0.3))
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
