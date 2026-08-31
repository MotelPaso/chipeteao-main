extends Node
## Autoload "Settings": the single APPLIER of the persisted settings that
## SaveData stores (sfx/ambient volume, mouse sensitivity, fullscreen).
## Registered after Sfx so both code-built buses exist, and before any
## scene loads so buses and window mode are right from the first frame.
## The settings panel writes through the set_* API here, which mutates
## SaveData, applies the value live, and debounces a disk save (flushed
## on panel close). Headless-safe: bus ops mix into the dummy driver and
## the window call is guarded on the headless DisplayServer.

## Sliders map 0..100 linearly onto this dB range; 0 additionally mutes
## the bus (a -40 dB floor alone is still faintly audible).
const MIN_VOLUME_DB := -40.0
const MAX_VOLUME_DB := 0.0
## Seconds of slider silence before a dirty change hits the disk.
@export var save_debounce: float = 0.8

var _save_timer: Timer


func _ready() -> void:
	# The pause menu hosts the settings panel under a paused tree; the
	# debounce timer must keep ticking there.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_on_save_timeout)
	add_child(_save_timer)
	apply_all()


## Startup (and harness re-load) application of everything persisted.
func apply_all() -> void:
	_apply_bus_volume(Sfx.BUS_NAME, SaveData.sfx_volume)
	_apply_bus_volume(Sfx.AMBIENT_BUS_NAME, SaveData.ambient_volume)
	_apply_fullscreen(SaveData.fullscreen)


## --- Panel API (clamp, store, apply live, schedule the save) -----------

func set_sfx_volume(value: float) -> void:
	SaveData.sfx_volume = clampf(value, 0.0, 100.0)
	_apply_bus_volume(Sfx.BUS_NAME, SaveData.sfx_volume)
	_request_save()


func set_ambient_volume(value: float) -> void:
	SaveData.ambient_volume = clampf(value, 0.0, 100.0)
	_apply_bus_volume(Sfx.AMBIENT_BUS_NAME, SaveData.ambient_volume)
	_request_save()


func set_mouse_sensitivity(value: float) -> void:
	SaveData.mouse_sensitivity = clampf(value,
			SaveData.MIN_MOUSE_SENSITIVITY, SaveData.MAX_MOUSE_SENSITIVITY)
	# The player reads SaveData.mouse_sensitivity per mouse event, so the
	# new value is live without any notification.
	_request_save()


func set_fullscreen(on: bool) -> void:
	SaveData.fullscreen = on
	_apply_fullscreen(on)
	_request_save()


## Panel close / quit-to-menu hook: lands any debounced change now.
func flush_save() -> void:
	if _save_timer.is_stopped():
		return
	_save_timer.stop()
	SaveData.save()


## --- Application --------------------------------------------------------

## 0..100 slider value -> bus dB (0 -> -40, 50 -> -20, 100 -> 0).
static func volume_to_db(value: float) -> float:
	return lerpf(MIN_VOLUME_DB, MAX_VOLUME_DB, clampf(value, 0.0, 100.0) / 100.0)


static func _apply_bus_volume(bus_name: StringName, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, volume_to_db(value))
	AudioServer.set_bus_mute(idx, value <= 0.0)


static func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on
			else DisplayServer.WINDOW_MODE_WINDOWED)


func _request_save() -> void:
	_save_timer.start(save_debounce)


func _on_save_timeout() -> void:
	SaveData.save()
