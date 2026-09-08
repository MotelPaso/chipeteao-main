class_name PowerUps
extends Node
## Per-raider power-up holder (iteration 53), mounted on the Player beside
## ItemBag and Stats. Owns WHAT IS ACTIVE and for how long; the effects
## themselves ride existing channels wherever one exists:
##   stat rows      -> PlayerStats.add_timed_boon, tagged so a refresh
##                     replaces itself instead of stacking with itself
##   immortal       -> Health.invulnerable
##   reflect        -> Health.reflect_fraction
##   gold           -> Player.set_points_source (a named factor, not a
##                     second wallet)
##   vampire        -> lifesteal boon + permanent_max_hp banked HERE
##   flight         -> Player reads has("flight") each physics tick
##   time_stop      -> EnemySpawner.freeze_enemies through the group
##   star           -> every other row at once, on the STAR's own clock
##
## Different power-ups STACK; the same one REFRESHES. That is the whole
## rule, and it is why every kind-driven consumer is re-synced from
## has(kind) after any change instead of being toggled on expiry: with
## stacking, "the immortality ran out" and "I am no longer immortal" are
## different questions (a star can still be running).
##
## Nothing here is per-frame work when nothing is active: the expiry poll
## returns immediately on an empty list.

signal active_changed

## Points multiplier while Fiebre del oro runs, and the name it registers
## under on the Player (part C2 adds a second source, hence named factors).
@export var gold_points_multiplier: float = 2.0
## Max HP banked per kill while Modo vampiro runs.
@export var vampire_hp_per_kill: float = 1.0
## Damage returned to the attacker while Reflejo runs, as a fraction.
@export var reflect_fraction: float = 1.0

const POINTS_SOURCE := "powerup_gold"
## Tag prefix for the timed boons a row owns, so a re-pick can clear its
## own and only its own.
const BOON_TAG_PREFIX := "powerup:"

## Permanent max HP banked by Modo vampiro. A STORED TOTAL, re-added by
## PlayerStats.recompute on every rebuild — never added onto a derived
## value, which _reset_derived would wipe on the next recompute.
var permanent_max_hp: float = 0.0

## Live rows: {id, kind, expires_at}. Ordered by pickup.
var _active: Array[Dictionary] = []
## Raised by RunState.stage_changed, consumed on the next physics frame:
## the new arena's nodes are built by then, so _sync writes to the live
## spawner instead of the one that was just freed.
var _stage_changed: bool = false


## The component rides the raider across a stage change; the nodes it
## publishes to do not. Flagged rather than synced on the spot, because
## the arena is still being built when this fires.
func _ready() -> void:
	RunState.stage_changed.connect(func(_index: int, _map_id: String) -> void:
		_stage_changed = true)
## One recompute per frame no matter how many kills land in it.
var _recompute_queued: bool = false
## Edge detection for the one consumer that needs a "just ended" moment
## rather than a state (the raider may be over a rock when flight stops).
var _was_flying: bool = false


## Finds the PowerUps component on a body, or null.
static func find_in(body: Node) -> PowerUps:
	if body == null:
		return null
	for child in body.get_children():
		if child is PowerUps:
			return child
	return null


## Grants a power-up. THE door: the toast, the log and the announce all
## live here, so a new source (kill drop, spring, vendor, roulette later)
## only has to call this. The star recurses once per component row, which
## is why the announcement is done here and not in _apply_row.
func apply(powerup_id: String) -> void:
	var row := PowerUpCatalog.by_id(powerup_id)
	if row.is_empty():
		push_warning("PowerUps: unknown power-up '%s'" % powerup_id)
		return
	var duration := float(row.duration) * _duration_multiplier()
	if String(row.get("kind", "")) == "star":
		# Everything at once, all of it on the star's shorter clock: the
		# star IS the jackpot, not a way to get twenty-second buffs.
		for component: Dictionary in PowerUpCatalog.star_components():
			_apply_row(component, duration)
	_apply_row(row, duration)
	_sync()
	_announce(row, duration)
	# One-line log (RunManager convention) for headless soaks.
	print("Power-up picked: %s" % powerup_id)


## Live power-ups as {id, kind, time_left}, in pickup order (the HUD row
## and the Tab overlay both read this).
func active() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in _active:
		rows.append({
			"id": String(entry.id), "kind": String(entry.kind),
			"time_left": maxf(float(entry.expires_at) - RunState.run_time, 0.0)})
	return rows


## True while any live row carries this behavior kind. The star turns them
## all on, so consumers ask this and never "is the star running".
## Seconds left on the longest live row of `kind`, or 0.0 when none is
## running. The counterpart to has() for consumers that need the clock
## rather than the flag.
func _remaining(kind: String) -> float:
	var left := 0.0
	for entry: Dictionary in _active:
		if String(entry.get("kind", "")) == kind:
			left = maxf(left, float(entry.expires_at) - RunState.run_time)
	return left


func has(kind: String) -> bool:
	for entry: Dictionary in _active:
		if String(entry.kind) == kind:
			return true
	return false


func is_active(powerup_id: String) -> bool:
	for entry: Dictionary in _active:
		if String(entry.id) == powerup_id:
			return true
	return false


func count() -> int:
	return _active.size()


## ItemBag.on_weapon_kill relays every kill this raider's weapons make.
## Modo vampiro is the only listener today.
func on_kill() -> void:
	if not has("vampire"):
		return
	permanent_max_hp += vampire_hp_per_kill
	_request_recompute()


func _physics_process(_delta: float) -> void:
	if _active.is_empty():
		return
	if _stage_changed:
		# The arena (and its spawner) was replaced under us: re-publish
		# every kind-driven state to the nodes that were just built.
		_stage_changed = false
		_sync()
	var expired := false
	for i in range(_active.size() - 1, -1, -1):
		if RunState.run_time >= float(_active[i].expires_at):
			_active.remove_at(i)
			expired = true
	if expired:
		_sync()


## Registers (or refreshes) one row for `duration` seconds and issues its
## stat boons. A refresh NEVER shortens: picking the same power-up up
## again while eight seconds are left and the roll is shorter would
## otherwise be a downgrade.
func _apply_row(row: Dictionary, duration: float) -> void:
	var powerup_id := String(row.id)
	var expires_at := RunState.run_time + duration
	var found := -1
	for i in _active.size():
		if String(_active[i].id) == powerup_id:
			found = i
			break
	if found >= 0:
		_active[found].expires_at = maxf(float(_active[found].expires_at), expires_at)
		expires_at = float(_active[found].expires_at)
	else:
		_active.append({"id": powerup_id, "kind": String(row.get("kind", "")),
				"expires_at": expires_at})
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		var tag := BOON_TAG_PREFIX + powerup_id
		# Its own boons first: without this a refresh would stack a second
		# copy of every effect and the first expiry would take back half.
		stats.clear_timed_boons(tag)
		for effect: Dictionary in row.get("effects", [] as Array):
			stats.add_timed_boon(String(effect.stat), float(effect.amount),
					expires_at - RunState.run_time, tag)
	if String(row.get("kind", "")) == "time_stop":
		# Through the group like every cross-scene call here; the spawner
		# owns the frozen set and its own thaw clock.
		get_tree().call_group("enemy_spawner", "freeze_enemies", duration)
		get_tree().call_group("hud", "announce_major", "¡TIEMPO DETENIDO!")


## Pushes every kind-driven state from the CURRENT set of live rows.
## Idempotent and cheap, and called after any change: toggling consumers
## on expiry instead would turn immortality off while a star still runs.
func _sync() -> void:
	var body := get_parent()
	var health := Health.find_in(body)
	if health != null:
		health.invulnerable = has("immortal")
		health.reflect_fraction = reflect_fraction if has("reflect") else 0.0
	if body != null and body.has_method("set_points_source"):
		if has("gold"):
			body.call("set_points_source", POINTS_SOURCE, gold_points_multiplier)
		else:
			body.call("clear_points_source", POINTS_SOURCE)
	# time_stop is a kind-driven consumer like every other one here, and
	# it lives on a node that does NOT survive a stage change: the arena's
	# spawner is freed with its arena and the next one is born with an
	# empty freeze clock, while this component (and the HUD tile counting
	# it down) rode across on the raider. Re-pushed from the live row, so
	# the freeze crosses with the party. freeze_enemies takes the MAX, so
	# saying it again is free.
	var freeze_left := _remaining("time_stop")
	if freeze_left > 0.0:
		get_tree().call_group("enemy_spawner", "freeze_enemies", freeze_left)
	var flying := has("flight")
	if _was_flying and not flying and body != null and body.has_method("end_flight"):
		# An edge, not a state: the raider may be hanging over a blocked
		# cell and has to be put down somewhere walkable.
		body.call("end_flight")
	_was_flying = flying
	active_changed.emit()


func _announce(row: Dictionary, duration: float) -> void:
	get_tree().call_group("hud", "show_loot", String(row.display_name),
			"%s (%d s)" % [String(row.get("description", "")), roundi(duration)],
			row.get("color", Color.WHITE) as Color, _player_index())


func _player_index() -> int:
	var body := get_parent()
	if body == null:
		return 0
	var index: Variant = body.get("player_index")
	return int(index) if index != null else 0


func _duration_multiplier() -> float:
	var stats := PlayerStats.find_in(get_parent())
	return stats.duration_multiplier if stats != null else 1.0


## Coalesced: an area weapon can bank a dozen vampire kills in one frame
## and each one would otherwise rebuild the whole stat layer.
func _request_recompute() -> void:
	if _recompute_queued:
		return
	_recompute_queued = true
	_flush_recompute.call_deferred()


func _flush_recompute() -> void:
	_recompute_queued = false
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()
