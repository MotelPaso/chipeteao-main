class_name Interactable
extends Area3D
## Base for world interactables (shrines, chests — GDD 4). The Area3D is
## the detection ring: while the player stands inside and the interactable
## is still available, a floating world-space prompt (Label3D, the one
## prompt scheme for every interactable — with the button written as
## INTERACT_TOKEN and resolved per raider) shows, and pressing the
## "interact" action calls the _interact() override. Subclasses emit the
## lifecycle signals through the _emit_* helpers and call consume() once spent
## (one-use pattern: prompt gone, further input ignored). Loose coupling:
## the player is found via its group, rewards go out via call_group.

signal interaction_started
signal interaction_completed
signal interaction_cancelled

## Line shown on the floating prompt while the player is in range. Write
## the interact button as INTERACT_TOKEN: the label resolves it per raider.
@export var prompt_text: String = "[E] Interactuar"
## Height of the prompt label above the interactable's origin.
@export var prompt_height: float = 3.4
## SaveData counter bumped when this interactable is consumed ("" records
## nothing). Lets the quest log count shrine/chest usage without the
## subclasses knowing anything about persistence (subclasses set a default
## in _init; scenes may still override per instance).
@export var meta_stat_id: String = ""
## Sfx id played on completion; the two resolution chimes are inversions
## of the same chord, so subclasses just pick their voicing (chests swap
## in &"chest_open" in _init).
@export var complete_sound: StringName = &"shrine_done"

## Placeholder every prompt line carries for the interact button. The
## action is bound to E *and* to a pad face button (project.godot,
## Coop.PAD_INTERACT_BUTTON), and co-op slots 1-3 only ever hold a
## control, so the label resolves the token against the raider actually
## standing in the ring instead of promising a key they cannot press.
const INTERACT_TOKEN: String = "[E]"
## What the token becomes for a control-driven slot (Coop.PAD_INTERACT_BUTTON).
const PAD_INTERACT_GLYPH: String = "[Y]"

## Cleared by consume(); a spent interactable ignores the interact action.
var available: bool = true
var player_in_range: bool = false

## Player bodies currently inside the ring (co-op: several at once); the
## legacy player_in_range bool mirrors "any of them" for subclasses.
## A DOWNED raider stays in here (the body never leaves the tree, so
## body_exited never fires) — ask live_players_in_range() for the raiders
## that can actually hold a ritual.
var _players_in_range: Array[Node3D] = []

## Ref-counted channel loop currently held by this interactable (&"" =
## none). See _hold_loop().
var _held_loop: StringName = &""

var _prompt: Label3D


## Map marker (iteration 52): which dot this thing draws as on the
## minimap and the Tab map. Empty means IT NEVER APPEARS — which is what
## secret_trigger.gd keeps, on purpose: a secret you can read off the map
## is not a secret. Subclasses set their default in _init; the style table
## lives in MapDraw.MARKER_STYLES.
@export var marker_kind: StringName = &""


func _ready() -> void:
	if not marker_kind.is_empty():
		add_to_group(&"map_markers")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 52
	_prompt.outline_size = 14
	_prompt.modulate = Color(0.96, 0.93, 0.8)
	_prompt.position = Vector3.UP * prompt_height
	add_child(_prompt)
	_refresh_prompt()


## Sfx loops shared by several emitters (the channel hum runs on both the
## altars and the Humming Skull) are ref-counted: acquire on start,
## exactly one release on stop, and one more from _exit_tree so a
## retry/quit mid-channel can never leave the voice droning.
func _exit_tree() -> void:
	_drop_loop()


func _unhandled_input(event: InputEvent) -> void:
	if not available or not player_in_range:
		return
	# Each in-range player answers only to THEIR interact action (solo:
	# the plain project action; co-op: the per-slot clone), so a shrine
	# resolves for the raider who actually pressed the button.
	for body: Node3D in live_players_in_range():
		var interact_name: StringName = &"interact"
		if body.has_method(&"interact_action"):
			interact_name = body.call(&"interact_action")
		if event.is_action_pressed(interact_name):
			_interact(body)
			# One press resolves ONE interactable: overlapping rings
			# (a director spring dropped on a scene altar) used to charge
			# the raider for both in the same frame.
			get_viewport().set_input_as_handled()
			return


## Virtual: the actual effect. `player` is the node from the "player" group.
func _interact(_player: Node) -> void:
	pass


## Virtual hooks for range changes (the Charge Shrine cancels its channel
## when the player steps out).
func _on_range_entered() -> void:
	pass


func _on_range_exited() -> void:
	pass


## Marks this interactable spent: prompt gone, further input ignored.
func consume() -> void:
	if available and meta_stat_id != "":
		SaveData.bump(meta_stat_id)
	available = false
	_refresh_prompt()


## Swaps the prompt line (e.g. "resume" text after a cancelled channel).
func set_prompt(text: String) -> void:
	prompt_text = text
	_refresh_prompt()


## Raiders standing in the ring that are still ON THEIR FEET. A downed
## body never leaves the Area3D (Player only drops the "player" group),
## so every "is anybody holding this ritual / who pays / whose stats
## count" question has to come through here. Freed bodies are dropped
## from the backing array on the way past.
func live_players_in_range() -> Array[Node3D]:
	var live: Array[Node3D] = []
	var kept: Array[Node3D] = []
	for body: Node3D in _players_in_range:
		if not is_instance_valid(body):
			continue
		kept.append(body)
		if body.is_in_group("player"):
			live.append(body)
	if kept.size() != _players_in_range.size():
		_players_in_range = kept
		player_in_range = not _players_in_range.is_empty()
	return live


## Closest raider still standing in the ring (null when nobody is), used
## for the per-raider parts of the prompt.
func nearest_live_player() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for body: Node3D in live_players_in_range():
		var distance := global_position.distance_squared_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## Highest copy count of `item_id` among the raiders in the ring (the
## party pools its keys/blood: the best holder carries the ritual).
func best_item_count_in_range(item_id: String) -> int:
	var best := 0
	for body: Node3D in live_players_in_range():
		var bag := ItemBag.find_in(body)
		if bag != null:
			best = maxi(best, bag.count(item_id))
	return best


## Starts (or swaps to) a ref-counted Sfx loop owned by this interactable.
## Exactly one release per acquire — the flag is what guarantees it.
func _hold_loop(id: StringName) -> void:
	if _held_loop == id:
		return
	_drop_loop()
	_held_loop = id
	Sfx.acquire_loop(id)


func _drop_loop() -> void:
	if _held_loop == &"":
		return
	Sfx.release_loop(_held_loop)
	_held_loop = &""


## True while the [E] prompt is actually showing (range + availability).
func prompt_visible() -> bool:
	return _prompt != null and _prompt.visible


## Gray-out for spent shrines: every mesh gets a flat stone override and
## any glow lights go dark, so "used" reads at a distance.
func dim_visuals() -> void:
	var dim := StandardMaterial3D.new()
	dim.albedo_color = Color(0.34, 0.34, 0.37)
	dim.roughness = 1.0
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = dim
	for node: Node in find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		if light != null:
			light.visible = false


func _emit_started() -> void:
	interaction_started.emit()


func _emit_completed() -> void:
	Juice.sparkle(global_position + Vector3.UP * 1.2)
	Sfx.play(complete_sound)
	interaction_completed.emit()


func _emit_cancelled() -> void:
	interaction_cancelled.emit()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if not _players_in_range.has(body):
		_players_in_range.append(body)
	player_in_range = true
	_refresh_prompt()
	_on_range_entered()


func _on_body_exited(body: Node3D) -> void:
	if not _players_in_range.has(body):
		return
	_players_in_range.erase(body)
	if not _players_in_range.is_empty():
		return  # someone else still stands in the ring: no range-exit event
	player_in_range = false
	_refresh_prompt()
	_on_range_exited()


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	_prompt.text = prompt_text.replace(INTERACT_TOKEN, _interact_glyph())
	_prompt.visible = available and player_in_range


## Button glyph for the raider closest to the ring: the keyboard slot (and
## every solo run) reads "[E]", a control-driven co-op slot reads its face
## button instead of a key it does not have.
func _interact_glyph() -> String:
	var body := nearest_live_player()
	if body == null:
		return INTERACT_TOKEN
	var slot: Variant = body.get("player_index")
	if slot == null or Coop.device_for_slot(int(slot)) == Coop.KEYBOARD_DEVICE:
		return INTERACT_TOKEN
	return PAD_INTERACT_GLYPH


## Map marker contract (group "map_markers").
func map_marker_kind() -> StringName:
	return marker_kind
