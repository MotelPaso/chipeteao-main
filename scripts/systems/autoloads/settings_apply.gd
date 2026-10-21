extends Node
## Autoload "Settings": the single APPLIER of the persisted settings that
## SaveData stores (sfx/ambient volume, mouse sensitivity, fullscreen,
## FPS readout, graphics preset).
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

## --- Graphics preset (iteration 64) --------------------------------------
## Indexed by SaveData.graphics_quality: 0 Alta, 1 Media, 2 Baja.
##
## WHY THESE TWO KNOBS. The interface stretches in `canvas_items` mode,
## which renders the 3D at the window's NATIVE resolution (iteration 62):
## fullscreen on a MacBook retina is 3024x1964, 6.4 times the 1280x720 the
## game is designed at. Fragment cost scales with that pixel count, and the
## sun's four-split shadows re-draw every caster up to 100 m four more
## times. Those are the two biggest GPU levers that leave the game itself
## alone; the HUD stays sharp at any 3D scale because 2D is drawn apart.
##
## Alta is exactly what the game rendered before this preset existed.
const RENDER_SCALE_BY_QUALITY: Array[float] = [1.0, 0.75, 0.5]
## Sun shadow reach per preset; a negative value keeps what the arena
## authored, zero turns the sun's shadows off.
const SUN_SHADOW_DISTANCE_BY_QUALITY: Array[float] = [-1.0, 60.0, 0.0]
## Media's split count: half the shadow passes of the authored four, and
## at 60 m the farthest cascade the four bought is already under the fog.
const REDUCED_SUN_SHADOW_MODE := DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
## SubViewports a split-screen run draws the world through. The root
## viewport's 3D scale does not reach them, so SplitScreen.build puts each
## one in this group and the preset is applied to the group too.
const WORLD_VIEW_GROUP := &"world_views"
## Where a sun keeps the shadow setup its arena authored, so going back to
## Alta restores it instead of guessing the engine defaults.
const SUN_AUTHORED_META := &"authored_sun_shadow"

var _save_timer: Timer


func _ready() -> void:
	# The pause menu hosts the settings panel under a paused tree; the
	# debounce timer must keep ticking there.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_on_save_timeout)
	add_child(_save_timer)
	# Every stage brings its own arena and its own sun; the preset has to
	# reach each one. RunState is registered before this autoload.
	RunState.stage_changed.connect(func(_index: int, _map_id: String) -> void:
		_apply_sun_shadows())
	apply_all()


## Closing the window is the one exit that does not pass through the panel
## or the pause menu: without this, a slider moved in the last 0.8 s died
## with the app because only the debounce timer knew about it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush_save()


## Startup (and harness re-load) application of everything persisted.
func apply_all() -> void:
	_apply_bus_volume(Sfx.BUS_NAME, SaveData.sfx_volume)
	_apply_bus_volume(Sfx.AMBIENT_BUS_NAME, SaveData.ambient_volume)
	_apply_fullscreen(SaveData.fullscreen)
	apply_graphics()


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


## The HUD polls SaveData.show_fps, so flipping it is live everywhere at
## once — including a HUD that does not exist yet (menu -> run).
func set_show_fps(on: bool) -> void:
	SaveData.show_fps = on
	_request_save()


func set_graphics_quality(quality: int) -> void:
	SaveData.graphics_quality = clampi(quality, 0, SaveData.MAX_GRAPHICS_QUALITY)
	apply_graphics()
	_request_save()


## The 3D scale the current preset renders at (1.0 = native).
static func render_scale() -> float:
	return RENDER_SCALE_BY_QUALITY[clampi(SaveData.graphics_quality, 0,
			RENDER_SCALE_BY_QUALITY.size() - 1)]


## Gives one viewport the preset's 3D scale. FSR 1 below native — it is a
## spatial upscaler that works on every Forward+ driver, Metal included —
## and plain bilinear at 1.0, where nothing is scaled at all.
static func apply_render_scale(viewport: Viewport) -> void:
	if viewport == null:
		return
	var scale := render_scale()
	viewport.scaling_3d_scale = scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 \
			else Viewport.SCALING_3D_MODE_BILINEAR


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


## The preset in SaveData onto the viewports and the current scene's sun.
## Public for the soak harness, which re-points SaveData at its own save
## after this autoload already applied the player's.
func apply_graphics() -> void:
	apply_render_scale(get_tree().root)
	for node: Node in get_tree().get_nodes_in_group(WORLD_VIEW_GROUP):
		apply_render_scale(node as Viewport)
	_apply_sun_shadows()


## Every DirectionalLight3D under the current scene: the arena's sun in a
## run, nothing on the select screen. The first touch records what the
## arena authored on the light itself, which is what Alta goes back to.
func _apply_sun_shadows() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var distance: float = SUN_SHADOW_DISTANCE_BY_QUALITY[clampi(
			SaveData.graphics_quality, 0, SUN_SHADOW_DISTANCE_BY_QUALITY.size() - 1)]
	var suns := scene.find_children("*", "DirectionalLight3D", true, false)
	# One line per application (RunManager convention): what a soak greps
	# to prove the preset reached the arena it is standing in. The scale is
	# read back from the root viewport, not from the preset table, so the
	# line reports what is actually rendering.
	print("Graphics: quality=%d scale=%.2f suns=%d views=%d" % [
			SaveData.graphics_quality, get_tree().root.scaling_3d_scale, suns.size(),
			get_tree().get_node_count_in_group(WORLD_VIEW_GROUP)])
	for node: Node in suns:
		var sun := node as DirectionalLight3D
		if not sun.has_meta(SUN_AUTHORED_META):
			sun.set_meta(SUN_AUTHORED_META, [sun.shadow_enabled,
					sun.directional_shadow_mode, sun.directional_shadow_max_distance])
		var authored: Array = sun.get_meta(SUN_AUTHORED_META)
		if distance < 0.0:
			sun.shadow_enabled = authored[0]
			sun.directional_shadow_mode = authored[1]
			sun.directional_shadow_max_distance = authored[2]
		elif distance == 0.0:
			sun.shadow_enabled = false
		else:
			sun.shadow_enabled = authored[0]
			sun.directional_shadow_mode = REDUCED_SUN_SHADOW_MODE
			sun.directional_shadow_max_distance = minf(distance, authored[2])


static func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on
			else DisplayServer.WINDOW_MODE_WINDOWED)


func _request_save() -> void:
	# Timer.start(0) is an error in Godot; a zero debounce means "write now".
	if save_debounce <= 0.0:
		SaveData.save()
		return
	_save_timer.start(save_debounce)


func _on_save_timeout() -> void:
	SaveData.save()
