extends Node
## Headless soak harness (iteration 38): boots an arena as a CHILD of an
## always-processing root, prints a status line every 2 s of run time and
## auto-picks the first upgrade card whenever the card UI opens (a soak has
## nobody at the mouse). Run with:
##   godot --headless --fixed-fps 60 --quit-after 36000 res://scenes/tests/ArenaProbe.tscn
##
## Env switches:
##   BONK_ARENA=res://...   arena scene (default: Hollow Woods)
##   BONK_CHARACTER=<id>    raider from CharacterCatalog
##   BONK_GODMODE=1         unkillable raider, so late systems get exercised
##   BONK_WALK=0            hold the raider still (default: it walks, see below)
##   BONK_SEED=<int>        deterministic walk, for reproducing a soak
##
## The raider WALKS AND INTERACTS by default (iteration 45). A parked raider
## silently skips every movement-gated system — Slime Trail only drops
## puddles while moving, altars only charge while a player stands in the
## ring, chests and portals need someone to reach them AND press interact —
## so a still soak reports "no errors" about code it never ran. The walk
## tours available Interactables first (lingering on arrival so Charge
## altars can finish their channel and the interact action lands) and falls
## back to random walkable points when none are left.

const DEFAULT_ARENA := "res://scenes/world/HollowWoods.tscn"

## Radius of the square the walk picks waypoints in, when the arena does not
## publish its own bounds through the "arena_bounds" group.
const FALLBACK_HALF_EXTENT: float = 60.0
## A leg ends when the raider gets this close to its waypoint...
const WAYPOINT_REACHED: float = 2.5
## ...or after this long, so geometry it cannot walk around never wedges it.
## Generous: a 160x160 arena with mask walls needs detours.
const LEG_TIMEOUT: float = 16.0
## Seconds before the tour will head back to an interactable it already
## tried. Keeps a spent-but-still-available altar from pinning the walk.
const REVISIT_COOLDOWN: float = 45.0
## Progress is sampled this often; moving less than STALL_DISTANCE in that
## window counts as stuck and earns a jump.
const STALL_WINDOW: float = 1.0
const STALL_DISTANCE: float = 1.5
## On reaching an interactable the raider stands still this long: Charge
## altars need an uninterrupted channel, and leaving cancels it.
const LINGER_TIME: float = 6.0
## While lingering, fire the interact action this often (chests answer on
## the first press; a spent one just ignores the rest).
const INTERACT_INTERVAL: float = 0.75
## A paused tree with no upgrade card UI open for this long means some
## blocking UI wedged the soak — worth a log line, since a wedged run looks
## exactly like a clean one in the frame counter.
const PAUSE_WEDGE_WARN: float = 20.0

var _frames: int = 0
var _walking: bool = true
var _waypoint: Vector3 = Vector3.ZERO
var _leg_time_left: float = 0.0
var _linger_left: float = 0.0
var _interact_timer: float = 0.0
var _paused_for: float = 0.0
var _wedge_reported: bool = false
## BONK_PROBE_DEBUG=1 narrates the tour (waypoints, arrivals, interact
## presses) so a soak that never reaches an interactable is diagnosable.
var _debug: bool = false
## Interactable instance id -> run_time when the tour last headed for it.
var _visited: Dictionary[int, float] = {}
## The interactable this leg is walking to (null when just roaming).
var _target: Interactable = null
var _stall_check: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Never fold a soak into the real save: re-point SaveData at a scratch
	# file (fresh defaults) before the arena boots.
	SaveData.save_path = "user://soak_save.json"
	SaveData.load_from_disk()
	# BONK_CHARACTER=<id> picks the raider (default: the config's choice).
	var character := OS.get_environment("BONK_CHARACTER")
	if not character.is_empty() and not CharacterCatalog.by_id(character).is_empty():
		GameConfig.selected_character_id = character
	var path := OS.get_environment("BONK_ARENA")
	if path.is_empty():
		path = DEFAULT_ARENA
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("ArenaProbe: cannot load '%s'" % path)
		get_tree().quit(1)
		return
	add_child(scene.instantiate())
	_walking = OS.get_environment("BONK_WALK") != "0"
	_debug = OS.get_environment("BONK_PROBE_DEBUG") == "1"
	var seed_text := OS.get_environment("BONK_SEED")
	if seed_text.is_valid_int():
		_rng.seed = int(seed_text)
	else:
		_rng.randomize()
	# BONK_GODMODE=1: an idle raider dies inside a minute, which hides every
	# late system (bosses, hordes, altars); a huge HP pool lets a soak run
	# the full clock. Purely a harness switch — never shipped behavior.
	if OS.get_environment("BONK_GODMODE") == "1":
		_apply_godmode.call_deferred()
	print("ArenaProbe: arena=%s walk=%s" % [path.get_file(), _walking])


func _apply_godmode() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var health := Health.find_in(node)
		if health != null:
			health.max_hp = 10000000.0
			health.heal_full()
	print("ArenaProbe: godmode on")


func _physics_process(delta: float) -> void:
	_frames += 1
	if _frames % 120 == 0:
		print("frame %d paused=%s run_time=%.1f active=%s enemies=%d level=%d" % [
				_frames, get_tree().paused, RunState.run_time, RunState.run_active,
				get_tree().get_node_count_in_group("enemies"), RunState.level])
	var card_ui_open := false
	for node: Node in get_tree().get_nodes_in_group("upgrade_ui"):
		var ui := node as CanvasLayer
		if ui != null and ui.visible and ui.has_method("_on_card_pressed"):
			card_ui_open = true
			ui.call("_on_card_pressed", 0)
	_watch_for_wedge(delta, card_ui_open)
	if _walking and not get_tree().paused:
		_drive_walk(delta)


## A blocking UI that never closes (roulette, run end) freezes run_time while
## the frame counter keeps climbing, so the soak looks healthy while running
## nothing. Report it once, loudly enough for a grep.
func _watch_for_wedge(delta: float, card_ui_open: bool) -> void:
	if not get_tree().paused or card_ui_open:
		_paused_for = 0.0
		return
	_paused_for += delta
	if _paused_for >= PAUSE_WEDGE_WARN and not _wedge_reported:
		_wedge_reported = true
		# Only the VISIBLE blockers: every screen in the group is a member
		# whether or not it is on screen, so listing all of them points at
		# the wrong culprit.
		var blockers: Array[String] = []
		for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
			var shown: Variant = node.get("visible")
			if shown == null or bool(shown):
				blockers.append(node.name)
		push_warning("ArenaProbe: WEDGE — tree paused %.0fs with no card UI; blocking=%s"
				% [_paused_for, blockers])


## Steers the lead raider toward the current waypoint by HOLDING THE REAL
## MOVE ACTIONS. Writing velocity directly does not work: Player rebuilds it
## from Input.get_vector() every physics frame and then calls
## move_and_slide(), so a written velocity is overwritten before it moves
## anything. Pressing the actions also means the soak exercises the real
## input path (slide, sprint gating, free-orbit basis) instead of bypassing it.
func _drive_walk(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_release_move()
		return
	var lead := players[0] as CharacterBody3D
	if lead == null or not lead.is_inside_tree():
		_release_move()
		return
	if _linger_left > 0.0:
		_linger_left -= delta
		_release_move()
		_interact_timer -= delta
		if _interact_timer <= 0.0:
			_interact_timer = INTERACT_INTERVAL
			_press_interact()
		return
	_leg_time_left -= delta
	# "Arrived" means the game's own condition — inside the target's Area3D,
	# which is what gates the prompt and the interact — not a fixed radius.
	# A chest on a rise sits 4-5 m away horizontally and would never satisfy
	# a distance test while being perfectly interactable.
	var reached := lead.global_position.distance_to(_waypoint) <= WAYPOINT_REACHED
	if is_instance_valid(_target) and _target.player_in_range:
		reached = true
	if _waypoint == Vector3.ZERO or _leg_time_left <= 0.0 or reached:
		if reached:
			# Stand still on arrival: Charge altars need an uninterrupted
			# channel and chests need the interact press to land.
			_linger_left = LINGER_TIME
			_interact_timer = 0.0
			_release_move()
			_pick_waypoint(lead.global_position)
			return
		if _debug:
			print("ArenaProbe: leg timed out %.1fm short of %v"
					% [lead.global_position.distance_to(_waypoint), _waypoint])
		_pick_waypoint(lead.global_position)
	_hold_move_toward(lead, _waypoint)
	_unstick(lead, delta)


## Hops when horizontal progress stalls. Ledges, ramps and the mask walls
## all read as "walking into something"; without a jump the tour can never
## reach the chests parked on verticality spots.
func _unstick(lead: CharacterBody3D, delta: float) -> void:
	_stall_check -= delta
	if _stall_check > 0.0:
		return
	_stall_check = STALL_WINDOW
	var moved := lead.global_position.distance_to(_last_position)
	_last_position = lead.global_position
	if moved > STALL_DISTANCE:
		return
	var jump := Coop.action(0, &"jump")
	Input.action_press(jump)
	Input.action_release.bind(jump).call_deferred()


## Converts a world-space heading into held move actions. Player builds its
## wish direction as `transform.basis * Vector3(input.x, 0, input.y)`, so the
## heading has to come back through the body's own basis.
func _hold_move_toward(body: CharacterBody3D, to: Vector3) -> void:
	var heading := to - body.global_position
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		_release_move()
		return
	var local := body.transform.basis.inverse() * heading.normalized()
	_hold_axis(&"move_right", &"move_left", local.x)
	_hold_axis(&"move_back", &"move_forward", local.z)


func _hold_axis(positive: StringName, negative: StringName, amount: float) -> void:
	var forward := Coop.action(0, positive)
	var backward := Coop.action(0, negative)
	if amount >= 0.0:
		Input.action_press(forward, absf(amount))
		Input.action_release(backward)
	else:
		Input.action_press(backward, absf(amount))
		Input.action_release(forward)


func _release_move() -> void:
	for base: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(Coop.action(0, base))


## Synthesizes a real "interact" press so shrines, chests, portals and
## secret triggers resolve through their own _unhandled_input path.
## The release has to land on a LATER frame than the press: both parsed in
## one flush and the action never reads as "just pressed", which is exactly
## what Interactable._unhandled_input tests for.
func _press_interact() -> void:
	if _debug:
		var touching: Array[String] = []
		for node: Node in _all_interactables(get_tree().current_scene):
			var spot := node as Interactable
			if spot != null and spot.player_in_range:
				touching.append("%s(available=%s)" % [spot.name, spot.available])
		print("ArenaProbe: interact press; in range: %s" % [touching])
	_send_interact(true)
	_release_interact.call_deferred()


func _release_interact() -> void:
	_send_interact(false)


func _send_interact(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = Coop.action(0, &"interact")
	event.pressed = pressed
	Input.parse_input_event(event)


## Next destination: the nearest still-available Interactable that this tour
## has not just visited, so a soak actually spends points on chests and
## charges altars; a random walkable point once they are all spent or all
## recently tried.
func _pick_waypoint(from: Vector3) -> void:
	_leg_time_left = LEG_TIMEOUT
	var target := _nearest_interactable(from)
	_target = target
	if target != null:
		_visited[target.get_instance_id()] = RunState.run_time
		_waypoint = target.global_position
		if _debug:
			print("ArenaProbe: heading to %s at %.1fm (available=%s)"
					% [target.name, from.distance_to(_waypoint), target.available])
		return
	# Prefer the arena's own walkable mask so waypoints never sit inside the
	# blocked cells the irregular-arena mask carves out (iteration 44).
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		if node.has_method("random_walkable_point"):
			var point: Variant = node.call("random_walkable_point")
			if point is Vector2:
				_waypoint = Vector3(point.x, from.y, point.y)
				if _debug:
					print("ArenaProbe: no fresh interactable, roaming to %v" % _waypoint)
				return
	var half := FALLBACK_HALF_EXTENT
	_waypoint = Vector3(_rng.randf_range(-half, half), from.y, _rng.randf_range(-half, half))


## Nearest available interactable not tried within REVISIT_COOLDOWN. Without
## that cooldown the tour ping-pongs between the two closest points forever
## (a spent-but-still-`available` altar stays the nearest thing on the map).
func _nearest_interactable(from: Vector3) -> Interactable:
	var nearest: Interactable = null
	var nearest_dist := INF
	for node: Node in _all_interactables(get_tree().current_scene):
		var spot := node as Interactable
		if spot == null or not spot.available or not spot.is_inside_tree():
			continue
		var tried_at: float = _visited.get(spot.get_instance_id(), -INF)
		if RunState.run_time - tried_at < REVISIT_COOLDOWN:
			continue
		var dist := from.distance_to(spot.global_position)
		if dist <= WAYPOINT_REACHED or dist >= nearest_dist:
			continue
		nearest_dist = dist
		nearest = spot
	return nearest


func _all_interactables(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for child: Node in root.get_children():
		if child is Interactable:
			found.append(child)
		found.append_array(_all_interactables(child))
	return found
