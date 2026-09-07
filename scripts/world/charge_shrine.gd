class_name ChargeShrine
extends Interactable
## Charge altar (iteration 47 rules): charges BY ITSELF while any raider
## stands inside the ring — no button. The ring is wide (three times the
## old one) and MARKS ITSELF as you approach: within twice its radius it
## brightens and pulses, so an altar reads as an invitation from across
## the field instead of only once you are already standing in it.
##
## What changed in iteration 47, and why:
##   - No spawn surges. Calling a burst down on the altar punished the one
##     thing the altar asks you to do (stand still), so the ritual is now
##     free and the pressure comes from the run's own ramp.
##   - No timeouts and no forfeits. Leaving the ring PAUSES the charge and
##     stepping back in resumes it; an untouched altar waits forever.
##     There is no longer any difference between a scene-placed altar and
##     one the WorldDirector raised: the old `idle_lifetime > 0` flag was
##     the single discriminator for three different behaviors and it made
##     two altars that look identical behave differently.
##   - Every altar sinks after it pays (spent_lifetime), director-spawned
##     or authored into the arena alike, so a spent one stops advertising
##     a prize it no longer has.
##   - Completing opens a CHOICE of three boons on the card picker instead
##     of rolling one at random; the raider who held the ring picks, and
##     the boon lands on the whole party (PlayerStats.add_altar_boon),
##     independent of level-up cards. Master Keys still speed the fill and
##     enlarge the boon.

## Seconds of in-ring time needed to complete.
@export var channel_time: float = 8.0
## Seconds a SPENT altar lingers before sinking away. Every altar sinks
## once it has paid — there is no permanent-scenery exception any more.
@export var spent_lifetime: float = 8.0
## Boon size multiplier (the demonic altar pays more).
@export var boon_scale: float = 1.0
@export var completed_text: String = "El altar zumba: %s para todos"
## Card-picker title and ribbon tag for the choice this altar opens.
@export var choice_title: String = "El altar te ofrece un don"
@export var choice_tag: String = "Bendición"
@export_group("Master Key")
@export var key_speed_per_copy: float = 0.2
@export var key_boon_per_copy: float = 0.2

## Sfx loop held while channeling (ref-counted through _hold_loop, so the
## Humming Skull can hold the same voice at the same time).
const CHANNEL_LOOP: StringName = &"shrine_channel"

## Idle bob/spin of the crystal, and the faster pulse while charging.
const CRYSTAL_SPIN: float = 1.4
const CRYSTAL_BOB_HZ: float = 2.1
const CRYSTAL_BOB_HEIGHT: float = 0.12
const CRYSTAL_PULSE_HZ: float = 9.0
const CRYSTAL_PULSE_AMOUNT: float = 0.12
## Fallback ring radius when the scene ships no cylindrical zone shape.
## Matches ChargeShrine.tscn, so a malformed altar still looks right.
const DEFAULT_ZONE_RADIUS: float = 9.3
## The progress disc sits just inside the ring: derived from the zone
## shape, never a constant of its own — the two used to be separate
## numbers and the disc quietly stopped matching the ring it fills.
const PROGRESS_DISC_SHARE: float = 0.97
## A raider within this many ring radii marks the altar (brighter, pulsing).
const APPROACH_BAND_SCALE: float = 2.0
const MARK_PULSE_HZ: float = 3.4
## Ring/disc emission at rest, while marked, and while charging.
const RING_ENERGY_IDLE: float = 1.1
const RING_ENERGY_MARKED: float = 3.0
const RING_ENERGY_CHANNEL: float = 3.6
const RING_ALPHA_IDLE: float = 0.55
const RING_ALPHA_MARKED: float = 0.85
const PROGRESS_DISC_ALPHA: float = 0.26
## Boons offered on completion.
const ALTAR_CHOICE_COUNT: int = 3
## Prompt shown after an interrupted charge. There is no button anywhere on
## this altar (see _init), so the resume line points back at the ring
## instead of promising a key nobody can press.
const RESUME_TEXT: String = "Vuelve a entrar para reanudar (%d%%)"

## Flat boons a charge can land on: {stat, amount, name, label}.
## `stat` is a PlayerStats id; `name` titles the card (glosario: caja baja
## tipo oración) and `label` carries exactly one "%d", filled with the
## rarity-free, key-scaled amount.
const ALTAR_BOONS: Array[Dictionary] = [
	{"stat": "damage", "amount": 10.0, "name": "Furia", "label": "daño +%d%%"},
	{"stat": "cooldown", "amount": 6.0, "name": "Ritmo",
		"label": "velocidad de ataque +%d%%"},
	{"stat": "area", "amount": 10.0, "name": "Amplitud", "label": "área +%d%%"},
	{"stat": "move_speed", "amount": 6.0, "name": "Ligereza", "label": "velocidad +%d%%"},
	{"stat": "max_hp", "amount": 20.0, "name": "Vigor", "label": "HP máx. +%d"},
	{"stat": "armor", "amount": 2.0, "name": "Coraza", "label": "armadura +%d"},
	{"stat": "luck", "amount": 10.0, "name": "Fortuna", "label": "suerte +%d"},
	{"stat": "crit_chance", "amount": 5.0, "name": "Precisión",
		"label": "prob. de crítico +%d%%"},
	{"stat": "xp_gain", "amount": 8.0, "name": "Sabiduría",
		"label": "ganancia de XP +%d%%"},
	# The demonic altar scales this one past 1, so the label has to hold
	# for both counts ("+1 proyectil(es)" reads as a set, not a typo).
	{"stat": "projectiles", "amount": 1.0, "name": "Multitud",
		"label": "+%d proyectil(es)"},
	# Iteration 48 stats. "Salto" is capped inside PlayerStats
	# (MAX_EXTRA_JUMPS), so a lucky run cannot stack it into flight.
	{"stat": "jumps", "amount": 1.0, "name": "Impulso", "label": "+%d salto(s)"},
	{"stat": "powerup_chance", "amount": 10.0, "name": "Fortuna menor",
		"label": "prob. de power-up +%d%%"},
]

var channeling: bool = false
var progress: float = 0.0
var _time: float = 0.0
var _leaving: bool = false
var _crystal: MeshInstance3D = null
var _progress_disc: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _crystal_rest_y: float = 0.0
## Radius of this altar's own zone shape; the ring visuals, the approach
## band and the progress disc all derive from it.
var _zone_radius: float = DEFAULT_ZONE_RADIUS
## Per-instance materials for the ring and the disc (see _own_material).
var _ring_material: StandardMaterial3D = null
var _disc_material: StandardMaterial3D = null


func _init() -> void:
	meta_stat_id = "shrines_used"
	marker_kind = &"altar"
	# Proximity charges the altar; there is no button, so the prompt must
	# not offer one. Scenes MUST NOT override this (a scene value wins over
	# _init and used to put a dead "[E] ..." line back on the label).
	prompt_text = "Quédate dentro para cargar"


func _ready() -> void:
	super()
	# The WorldDirector caps how many UNSPENT altars may stand at once and
	# has no other way to find the ones an arena shipped; groups over node
	# paths, as everywhere else.
	add_to_group("altars")
	_zone_radius = _measure_zone_radius()
	_crystal = get_node_or_null("Visual/Crystal") as MeshInstance3D
	if _crystal != null:
		_crystal_rest_y = _crystal.position.y
	_ring = get_node_or_null("Visual/Ring") as MeshInstance3D
	_ring_material = _own_material(_ring, RING_ALPHA_IDLE, RING_ENERGY_IDLE)
	_progress_disc = get_node_or_null("Visual/ProgressDisc") as MeshInstance3D
	if _progress_disc == null:
		_progress_disc = _build_progress_disc()
	_disc_material = _own_material(_progress_disc, PROGRESS_DISC_ALPHA, RING_ENERGY_IDLE)


## Radius of this altar's charge zone, read off the scene's own shape so
## the ring visuals, the approach band and the disc can never drift from
## the area the player is actually standing in.
func _measure_zone_radius() -> float:
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var cylinder := shape_node.shape as CylinderShape3D
		if cylinder != null:
			return cylinder.radius
	return DEFAULT_ZONE_RADIUS


## A material this altar owns. Both the ring and the disc are tinted and
## pulsed every frame, and a .tscn [sub_resource] is ONE object shared by
## every instance of the scene (project convention), so writing through
## the scene's own material would pulse every altar in the arena at once.
func _own_material(target: MeshInstance3D, alpha: float,
		energy: float) -> StandardMaterial3D:
	if target == null:
		return null
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(_accent_color(), alpha)
	material.emission_enabled = true
	material.emission = _accent_color()
	material.emission_energy_multiplier = energy
	target.material_override = material
	return material


## Flat disc that grows with the charge (built here for altar scenes
## that don't ship one, e.g. the demonic obelisk).
func _build_progress_disc() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var radius := _zone_radius * PROGRESS_DISC_SHARE
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
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
	_tick_marking()
	if not channeling:
		# A banked charge restarts on proximity, and body_entered will NOT
		# fire again for a raider revived on the spot (the corpse never
		# left the Area3D, so the cancel below came from the live-players
		# check, not from an exit). Polling the ring here is what keeps
		# such an altar from sitting on its resume prompt forever.
		if available and not live_players_in_range().is_empty():
			_on_range_entered()
		return
	# A downed raider never leaves the Area3D, so body_exited alone would
	# let a corpse hold the ritual.
	if live_players_in_range().is_empty():
		_on_range_exited()
		return
	progress += delta * _charge_speed()
	_progress_disc.visible = true
	var fraction := clampf(progress / channel_time, 0.001, 1.0)
	_progress_disc.scale = Vector3(fraction, 1.0, fraction)
	set_prompt("Cargando... %d%%" % roundi(fraction * 100.0))
	if progress >= channel_time:
		_complete()


## The ring reads at three distances: dim at rest, bright and pulsing once
## a raider is inside the approach band, brightest while charging. Without
## this an altar was invisible until you were already standing in it, which
## is exactly the walk nobody made.
func _tick_marking() -> void:
	if _ring_material == null and _disc_material == null:
		return
	var energy := RING_ENERGY_IDLE
	var alpha := RING_ALPHA_IDLE
	if channeling:
		energy = RING_ENERGY_CHANNEL
		alpha = RING_ALPHA_MARKED
	elif available and _player_near():
		var beat := 0.5 + 0.5 * sin(_time * MARK_PULSE_HZ)
		energy = lerpf(RING_ENERGY_IDLE, RING_ENERGY_MARKED, beat)
		alpha = lerpf(RING_ALPHA_IDLE, RING_ALPHA_MARKED, beat)
	if _ring_material != null:
		_ring_material.emission_energy_multiplier = energy
		_ring_material.albedo_color.a = alpha
	if _disc_material != null:
		_disc_material.emission_energy_multiplier = energy


## Any raider still standing within the approach band. Live players only:
## a corpse lying in the band is not somebody walking up to the altar.
func _player_near() -> bool:
	var band := _zone_radius * APPROACH_BAND_SCALE
	var band_sq := band * band
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as Node3D
		if body != null and global_position.distance_squared_to(body.global_position) <= band_sq:
			return true
	return false


## Master Keys held by the raider(s) still standing in the ring: the best
## count wins (a downed body's bag no longer counts).
func _keys_in_ring() -> int:
	return best_item_count_in_range("master_key")


func _charge_speed() -> float:
	return 1.0 + key_speed_per_copy * float(_keys_in_ring())


## No button: stepping in starts (or resumes) the charge.
func _on_range_entered() -> void:
	if not available or channeling or _leaving:
		return
	channeling = true
	# Ref-counted: another altar (or the Humming Skull, which shares the
	# id) channeling at the same time keeps its own hold on the voice.
	_hold_loop(CHANNEL_LOOP)
	_emit_started()


## Stepping out mid-charge only PAUSES it (iteration 47): the banked
## progress stays and stepping back in resumes it. Nothing is forfeited
## and nothing sinks — an altar you walked away from is still an altar.
func _on_range_exited() -> void:
	if not channeling:
		return
	channeling = false
	_drop_loop()
	_emit_cancelled()
	set_prompt(RESUME_TEXT % roundi(clampf(progress / channel_time, 0.0, 1.0) * 100.0))


func _interact(_player: Node) -> void:
	pass  # proximity does everything; the interact button is a no-op


func _complete() -> void:
	channeling = false
	_drop_loop()
	progress = channel_time
	var keys := _keys_in_ring()
	# Resolved BEFORE consume(): the prize belongs to whoever held the ring,
	# and in co-op the card picker must be told so instead of falling back
	# to its round-robin.
	var recipient := nearest_live_player()
	consume()
	set_physics_process(false)
	if _crystal != null:
		_crystal.scale = Vector3.ONE
	_progress_disc.visible = false
	dim_visuals()
	_offer_reward(keys, recipient)
	_emit_completed()
	# Every altar clears the field once it has paid.
	if spent_lifetime > 0.0:
		# NOT process_always: the choice above holds the tree paused, and a
		# timer that ignored the pause would sink (and free) this altar
		# while its own menu was still on screen.
		get_tree().create_timer(spent_lifetime, false).timeout.connect(
				_leave.bind("se apaga: ya rindió su premio"))


## Opens the payoff menu on the card picker (group "upgrade_ui"), which
## owns the pause contract, the queue and the co-op title. Deliberately
## NOT a menu of its own: a second blocking UI is a second way to wedge a
## run, and the soak harness only knows how to answer this one.
func _offer_reward(keys: int, recipient: Node) -> void:
	var options := _reward_options(keys)
	if options.is_empty():
		return
	get_tree().call_group("upgrade_ui", "open_choice", choice_title, options,
			recipient, _on_choice_picked.bind(keys, recipient), choice_tag)


## Virtual: the options this altar offers. Charge altars draw
## ALTAR_CHOICE_COUNT DISTINCT boons; the demonic altar offers pacts.
func _reward_options(keys: int) -> Array[Dictionary]:
	var pool := ALTAR_BOONS.duplicate()
	pool.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(ALTAR_CHOICE_COUNT, pool.size()):
		var boon: Dictionary = pool[i]
		var amount := boon_amount(float(boon.amount), keys)
		var label := String(boon.label) % roundi(amount)
		options.append({
			"title": String(boon.name),
			"description": label + " para toda la party",
			"color": _accent_color(),
			"label": label,
			"stat": String(boon.stat),
			"amount": amount,
		})
	return options


## The card picker hands the chosen option back here.
func _on_choice_picked(option: Dictionary, keys: int, recipient: Node) -> void:
	if not is_inside_tree():
		return
	var label := _grant_choice(option, keys, recipient)
	if label.is_empty():
		return
	get_tree().call_group("hud", "announce", completed_text % label)
	# One-line log (RunManager convention) for headless soaks.
	print("Altar charged: %s -> %s" % [name, label])


## Virtual: applies one chosen option and returns the text to announce.
## The demonic altar overrides this to pay a pact's benefit AND its cost.
func _grant_choice(option: Dictionary, _keys: int, _recipient: Node) -> String:
	grant_boon(String(option.stat), float(option.amount))
	return String(option.label)


## One boon's size at grant time: the base amount, this altar's scale and
## the charger's Master Keys. Never below 1, so a rounded-down boon is
## still a boon.
func boon_amount(base: float, keys: int) -> float:
	var amount := base * _effective_boon_scale() * (1.0 + key_boon_per_copy * float(keys))
	return maxf(roundf(amount), 1.0)


## Boon multiplier at grant time. Virtual so the demonic altar can fold in
## its Demon Blood scaling WITHOUT writing to the exported knob (mutating
## boon_scale and dividing it back left float drift and broke the moment
## any path returned early).
func _effective_boon_scale() -> float:
	return boon_scale


## Party-wide flat boon (co-op shares altar stats by design). Downed
## raiders are still in the party: they left the "player" group on the way
## down, and altar boons are PERMANENT for the run, so skipping them would
## hand them a deficit nothing ever repays.
func grant_boon(stat: String, amount: float) -> void:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var stats := PlayerStats.find_in(node)
			if stats != null:
				stats.add_altar_boon(stat, amount)


## Sink-and-shrink exit; frees itself. Only a spent altar takes it now.
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
