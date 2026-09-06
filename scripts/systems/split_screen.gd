class_name SplitScreen
extends Control
## Local co-op split-screen (2-4 players), built in code by RunSystems.
## One SubViewportContainer per player, each with a SubViewport sharing
## the main 3D world and a follow Camera3D that mirrors that player's own
## (deactivated) SpringArm camera every frame — the player scene keeps
## owning look/arm collision exactly as in solo, and this layer is pure
## presentation. Layouts: 2 players stack top/bottom (keeps the wide
## aspect), 3-4 use a 2x2 grid (the empty 3-player cell shows a quiet
## filler panel). Sits in the default canvas layer, so every CanvasLayer
## UI (HUD 5, card UI, pause 30) draws above it untouched.
## The mirrored (source) cameras also join Juice.FEEL_CAMERA_GROUP, which
## is how camera shake and the slide FOV kick reach a split screen at all:
## the root viewport has no active camera once these views exist.

## One player's view: the camera that renders into its SubViewport and the
## player-owned camera it mirrors every frame.
class CameraPair:
	extends RefCounted
	var follow: Camera3D = null
	var source: Camera3D = null

	func is_live() -> bool:
		return is_instance_valid(follow) and is_instance_valid(source)

	## Everything the view must inherit from the player's own camera. The
	## h/v offsets matter as much as the transform: Juice writes the whole
	## camera shake into them (they survive the SpringArm3D rewriting the
	## child transform), so a view that skipped them never trembled.
	func sync() -> void:
		follow.global_transform = source.global_transform
		follow.fov = source.fov
		follow.h_offset = source.h_offset
		follow.v_offset = source.v_offset
		# First person culls the own seal via the source camera's mask.
		follow.cull_mask = source.cull_mask


var _pairs: Array[CameraPair] = []


## Builds the whole layout for `players` (Array of Player bodies, slot
## order). Call once from RunSystems after the party has spawned.
static func build(players: Array) -> SplitScreen:
	var split := SplitScreen.new()
	split.name = "SplitScreen"
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := players.size()
	for i in count:
		# Typed as Player, not Node3D: view_camera() is Player's contract, and
		# an untyped `:=` off a Node3D cannot infer its return type at all —
		# that is a PARSE error, which would take down every script that
		# preloads this one (run_systems.gd) and leave RunSystems unscripted.
		var player := players[i] as Player
		if player == null:
			push_error("SplitScreen: slot %d is not a Player body." % i)
			continue
		var source := player.view_camera()
		if source == null:
			push_error("SplitScreen: player %d has no view camera." % i)
			continue
		var rect := _cell_rect(i, count)
		var container := SubViewportContainer.new()
		container.name = "View%d" % (i + 1)
		container.stretch = true
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_rect(container, rect)
		split.add_child(container)
		var viewport := SubViewport.new()
		# Shares the parent (root) viewport's World3D by default; only the
		# camera is local to this view.
		viewport.handle_input_locally = false
		container.add_child(viewport)
		var follow := Camera3D.new()
		follow.fov = source.fov
		follow.near = source.near
		follow.far = source.far
		follow.keep_aspect = source.keep_aspect
		viewport.add_child(follow)
		follow.current = true
		# The feel layer (shake, FOV kick) drives the SOURCE cameras and
		# sync() carries the result into this view; without the group Juice
		# would look for an active camera on the root viewport and find none.
		source.add_to_group(Juice.FEEL_CAMERA_GROUP)
		var pair := CameraPair.new()
		pair.follow = follow
		pair.source = source
		split._pairs.append(pair)
	if count == 3:
		split.add_child(_filler_panel())
	return split


func _process(_delta: float) -> void:
	# After physics, before draw: no added latency versus a child camera.
	for pair: CameraPair in _pairs:
		# Validity BEFORE any use: the pair holds a camera owned by another
		# scene, and casting a freed one is already an error.
		if not pair.is_live():
			continue
		pair.sync()


## Anchor rect (in 0-1 space) for player cell `index` of `count`.
static func _cell_rect(index: int, count: int) -> Rect2:
	match count:
		2:
			return Rect2(0.0, 0.5 * index, 1.0, 0.5)
		_:
			return Rect2(0.5 * (index % 2), 0.5 * (index >> 1), 0.5, 0.5)


static func _apply_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.position.x + rect.size.x
	control.anchor_bottom = rect.position.y + rect.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


## Quiet dark panel over the unused 3-player quadrant (bottom-right).
static func _filler_panel() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_rect(panel, Rect2(0.5, 0.5, 0.5, 0.5))
	panel.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.05, 0.055, 0.08), 0))
	var label := Label.new()
	label.text = "BONKRAIDERS"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.25, 0.27, 0.33))
	label.add_theme_font_size_override("font_size", 28)
	panel.add_child(label)
	return panel
