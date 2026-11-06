class_name OddStump
extends SecretTrigger
## Secreto del Bosque Hueco: entre los tocones decorativos hay uno con un solo
## hongo brillante encima. Cada interacción lo hace gruñir más fuerte (frase
## flotante, un retumbe con más volumen y una sacudida mayor); la tercera
## despierta lo que duerme debajo. El despertar vive en SecretTrigger.

## Interacciones necesarias para despertar al minijefe.
@export var required_interacts: int = 3
## Frase por interacción (índice = número de interacción - 1; si se acaban, se repite la última).
@export var grumble_lines: Array[String] = [
	"Un gruñido sordo sube por las raíces...",
	"El gruñido crece. El hongo tiembla de rabia.",
	"¡Las raíces revientan!",
]
## Sonido (id de Sfx) de cada gruñido.
@export var grumble_sound: StringName = &"burrow_pop"
## Volumen del primer gruñido en dB; cada interacción siguiente suma el paso.
@export var grumble_volume_start_db: float = -10.0
@export var grumble_volume_step_db: float = 5.0

## Interacciones hechas hasta ahora (lo lee el harness).
var interact_count: int = 0

@onready var _visual: Node3D = $Visual

var _shudder_tween: Tween


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


## Pulso de aplastamiento que crece con cada golpe, para que se note la rabia.
func _play_shudder() -> void:
	var punch := 1.0 + 0.05 * float(interact_count)
	if _shudder_tween != null and _shudder_tween.is_valid():
		_shudder_tween.kill()
	_visual.scale = Vector3.ONE
	_shudder_tween = create_tween()
	_shudder_tween.tween_property(_visual, "scale", Vector3(punch, 2.0 - punch, punch), 0.08)
	_shudder_tween.tween_property(_visual, "scale", Vector3.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
