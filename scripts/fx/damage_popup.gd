class_name DamagePopup
extends Label3D
## Pooled floating combat text (damage numbers, "Dodge!"): identical look
## and motion to the old per-hit code-built Label3D — rises while fading,
## crit sizing/colors decided by the caller — but acquired and released
## through Pools instead of allocated per hit. Health._spawn_popup is the
## only caller and keeps its old API.

## Motion constants match the pre-pooling popup exactly.
const RISE_HEIGHT: float = 1.2
const RISE_TIME: float = 0.6
const FADE_DELAY: float = 0.25
const FADE_TIME: float = 0.35

var _tween: Tween = null


## Pooled-node contract: no stale motion from the previous flight.
func pool_reset() -> void:
	_kill_tween()


## Configures and plays one popup; the node releases itself when done.
func show_popup(popup_text: String, popup_font_size: int, color: Color, at: Vector3) -> void:
	text = popup_text
	font_size = popup_font_size
	modulate = color
	global_position = at
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "position:y", position.y + RISE_HEIGHT, RISE_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME).set_delay(FADE_DELAY)
	_tween.chain().tween_callback(_on_popup_done)


func _on_popup_done() -> void:
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
