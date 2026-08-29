class_name CurseShrine
extends Interactable
## Curse Shrine (GDD 4): a cracked, red-glowing obelisk. Activating marks
## the run cursed (+stacks_per_use on the RunState counter): the NEXT boss
## to spawn consumes every active stack, arriving stronger but paying out
## far richer (the multipliers live as exports on the boss — see
## Rotking.apply_curse; the spawner wires the two together). One use.

@export var stacks_per_use: int = 1
@export var activation_text: String = "A grudge binds itself to the next great foe..."


func _interact(_player: Node) -> void:
	_emit_started()
	RunState.add_curse(stacks_per_use)
	get_tree().call_group("hud", "announce", activation_text)
	consume()
	dim_visuals()
	_emit_completed()
