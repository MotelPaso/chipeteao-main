class_name Health
extends Node
## Reusable health component. Attach as a child of any body; bodies in the
## "enemies" group with a Health child are damageable by weapons.
## Emits died once when HP reaches zero; heal_full() re-arms it.

signal damaged(amount: float, current: float)
## Emitted alongside `damaged` when the hit named its attacker (enemy
## contact damage does); thorns-style retaliation hooks onto this.
signal damaged_by(attacker: Node3D)
## Emitted instead of `damaged` when the owner fully evaded the hit (the
## player's evasion roll); dodge-execute passives hook onto this. The
## attacker is whatever the dodged hit named, possibly null.
signal dodged(attacker: Node3D)
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

const DODGE_POPUP_COLOR := Color(0.5, 0.88, 1.0)

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


## `attacker` (optional) is the body that dealt the hit; contact attackers
## pass themselves so thorns can retaliate through damaged_by.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null) -> void:
	if is_dead or amount <= 0.0:
		return
	var evade_chance := _evasion_chance()
	if evade_chance > 0.0 and randf() < evade_chance:
		if show_damage_popups:
			_spawn_popup("Dodge!", 64, DODGE_POPUP_COLOR)
		Sfx.play(&"dodge")
		dodged.emit(attacker)
		return
	var final_amount := minf(amount, maxf(amount - armor, 1.0))
	current_hp = maxf(current_hp - final_amount, 0.0)
	if show_damage_popups:
		_spawn_damage_popup(final_amount, is_crit)
	damaged.emit(final_amount, current_hp)
	# Before the death check so even a lethal blow is repaid.
	if attacker != null:
		damaged_by.emit(attacker)
	if current_hp <= 0.0:
		is_dead = true
		died.emit()


## Voluntary HP payment (Greed Shrine): unlike take_damage it ignores
## armor, spawns no popup, and can never kill — the cost is clamped so at
## least min_remaining HP stays. Returns the HP actually paid.
func pay(amount: float, min_remaining: float = 1.0) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var paid := minf(amount, maxf(current_hp - min_remaining, 0.0))
	current_hp -= paid
	hp_changed.emit(current_hp, max_hp)
	return paid


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


## Chance (0-1) this body fully evades a hit: only the player evades, read
## from its PlayerStats layer (which caps the stat); enemies never roll.
func _evasion_chance() -> float:
	var body := get_parent()
	if body == null or not body.is_in_group("player"):
		return 0.0
	var stats := PlayerStats.find_in(body)
	return stats.evasion if stats != null else 0.0


func _spawn_damage_popup(amount: float, is_crit: bool) -> void:
	_spawn_popup(str(roundi(amount)), 88 if is_crit else 64,
			Color(1.0, 0.3, 0.15) if is_crit else Color(1.0, 0.85, 0.25))


func _spawn_popup(popup_text: String, popup_font_size: int, color: Color) -> void:
	var scene_root := get_tree().current_scene
	var body := get_parent() as Node3D
	if scene_root == null or body == null:
		return
	var label := Label3D.new()
	label.text = popup_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = popup_font_size
	label.outline_size = 16
	label.modulate = color
	# Parented to the scene root so the popup survives the body dying.
	scene_root.add_child(label)
	label.global_position = body.global_position \
			+ Vector3(randf_range(-0.3, 0.3), 2.0, randf_range(-0.3, 0.3))
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
