class_name ShotCamera
extends RefCounted
## The camera both soak harnesses carry (iteration 60), behind
## BONK_SHOT_DIR.
##
## WHY IT EXISTS. Every gate this project has ever run is --headless, and
## the dummy renderer compiles no shader and rasterises nothing: a ground
## mesh that is back-face culled, a material that never binds, a panel
## drawn on top of the clock and a label clipped to two letters all
## produce a perfectly green log. Iterations 51-59 shipped a terrain whose
## triangles faced away from every camera above them and no soak could
## say so. This class is how a soak looks at the screen.
##
## HOW IT CAPTURES. From INSIDE the engine —
## Viewport.get_texture().get_image() after RenderingServer.frame_post_draw
## — and never with a screen grabber: macOS refuses a terminal's
## `screencapture` without the Screen Recording permission, and a soak has
## nobody to grant one.
##
## It can only ADD frames. Nothing here changes what a harness asserts,
## and with the switch unset every line below is a no-op.

## Seconds between periodic shots when BONK_SHOT_EVERY is unset.
const SHOT_EVERY_DEFAULT: float = 10.0
const SHOT_DIR_ENV := "BONK_SHOT_DIR"
const SHOT_EVERY_ENV := "BONK_SHOT_EVERY"

var _dir: String = ""
var _on: bool = false
var _every: float = SHOT_EVERY_DEFAULT
## Counts DOWN to the next periodic shot. Fed with the caller's delta and
## never with RunState.run_time: run_time freezes while a menu owns the
## pause, and a menu is exactly the thing worth photographing.
var _left: float = 0.0
## Pending stems, taken one per DRAWN frame, so two events in the same
## frame produce two files instead of one image saved twice.
var _queue: Array[String] = []
var _busy: bool = false
var _taken: int = 0
var _viewport: Viewport = null
## Shots asked for with a delay, as {left, stem}. An EVENT is not the same
## thing as what the event looks like: the map overlay opens on the frame
## after the Tab press, a weather tint ramps in and a stage change is
## behind a fade, so a picture taken on the frame the event fires is a
## picture of the moment before it.
var _pending: Array[Dictionary] = []


## `viewport` is the one whose frames get saved — the harness's own
## get_viewport(), i.e. the window root, which is what composites the
## split-screen cells and every CanvasLayer above them.
func _init(viewport: Viewport, every_default: float = SHOT_EVERY_DEFAULT) -> void:
	_viewport = viewport
	_every = every_default
	var dir := OS.get_environment(SHOT_DIR_ENV).strip_edges()
	if dir.is_empty():
		return
	# The dummy DisplayServer never drew a frame and its viewport texture
	# is empty, so every PNG would be a lie. Said out loud exactly once: a
	# script that asked for pictures has to be able to see it got none.
	if DisplayServer.get_name() == "headless":
		print("Shots skipped: headless")
		return
	var every := OS.get_environment(SHOT_EVERY_ENV)
	if every.is_valid_float():
		_every = maxf(every.to_float(), 0.1)
	DirAccess.make_dir_recursive_absolute(dir)
	if not DirAccess.dir_exists_absolute(dir):
		push_warning("ShotCamera: cannot create %s '%s'" % [SHOT_DIR_ENV, dir])
		return
	_dir = dir
	_on = true
	_left = _every
	print("Shots on: dir=%s every=%.1fs" % [_dir, _every])


## What every caller tests instead of re-reading the environment.
func enabled() -> bool:
	return _on


func every() -> float:
	return _every


## Queues one shot under `stem` (no extension). Safe from anywhere,
## including a signal on a node that is about to free itself.
func request(stem: String) -> void:
	if _on:
		_queue.append(stem)


## Queues one shot `delay` seconds from now. See _pending: some events are
## worth photographing for what they LEAVE on screen, not for the frame
## they fire on.
func request_in(delay: float, stem: String) -> void:
	if not _on:
		return
	if delay <= 0.0:
		request(stem)
		return
	_pending.append({"left": delay, "stem": stem})


## Drives the periodic shot and drains the queue, one frame at a time.
## `periodic_stem` is a Callable returning the stem for the timed shot —
## a Callable and not a string because the name carries the run clock,
## which is only known at the moment the shot is due.
func tick(delta: float, periodic_stem: Callable) -> void:
	if not _on:
		return
	for index in range(_pending.size() - 1, -1, -1):
		var due: Dictionary = _pending[index]
		due["left"] = float(due["left"]) - delta
		if float(due["left"]) <= 0.0:
			_pending.remove_at(index)
			request(String(due["stem"]))
	_left -= delta
	if _left <= 0.0:
		_left = _every
		request(String(periodic_stem.call()))
	if _busy or _queue.is_empty():
		return
	_busy = true
	# Started, not awaited: the caller's frame has other work to do.
	_take(_queue.pop_front())


## One PNG, saved after the frame it belongs to has actually been DRAWN:
## get_image() before frame_post_draw hands back the PREVIOUS frame, which
## for an event shot is the frame before the event.
func _take(stem: String) -> void:
	await RenderingServer.frame_post_draw
	_busy = false
	var image := _frame()
	if image == null:
		push_warning("ShotCamera: no frame to save for '%s'" % stem)
		return
	_write(image, stem)


## `final.png`, grabbed WITHOUT the frame_post_draw await: this runs from
## an _exit_tree, where a coroutine parked on a signal is never resumed.
## The cost is one frame of staleness, and what it saves is the frame that
## was on screen when the harness ended.
func final_shot() -> void:
	if not _on:
		return
	var image := _frame()
	if image == null:
		push_warning("ShotCamera: no frame to save for final.png")
		return
	_write(image, "final")


## The window's last drawn frame, or null when there is no viewport left
## to read (teardown, or a display server that never drew).
func _frame() -> Image:
	if not is_instance_valid(_viewport):
		return null
	var texture := _viewport.get_texture()
	return texture.get_image() if texture != null else null


func _write(image: Image, stem: String) -> void:
	var path := "%s/%s.png" % [_dir, stem]
	# The run clock is frozen while a menu owns the pause, so two shots can
	# want the same name; the counter suffix keeps both instead of
	# overwriting. `final` is the one name that is meant to be overwritten.
	if stem != "final" and FileAccess.file_exists(path):
		path = "%s/%s-%d.png" % [_dir, stem, _taken]
	var error := image.save_png(path)
	if error != OK:
		push_warning("ShotCamera: cannot write '%s' (error %d)" % [path, error])
		return
	_taken += 1
	print("Shot saved: %s" % path)
