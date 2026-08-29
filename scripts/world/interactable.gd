class_name Interactable
extends Area3D
## Base for world interactables (shrines, chests — GDD 4). The Area3D is
## the detection ring: while the player stands inside and the interactable
## is still available, a floating world-space [E] prompt (Label3D, the one
## prompt scheme for every interactable) shows, and pressing the "interact"
## action calls the _interact() override. Subclasses emit the lifecycle
## signals through the _emit_* helpers and call consume() once spent
## (one-use pattern: prompt gone, further input ignored). Loose coupling:
## the player is found via its group, rewards go out via call_group.

signal interaction_started
signal interaction_completed
signal interaction_cancelled

## Line shown on the floating prompt while the player is in range.
@export var prompt_text: String = "[E] Interact"
## Height of the prompt label above the interactable's origin.
@export var prompt_height: float = 3.4
## SaveData counter bumped when this interactable is consumed ("" records
## nothing). Lets the quest log count shrine/chest usage without the
## subclasses knowing anything about persistence (subclasses set a default
## in _init; scenes may still override per instance).
@export var meta_stat_id: String = ""

## Cleared by consume(); a spent interactable ignores the interact action.
var available: bool = true
var player_in_range: bool = false

var _prompt: Label3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.text = prompt_text
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 52
	_prompt.outline_size = 14
	_prompt.modulate = Color(0.96, 0.93, 0.8)
	_prompt.position = Vector3.UP * prompt_height
	_prompt.visible = false
	add_child(_prompt)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not available or not player_in_range:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_interact(player)


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
	if _prompt != null:
		_prompt.text = text


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
	interaction_completed.emit()


func _emit_cancelled() -> void:
	interaction_cancelled.emit()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = true
	_refresh_prompt()
	_on_range_entered()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = false
	_refresh_prompt()
	_on_range_exited()


func _refresh_prompt() -> void:
	_prompt.visible = available and player_in_range
