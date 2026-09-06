class_name ChargeShrine
extends Interactable
## Charge altar (iteration 41 rules): charges BY ITSELF while any raider
## stands inside the ring — no button — calling spawn surges down on the
## spot for pressure. Leaving the ring before it completes forfeits a
## TEMPORARY altar (one of the WorldDirector's timed events: it sinks away
## for good, because "stay and hold" is the whole point of the window),
## while an altar authored into an arena only pauses — its charge stays
## banked and stepping back in resumes it. An altar nobody touches for
## `idle_lifetime` seconds leaves on its own (the WorldDirector keeps
## spawning fresh ones). Completing grants a random FLAT stat boon to the
## whole party — independent of level-up cards, never weapon levels —
## through PlayerStats.add_altar_boon; the charging raider's Master Keys
## speed the fill and enlarge the boon.

## Seconds of in-ring time needed to complete.
@export var channel_time: float = 8.0
## Seconds an untouched altar waits before leaving (0 = stays forever;
## scene-placed altars use 0, WorldDirector spawns set a lifetime).
@export var idle_lifetime: float = 0.0
## Seconds a SPENT altar lingers before sinking away, for the temporary
## altars only (the ones the WorldDirector gives an idle_lifetime). Altars
## authored into an arena are scenery and stay put forever, as before.
@export var spent_lifetime: float = 8.0
## Boon size multiplier (the demonic altar pays more).
@export var boon_scale: float = 1.0
@export var completed_text: String = "El altar zumba: %s para todos"
@export_group("Master Key")
@export var key_speed_per_copy: float = 0.2
@export var key_boon_per_copy: float = 0.2
@export_group("Spawn Surge")
## Seconds between surge bursts while channeling.
@export var surge_interval: float = 2.0
## Enemies per surge burst (spawner-side radii decide where they land).
@export var surge_count: int = 4

## Sfx loop held while channeling (ref-counted through _hold_loop, so the
## Humming Skull can hold the same voice at the same time).
const CHANNEL_LOOP: StringName = &"shrine_channel"

## Idle bob/spin of the crystal, and the faster pulse while charging.
const CRYSTAL_SPIN: float = 1.4
const CRYSTAL_BOB_HZ: float = 2.1
const CRYSTAL_BOB_HEIGHT: float = 0.12
const CRYSTAL_PULSE_HZ: float = 9.0
const CRYSTAL_PULSE_AMOUNT: float = 0.12
## Radius of the flat progress disc built for altar scenes without one.
const PROGRESS_DISC_RADIUS: float = 3.0
## Prompt a PERMANENT altar shows after an interrupted charge. There is no
## button anywhere on this altar (see _init), so the resume line points
## back at the ring instead of promising a key nobody can press.
const RESUME_TEXT: String = "Vuelve a entrar para reanudar (%d%%)"

## Flat boons a charge can land on: {stat, amount} (PlayerStats ids).
const ALTAR_BOONS: Array[Dictionary] = [
	{"stat": "damage", "amount": 10.0, "label": "daño +%d%%"},
	{"stat": "cooldown", "amount": 6.0, "label": "enfriamientos -%d%%"},
	{"stat": "area", "amount": 10.0, "label": "área +%d%%"},
	{"stat": "move_speed", "amount": 6.0, "label": "velocidad +%d%%"},
	{"stat": "max_hp", "amount": 20.0, "label": "HP máx. +%d"},
	{"stat": "armor", "amount": 2.0, "label": "armadura +%d"},
	{"stat": "luck", "amount": 10.0, "label": "suerte +%d"},
	{"stat": "crit_chance", "amount": 5.0, "label": "prob. de crítico +%d%%"},
	{"stat": "xp_gain", "amount": 8.0, "label": "ganancia de XP +%d%%"},
	# The demonic altar scales this one past 1, so the label has to hold
	# for both counts ("+1 proyectil(es)" reads as a set, not a typo).
	{"stat": "projectiles", "amount": 1.0, "label": "+%d proyectil(es)"},
]

var channeling: bool = false
var progress: float = 0.0
var _surge_timer: float = 0.0
var _time: float = 0.0
var _idle_left: float = 0.0
var _leaving: bool = false
var _crystal: MeshInstance3D = null
var _progress_disc: MeshInstance3D = null
var _crystal_rest_y: float = 0.0


func _init() -> void:
	meta_stat_id = "shrines_used"
	# Proximity charges the altar; there is no button, so the prompt must
	# not offer one. Scenes MUST NOT override this (a scene value wins over
	# _init and used to put a dead "[E] ..." line back on the label).
	prompt_text = "Quédate dentro para cargar"


func _ready() -> void:
	super()
	_crystal = get_node_or_null("Visual/Crystal") as MeshInstance3D
	if _crystal != null:
		_crystal_rest_y = _crystal.position.y
	_progress_disc = get_node_or_null("Visual/ProgressDisc") as MeshInstance3D
	if _progress_disc == null:
		_progress_disc = _build_progress_disc()
	_idle_left = idle_lifetime


## Flat disc that grows with the charge (built here for altar scenes
## that don't ship one, e.g. the demonic obelisk).
func _build_progress_disc() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = PROGRESS_DISC_RADIUS
	mesh.bottom_radius = PROGRESS_DISC_RADIUS
	mesh.height = 0.04
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(_accent_color(), 0.26)
	material.emission_enabled = true
	material.emission = _accent_color()
	mesh.material = material
	disc.mesh = mesh
	disc.position.y = 0.06
	disc.scale = Vector3(0.001, 1.0, 0.001)
	disc.visible = false
	add_child(disc)
	return disc


## Ring/disc color; the demonic altar overrides it red.
func _accent_color() -> Color:
	return Color(0.4, 0.8, 1.0)


func _physics_process(delta: float) -> void:
	if _leaving:
		return
	_time += delta
	if _crystal != null:
		_crystal.rotate_y(delta * CRYSTAL_SPIN)
		_crystal.position.y = _crystal_rest_y + sin(_time * CRYSTAL_BOB_HZ) * CRYSTAL_BOB_HEIGHT
		var pulse := CRYSTAL_PULSE_AMOUNT * sin(_time * CRYSTAL_PULSE_HZ) if channeling else 0.0
		_crystal.scale = Vector3.ONE * (1.0 + pulse)
	if not channeling:
		if idle_lifetime > 0.0:
			if available:
				_idle_left -= delta
				if _idle_left <= 0.0:
					_leave("fades away, unclaimed")
			return
		# Permanent altar with a banked charge: proximity is the only way
		# to restart it, and body_entered will NOT fire again for a raider
		# revived on the spot (the corpse never left the Area3D, so the
		# cancel below came from the live-players check, not from an exit).
		# Polling the ring here is what keeps such an altar from sitting on
		# its resume prompt forever.
		if available and not live_players_in_range().is_empty():
			_on_range_entered()
		return
	# A downed raider never leaves the Area3D, so body_exited alone would
	# let a corpse hold the ritual (and keep calling surges down on it).
	if live_players_in_range().is_empty():
		_on_range_exited()
		return
	progress += delta * _charge_speed()
	_surge_timer -= delta
	if _surge_timer <= 0.0:
		_surge_timer = surge_interval
		get_tree().call_group(
				"enemy_spawner", "spawn_pressure_burst", global_position, surge_count)
	_progress_disc.visible = true
	var fraction := clampf(progress / channel_time, 0.001, 1.0)
	_progress_disc.scale = Vector3(fraction, 1.0, fraction)
	set_prompt("Cargando... %d%%" % roundi(fraction * 100.0))
	if progress >= channel_time:
		_complete()


## Master Keys held by the raider(s) still standing in the ring: the best
## count wins (a downed body's bag no longer counts).
func _keys_in_ring() -> int:
	return best_item_count_in_range("master_key")


func _charge_speed() -> float:
	return 1.0 + key_speed_per_copy * float(_keys_in_ring())


## No button: stepping in starts the charge.
func _on_range_entered() -> void:
	if not available or channeling or _leaving:
		return
	channeling = true
	_surge_timer = 0.0  # first surge lands immediately: pressure from second one
	# Ref-counted: another altar (or the Humming Skull, which shares the
	# id) channeling at the same time keeps its own hold on the voice.
	_hold_loop(CHANNEL_LOOP)
	_emit_started()


## Stepping out mid-charge. Same rule the completed path uses below: only
## the WorldDirector's temporary altars (the ones given an idle_lifetime)
## leave the field. An altar authored into an arena is permanent scenery,
## so it keeps its banked progress and offers to resume — abandoning a
## charge must never delete a fixture the arena is built around.
func _on_range_exited() -> void:
	if not channeling:
		return
	channeling = false
	_drop_loop()
	_emit_cancelled()
	if idle_lifetime > 0.0:
		_leave("sinks away, released")
		return
	set_prompt(RESUME_TEXT % roundi(clampf(progress / channel_time, 0.0, 1.0) * 100.0))


func _interact(_player: Node) -> void:
	pass  # proximity does everything; the interact button is a no-op


func _complete() -> void:
	channeling = false
	_drop_loop()
	progress = channel_time
	var keys := _keys_in_ring()
	consume()
	set_physics_process(false)
	if _crystal != null:
		_crystal.scale = Vector3.ONE
	_progress_disc.visible = false
	dim_visuals()
	_grant_reward(keys)
	_emit_completed()
	# The director's temporary altars clear the field once they have paid;
	# altars authored into an arena (idle_lifetime 0) stay as scenery.
	if idle_lifetime > 0.0 and spent_lifetime > 0.0:
		get_tree().create_timer(spent_lifetime).timeout.connect(
				_leave.bind("se apaga: ya rindió su premio"))


## Boon multiplier at grant time. Virtual so the demonic altar can fold in
## its Demon Blood scaling WITHOUT writing to the exported knob (mutating
## boon_scale and dividing it back left float drift and broke the moment
## any path returned early).
func _effective_boon_scale() -> float:
	return boon_scale


## Party-wide flat boon (co-op shares altar stats by design), enlarged by
## the charger's Master Keys and this altar's boon scale.
func _grant_reward(keys: int) -> void:
	var boon: Dictionary = ALTAR_BOONS.pick_random()
	var amount := float(boon.amount) * _effective_boon_scale() \
			* (1.0 + key_boon_per_copy * float(keys))
	amount = maxf(roundf(amount), 1.0)
	# Downed raiders are still in the party: they left the "player" group
	# on the way down, and altar boons are PERMANENT for the run, so
	# skipping them would hand them a deficit nothing ever repays.
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var stats := PlayerStats.find_in(node)
			if stats != null:
				stats.add_altar_boon(String(boon.stat), amount)
	var label := String(boon.label) % roundi(amount)
	get_tree().call_group("hud", "announce", completed_text % label)
	# One-line log (RunManager convention) for headless soaks.
	print("Altar charged: %s -> %s" % [name, label])


## Sink-and-shrink exit; frees itself. Used by both forfeits and timeouts.
func _leave(reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	available = false
	_refresh_prompt()
	set_physics_process(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 2.5, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.2, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
	print("Altar left: %s %s" % [name, reason])
