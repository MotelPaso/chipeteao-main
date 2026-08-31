extends CanvasLayer
## ScreenFade autoload: quarter-second fade-to-black around every scene
## change (select → run, run → select, retry, quest log) so cuts stop
## being abrupt. transition(action) fades in a full-screen black rect,
## runs the callable (which performs the actual change_scene/reload plus
## any cleanup), then fades back out. Draws above everything (layer 100),
## processes always and ignores time scale, so it works from paused
## run-end screens and mid hit-stop. Headless-safe: it is only a ColorRect
## tween. While busy, repeat requests are dropped — the first change wins
## and the fade never strands the game mid-black.

const FADE_IN_TIME := 0.22
const FADE_OUT_TIME := 0.26

var _rect: ColorRect
var _tween: Tween = null
var _busy: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.015, 0.018, 0.03)
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func transition(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks mid-cut
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_IN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(action)
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_OUT_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_clear_busy)


func _clear_busy() -> void:
	_busy = false
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
