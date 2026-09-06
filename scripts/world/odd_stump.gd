class_name OddStump
extends SecretTrigger
## Hollow Woods secret (GDD 6): among the decorative stumps sits one with
## a single glowing mushroom on top. Each interact makes it grumble louder
## (floating flavor line + a volume-ramped rumble and a bigger shudder);
## the third wakes what sleeps underneath. The awaken/spawn flow lives on
## SecretTrigger.

## Interacts needed to wake the miniboss.
@export var required_interacts: int = 3
## Flavor line per interact (index = interact number - 1; the list's last
## line repeats if the count somehow exceeds it).
@export var grumble_lines: Array[String] = [
	"Un gruñido sordo sube por las raíces...",
	"El gruñido crece. El hongo tiembla de rabia.",
	"¡Las raíces revientan!",
]
@export var grumble_sound: StringName = &"burrow_pop"
## First grumble's volume offset; each further interact adds the step, so
## the stump audibly grumbles louder every time.
@export var grumble_volume_start_db: float = -10.0
@export var grumble_volume_step_db: float = 5.0

## Interacts landed so far (test hook).
var interact_count: int = 0

@onready var _visual: Node3D = $Visual

var _shudder_tween: Tween


## Prompt and banner defaults live here, next to the other Interactable
## defaults; the scene only overrides them per instance.
func _init() -> void:
	prompt_text = "[E] Hurgar el tocón raro"
	awaken_text = "¡Algo gordo y furioso se abre paso entre las raíces!"


func _interact(_player: Node) -> void:
	_emit_started()
	interact_count += 1
	Sfx.play(grumble_sound,
			grumble_volume_start_db + grumble_volume_step_db * float(interact_count - 1))
	if not grumble_lines.is_empty():
		show_flavor(grumble_lines[mini(interact_count, grumble_lines.size()) - 1])
	_play_shudder()
	if interact_count >= required_interacts:
		_awaken()


## Quick squash pulse that grows with each poke, selling the rising anger.
func _play_shudder() -> void:
	var punch := 1.0 + 0.05 * float(interact_count)
	if _shudder_tween != null and _shudder_tween.is_valid():
		_shudder_tween.kill()
	_visual.scale = Vector3.ONE
	_shudder_tween = create_tween()
	_shudder_tween.tween_property(_visual, "scale", Vector3(punch, 2.0 - punch, punch), 0.08)
	_shudder_tween.tween_property(_visual, "scale", Vector3.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
