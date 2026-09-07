extends Node
## Autoload "Coop": local co-op session config plus every helper the rest
## of the game needs to stop assuming "the player" is one node.
##
## - Session: player_count (1-4), one input device per slot (slot 0 is
##   keyboard+mouse by default; other slots are joypad ids) and one
##   CharacterCatalog id per slot. Configured by the select screen's
##   lobby; survives scene changes and RunState.reset() exactly like
##   GameConfig (Retry replays the same party).
## - Input: in co-op each slot gets its own InputMap action set
##   ("p<slot>_move_left" etc.) bound ONLY to that slot's device, so four
##   people can hold directions at once without clobbering each other.
##   Solo keeps the plain project actions (which also carry all-device
##   gamepad bindings, so one player can pick pad OR keyboard freely).
## - Queries: nearest/random alive player, alive count, per-tick group
##   snapshot (same allocation-avoidance pattern EnemyBase uses for the
##   horde). "Alive" means "in the player group": a downed co-op player
##   leaves the group until revived, so every existing group-based system
##   (enemy seek, gem homing, interactables) ignores downed bodies for free.

const MAX_PLAYERS: int = 4
## Sentinel device for the keyboard+mouse slot.
const KEYBOARD_DEVICE: int = -1

## Base action names cloned per slot in co-op (must exist in project.godot).
const BASE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"sprint", &"interact",
	&"camera_mode", &"camera_zoom_in", &"camera_zoom_out",
	&"map_overlay",
]

## Right-stick look tuning shared by every pad-driven camera.
const LOOK_DEADZONE: float = 0.18
## Radians/second of yaw at full stick deflection (before user sensitivity).
const LOOK_SPEED: float = 2.6

## Gamepad button layout (Xbox naming): A jump, X sprint/slide, Y interact.
const PAD_JUMP_BUTTON := JOY_BUTTON_A
const PAD_SPRINT_BUTTON := JOY_BUTTON_X
const PAD_INTERACT_BUTTON := JOY_BUTTON_Y
## Tab's pad equivalent: Back/Select, the button every game puts the map on.
const PAD_MAP_BUTTON := JOY_BUTTON_BACK

var player_count: int = 1
## Input device per slot: KEYBOARD_DEVICE or a joypad device id.
var devices: Array[int] = [KEYBOARD_DEVICE]
## CharacterCatalog id per slot; slot 0 mirrors GameConfig.selected_character_id.
var character_ids: Array[String] = []

## Per-physics-tick snapshot of the "player" group (see EnemyBase's
## enemies snapshot): a 200-enemy horde asks for the nearest player every
## tick, so the group array is built once per tick, not once per enemy.
var _players_snapshot: Array[Node3D] = []
var _players_snapshot_frame: int = -1


func is_coop() -> bool:
	return player_count > 1


## Called by the select screen's lobby right before starting a run (and
## once with count 1 to return to solo). Rebuilds the per-slot actions.
func configure(count: int, slot_devices: Array[int], slot_characters: Array[String]) -> void:
	player_count = clampi(count, 1, MAX_PLAYERS)
	# Built slot by slot, NOT with resize(): an Array[int] pads with 0, and
	# 0 is the id of the FIRST connected joypad, not the keyboard sentinel.
	# A party asked for more slots than devices ended up with two raiders
	# sharing one pad instead of one of them falling back to the keyboard.
	var resolved: Array[int] = []
	resolved.resize(player_count)
	for slot: int in player_count:
		resolved[slot] = slot_devices[slot] if slot < slot_devices.size() else KEYBOARD_DEVICE
	devices = resolved
	character_ids = slot_characters.duplicate()
	character_ids.resize(player_count)
	invalidate_players()
	if player_count > 0 and not character_ids[0].is_empty():
		GameConfig.selected_character_id = character_ids[0]
	_rebuild_slot_actions()


## Character id a given slot spawns with; empty slots fall back to the
## solo selection (slot 0) or the catalog default.
func character_for_slot(slot: int) -> String:
	if slot < character_ids.size() and not character_ids[slot].is_empty():
		return character_ids[slot]
	return GameConfig.selected_character_id


func device_for_slot(slot: int) -> int:
	return devices[slot] if slot < devices.size() else KEYBOARD_DEVICE


## Action name a player slot should poll. Solo (and any out-of-range
## slot) uses the plain project action so the existing bindings — and the
## all-device gamepad events added for solo pad play — keep working.
func action(slot: int, base: StringName) -> StringName:
	if not is_coop() or slot >= player_count:
		return base
	return StringName("p%d_%s" % [slot, base])


## Right-stick look vector for a slot's device, deadzone applied, in
## [-1, 1] per axis. The keyboard slot (and solo) also accepts ANY
## connected pad, so a solo player can play entirely on a controller.
func look_vector(slot: int) -> Vector2:
	var device := device_for_slot(slot)
	if device != KEYBOARD_DEVICE:
		return _pad_look(device)
	if is_coop():
		# In co-op the keyboard slot owns the mouse; pads belong to others.
		return Vector2.ZERO
	var best := Vector2.ZERO
	for pad: int in Input.get_connected_joypads():
		var candidate := _pad_look(pad)
		if candidate.length_squared() > best.length_squared():
			best = candidate
	return best


func _pad_look(device: int) -> Vector2:
	var raw := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if raw.length() < LOOK_DEADZONE:
		return Vector2.ZERO
	# Rescale so movement starts at zero right past the deadzone edge.
	return raw.normalized() * minf((raw.length() - LOOK_DEADZONE) / (1.0 - LOOK_DEADZONE), 1.0)


# --- party queries (the "which player?" answer for every system) ------------

## Nearest ALIVE player to `from`, or null with nobody standing. This is
## the drop-in replacement for get_first_node_in_group("player") at every
## positional call site (enemy seek, gem homing, spawn rings).
func nearest_player(tree: SceneTree, from: Vector3) -> Node3D:
	var nearest: Node3D = null
	var best := INF
	for player: Node3D in _players_this_tick(tree):
		if not _is_standing(player):
			continue
		var dist := from.distance_squared_to(player.global_position)
		if dist < best:
			best = dist
			nearest = player
	return nearest


## A uniformly random alive player (spawn-ring anchors), or null.
func random_player(tree: SceneTree) -> Node3D:
	var alive: Array[Node3D] = alive_players(tree)
	return alive.pick_random() if not alive.is_empty() else null


func alive_players(tree: SceneTree) -> Array[Node3D]:
	var alive: Array[Node3D] = []
	for player: Node3D in _players_this_tick(tree):
		if _is_standing(player):
			alive.append(player)
	return alive


func alive_player_count(tree: SceneTree) -> int:
	return alive_players(tree).size()


## Drops the per-tick snapshot. Call it whenever the party membership
## changes outside the normal tick boundary (a slot going down or being
## revived, a new session being configured).
func invalidate_players() -> void:
	_players_snapshot_frame = -1
	_players_snapshot.clear()


## Snapshot readers re-check the group instead of trusting the cache: this
## file promises that a downed raider leaves the group and every
## group-based system ignores it "for free", and a stale tick would have
## broken that promise exactly in the frame where somebody goes down.
static func _is_standing(player: Node3D) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() \
			and player.is_in_group(&"player")


func _players_this_tick(tree: SceneTree) -> Array[Node3D]:
	var frame := Engine.get_physics_frames()
	if frame != _players_snapshot_frame:
		_players_snapshot_frame = frame
		_players_snapshot.clear()
		for node: Node in tree.get_nodes_in_group(&"player"):
			var player := node as Node3D
			if player != null:
				_players_snapshot.append(player)
	return _players_snapshot


# --- per-slot InputMap actions ----------------------------------------------

## (Re)creates "p<slot>_<action>" for every co-op slot, bound only to that
## slot's device: keyboard slots clone the project keyboard events, pad
## slots get a stick+buttons layout pinned to their joypad id. Old slot
## actions are dropped first, so device reshuffles between runs are clean.
func _rebuild_slot_actions() -> void:
	_clear_slot_actions()
	if not is_coop():
		return
	for slot: int in player_count:
		var device := device_for_slot(slot)
		for base: StringName in BASE_ACTIONS:
			var slot_action := action(slot, base)
			InputMap.add_action(slot_action, 0.5)
			if device == KEYBOARD_DEVICE:
				for event: InputEvent in InputMap.action_get_events(base):
					if event is InputEventKey or event is InputEventMouseButton:
						InputMap.action_add_event(slot_action, event.duplicate())
			else:
				for event: InputEvent in _pad_events_for(base, device):
					InputMap.action_add_event(slot_action, event)


func _clear_slot_actions() -> void:
	for slot: int in MAX_PLAYERS:
		for base: StringName in BASE_ACTIONS:
			var slot_action := StringName("p%d_%s" % [slot, base])
			if InputMap.has_action(slot_action):
				InputMap.erase_action(slot_action)


## Joypad events for one base action pinned to `device`: left stick for
## movement, face buttons for the rest (mirrors the all-device solo
## bindings in project.godot).
func _pad_events_for(base: StringName, device: int) -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	match base:
		&"move_forward":
			events.append(_axis_event(device, JOY_AXIS_LEFT_Y, -1.0))
		&"move_back":
			events.append(_axis_event(device, JOY_AXIS_LEFT_Y, 1.0))
		&"move_left":
			events.append(_axis_event(device, JOY_AXIS_LEFT_X, -1.0))
		&"move_right":
			events.append(_axis_event(device, JOY_AXIS_LEFT_X, 1.0))
		&"jump":
			events.append(_button_event(device, PAD_JUMP_BUTTON))
		&"sprint":
			events.append(_button_event(device, PAD_SPRINT_BUTTON))
			events.append(_button_event(device, JOY_BUTTON_LEFT_SHOULDER))
		&"interact":
			events.append(_button_event(device, PAD_INTERACT_BUTTON))
		&"map_overlay":
			events.append(_button_event(device, PAD_MAP_BUTTON))
		&"camera_mode":
			events.append(_button_event(device, JOY_BUTTON_RIGHT_STICK))
		&"camera_zoom_in":
			events.append(_button_event(device, JOY_BUTTON_DPAD_UP))
		&"camera_zoom_out":
			events.append(_button_event(device, JOY_BUTTON_DPAD_DOWN))
	return events


func _axis_event(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


func _button_event(device: int, button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	return event
