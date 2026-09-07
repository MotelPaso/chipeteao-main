extends Node3D
## Root of RunSystems.tscn: the map-independent run block — Player,
## RunManager, WorldDirector, upgrade-card UI, HUD, and the run-end
## screen, with run_ended already wired to the end screen inside this
## scene. Arenas keep their own EnemySpawner and AmbientBed (the boss
## timetable and the wind differ per biome).
##
## Since iteration 49 this block is instanced ONCE, by Run.tscn, and
## survives every stage change: that is what makes level, weapons, tomes,
## items and points carry from map to map without copying anything. It no
## longer knows which map is being played (RunRoot publishes that into
## GameConfig) and it no longer settles a map tier (tiers are gone).

## Radius of the ring co-op slots 1..N-1 spawn on, around the scene's
## slot-0 spawn point. Generated instead of tabulated: a fixed table of
## three offsets indexed with a modulo silently sat two raiders on the
## same point the moment the party grew past it.
@export var coop_spawn_radius: float = 1.8

## Preloaded (not the bare class_name) so headless runs that never built
## the editor's class cache still resolve it.
const SplitScreenView := preload("res://scripts/systems/split_screen.gd")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")


## The run block owns the run reset. It enters the tree BEFORE the arena
## RunRoot builds afterwards, so a stage's scatter and director always see
## a clean RunState, and the Daily Hunt stream is re-seeded at one fixed
## point instead of however many frames earlier the menu happened to call
## it. reset() is idempotent, so the select screen's own call stays
## harmless.
func _enter_tree() -> void:
	RunState.reset()


func _ready() -> void:
	# Items, altars and the run root reach this block through the group
	# (vacuum_pickups, place_party).
	add_to_group("run_systems")
	if Coop.is_coop():
		_spawn_party()
	get_tree().call_group("hud", "show_stage_tag", RunState.stage_index, RunState.lap)
	# Iteration 38: leveling no longer vacuums the floor. The gem/orb
	# vacuum() hooks stay for the Magnet item, which fires them on its own
	# timer (see vacuum_pickups).


## Stage hook (RunRoot, through the "run_systems" group): puts the whole
## party down at the new arena's spawn point — standing raiders and downed
## bodies alike, since a downed raider travels with the party. Reuses the
## same ring geometry the co-op boot uses, so a party never lands stacked
## on one point, and re-anchors each body's void rescue: the anchor
## recorded at _ready belongs to a map that no longer exists.
func place_party(origin: Vector3) -> void:
	var bodies: Array[Node] = []
	for group: String in ["player", "downed_players"]:
		bodies.append_array(get_tree().get_nodes_in_group(group))
	bodies.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get("player_index")) < int(b.get("player_index")))
	for i: int in bodies.size():
		var body := bodies[i] as Node3D
		if body == null:
			continue
		# The ring offset moves the body sideways, so its ground height has
		# to be re-read there: slot 0 is on the spawn pad, slot 3 may be a
		# metre and a half off it.
		var at := origin + _coop_spawn_offset(i)
		var terrain := Terrain.find(get_tree())
		if terrain != null:
			at.y = terrain.height_at(at.x, at.z)
		body.global_position = at
		if body.has_method("anchor_here"):
			body.call("anchor_here")


## Magnet-item hook (and any future "hoover the floor" effect): every live
## XP gem and health orb force-homes to the nearest player at once,
## regardless of pickup radius. Idempotent on gems already homing.
func vacuum_pickups() -> void:
	get_tree().call_group(XpGem.LIVE_GROUP, "vacuum")
	get_tree().call_group(HealthOrb.LIVE_GROUP, "vacuum")


## Co-op boot: the scene's Player becomes slot 0; slots 1..N-1 are extra
## Player.tscn instances offset around the same spawn, then the whole
## screen becomes a SplitScreen of per-player views. Runs inside this
## _ready (parent readies after children), so RunManager's and the HUD's
## deferred party binds see the full roster on the same frame.
func _spawn_party() -> void:
	var first := get_node("Player") as Player
	var players: Array = [first]
	for slot in range(1, Coop.player_count):
		var extra := PLAYER_SCENE.instantiate() as Player
		extra.name = "Player%d" % (slot + 1)
		extra.player_index = slot
		# Position BEFORE add_child: Player._ready records its spawn point
		# (void-rescue anchor) the moment it enters the tree.
		extra.position = first.position + _coop_spawn_offset(slot)
		add_child(extra)
		players.append(extra)
	add_child(SplitScreenView.build(players))


## Slot `slot`'s offset on the spawn ring: one even share of the circle
## per party member, so no two slots can land on the same point.
## Slot 0 lands ON the spawn point; the rest ring around it, one even
## share of the circle each, so no two slots can land on the same spot.
func _coop_spawn_offset(slot: int) -> Vector3:
	if slot <= 0:
		return Vector3.ZERO
	var angle := TAU * float(slot) / float(maxi(Coop.player_count, 1))
	return Vector3(cos(angle), 0.0, sin(angle)) * coop_spawn_radius
