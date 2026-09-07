extends CanvasLayer
## ScreenFade autoload: quarter-second fade-to-black around every scene
## change (select → run, run → select, retry, quest log) so cuts stop
## being abrupt. transition(action) fades in a full-screen black rect,
## runs the callable (which performs the actual change_scene/reload plus
## any cleanup), then fades back out. Draws above everything (layer 100),
## processes always and ignores time scale, so it works from paused
## run-end screens and mid hit-stop. Headless-safe: it is only a ColorRect
## tween.
##
## transition_async() is the awaiting variant, for work that spans frames
## (the stage swap). While busy, repeat requests are DROPPED and both
## return false
## — the first change wins and the fade never strands the game mid-black.
## Callers must therefore put their irreversible cleanup INSIDE the
## callable (or check the return), never before the call: the busy window
## outlives the scene swap by FADE_OUT_TIME.
##
## leave_run() is the one ritual for ending a run: it owns the cleanup,
## the reset and the swap, and keeps the tree paused across the cut.

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


## Returns false when a fade is already running and this request was
## dropped without doing anything.
func transition(action: Callable) -> bool:
	if _busy:
		return false
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks mid-cut
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_IN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(action)
	# Give the mouse back with the cut, not with the flag: the rect keeps
	# fading for another FADE_OUT_TIME over the scene the player can
	# already see, and swallowing those clicks reads as a frozen UI.
	_tween.tween_callback(_release_mouse)
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_OUT_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_clear_busy)
	return true


## Async sibling of transition(): AWAITS the action between the fade-in
## and the fade-out. transition() cannot — its action runs inside a
## tween_callback, and a callback that is a coroutine returns to the tween
## the moment it hits its first await, so the screen would come back in
## the middle of the work. The stage swap needs several frames (frees
## settle, the next arena builds), which is what this exists for.
##
## Same busy contract as transition(): a request landing while another
## fade runs is DROPPED and returns false, so the caller can decide
## whether to retry.
func transition_async(action: Callable) -> bool:
	if _busy:
		return false
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks mid-cut
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_IN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _tween.finished
	await action.call()
	# Give the mouse back with the cut, not with the flag (see transition).
	_release_mouse()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_OUT_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _tween.finished
	_clear_busy()
	return true


## The one way to leave a live run (retry, back to the select, abandon
## from the pause menu). Owns the whole ritual so no caller can forget a
## step: flush the settings save, stop the audio loops, drop the run state
## and swap scenes. An empty scene_path reloads the current arena.
##
## The tree stays PAUSED across the swap on purpose. change_scene_to_file
## and reload_current_scene are deferred, so unpausing here would hand the
## outgoing arena one more live frame of a run that is already over:
## enemies dying in it credit kills to the NEXT run and the world director
## keeps firing events into a scene about to be freed.
func leave_run(scene_path: String = "") -> bool:
	return transition(func() -> void:
		Settings.flush_save()
		Sfx.stop_all_loops()
		get_tree().paused = true
		RunState.reset()
		if scene_path.is_empty():
			get_tree().reload_current_scene()
		else:
			get_tree().change_scene_to_file(scene_path)
		_unpause_after_swap())


## Hands the pause back once the deferred swap has landed — two frames,
## because the first one still belongs to the outgoing tree. Safe to await
## here and nowhere else: this autoload is the only node that survives the
## scene change.
func _unpause_after_swap() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false


func _release_mouse() -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _clear_busy() -> void:
	_busy = false
	_release_mouse()
