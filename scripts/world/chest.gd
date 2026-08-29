class_name Chest
extends Interactable
## Treasure chest (GDD 4): guaranteed loot, some placed on top of the
## verticality spots so ramps and jumps pay off. Interacting plays a small
## hop while the lid swings open, then pops a free upgrade-card pick at
## standard rarity (UpgradeCardUI via the "upgrade_ui" group). One use;
## the chest stays open afterwards.

@export var open_title: String = "Chest opened — take your prize"
## Seconds the lid swing takes; the card pick opens once it finishes.
@export var open_duration: float = 0.45
## Lid pivot X rotation when fully open (hinged at the back edge).
@export var lid_open_angle: float = -1.75

@onready var _lid_pivot: Node3D = $Visual/LidPivot


func _init() -> void:
	meta_stat_id = "chests_opened"


func _interact(_player: Node) -> void:
	_emit_started()
	consume()
	var rest_y := position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_lid_pivot, "rotation:x", lid_open_angle, open_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", rest_y + 0.3, open_duration * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "position:y", rest_y, open_duration * 0.6) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_pop_reward)


func _pop_reward() -> void:
	get_tree().call_group("upgrade_ui", "open_bonus_pick", open_title, 0.0, "")
	_emit_completed()
