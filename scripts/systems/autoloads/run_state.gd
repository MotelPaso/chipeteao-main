extends Node
## Autoload "RunState": the current run's XP, level, kills, and elapsed
## time, plus run-scoped stat multipliers that upgrades modify and other
## systems read (loose coupling through this singleton instead of node
## references). Default process_mode is pausable, so run_time freezes
## while the upgrade-card UI has the tree paused.

signal xp_changed(current_xp: int, xp_to_next: int)
signal leveled_up(new_level: int)
signal kills_changed(total_kills: int)
## Run-wide difficulty changed (Tome of Peril, demonic altars).
signal difficulty_changed(bonus: float)
## A new stage is live (iteration 49): the arena is in the tree and the
## party has been placed. `stage_index` is 0-based; everything the player
## or a soak log reads prints it as stage_index + 1.
signal stage_changed(stage_index: int, map_id: String)

var xp: int = 0
var level: int = 1
## Cost of the first level-up (reset() re-derives it from the curve).
var xp_to_next: int = XP_BASE + XP_PER_LEVEL
var kills: int = 0
var run_time: float = 0.0
## --- Stage progression (iteration 49) -----------------------------------
## A run is a sequence of STAGES, one map each, in MapCatalog order,
## wrapping back to the first map with lap + 1. Everything about the party
## carries across; only the map and its clock reset.
## 0-based index into MapCatalog.MAP_LIBRARY.
var stage_index: int = 0
## Completed loops of the map list. 0 on the first pass.
var lap: int = 0
## Seconds spent in the CURRENT stage. run_time keeps counting the whole
## run; this one is what the stage gate, the boss schedule and the hordes
## read, so a stage always plays out the same however late it comes.
var stage_time: float = 0.0
## True once this stage's Elder is dead (RunManager sets it).
var stage_boss_dead: bool = false
## True once this stage's gate opened (time AND boss): the exit portal is
## out and the pseudo-infinite ramp is running.
var stage_cleared: bool = false
## Seconds since this stage was cleared — the pseudo-infinite clock.
var pseudo_infinite_time: float = 0.0
## Run totals, folded into the meta ledger at the end.
var stages_cleared_total: int = 0
var endless_seconds_total: float = 0.0
var laps_completed: int = 0
## Maps entered / cleared this run, in order. The meta fold credits
## runs_on_<map> for every visited one and victories_<map> for every
## cleared one, so per-map quests keep working across a multi-map run.
var visited_map_ids: Array[String] = []
var cleared_map_ids: Array[String] = []
## True while the run is in progress; RunManager clears it when the run
## ends (death or victory) so late same-frame events like a level-up
## card stand down.
var run_active: bool = true
## Multiplies every gem's magnet radius; raised by pickup-radius upgrades.
var pickup_radius_multiplier: float = 1.0
## Demonic altar completions this run (iteration 41): bosses drop one
## extra chest per use, elites and hordes read it too.
var demonic_uses: int = 0
## Run-wide difficulty bonus (iteration 39), as a fraction: 0.3 = +30%.
## Shared by the whole party. Fresh spawns scale HP/damage by
## (1 + bonus) and XP by (1 + bonus * DIFFICULTY_XP_SHARE). Sources add
## through add_difficulty (tomes re-publish their total per player via
## set_difficulty_source so recompute-from-scratch stays exact).
var difficulty_bonus: float = 0.0
## Per-source difficulty contributions (source id -> fraction).
var _difficulty_sources: Dictionary[String, float] = {}
## Fraction of the difficulty bonus that becomes extra XP on every gem.
const DIFFICULTY_XP_SHARE: float = 0.75
## Demonic pacts (iteration 47): the run-wide knobs a pact's COST writes.
## Each is a fraction (0.1 = +10%) and each has exactly one consumer, named
## here so a knob can never quietly become dead data:
##   elite_chance_bonus     -> EnemySpawner.elite_chance()
##   sky_duration_multiplier-> WorldDirector sky event length
##   event_chance_bonus     -> WorldDirector sky event probability
##   disaster_chance_bonus  -> WorldDirector disaster roll (iteration 55:
##                             the first thing rolled on an event tick).
var elite_chance_bonus: float = 0.0
var sky_duration_multiplier: float = 1.0
var event_chance_bonus: float = 0.0
var disaster_chance_bonus: float = 0.0
## Chest economy (iteration 40): base price in run points per rarity, and
## the GLOBAL multiplier every opened chest applies to all the others.
const CHEST_BASE_PRICES: Dictionary[String, int] = {
	"Common": 20, "Rare": 40, "Epic": 80, "Legendary": 160}
const CHEST_PRICE_GROWTH: float = 1.25
## Party-wide chest price multiplier, one CHEST_PRICE_GROWTH step per chest
## opened this run. It is the ONLY chest bookkeeping this run needs — the
## lifetime "chests_opened" counter the quests read lives in SaveData and
## is bumped by Interactable.consume, so there is no second copy here to
## drift out of sync with it.
var chest_price_multiplier: float = 1.0
## Roulette economy (iteration 46): each spin DOUBLES the price of every
## later spin this run. Steeper than the chest curve on purpose — a
## roulette outcome can be a Legendary item, so a flat price turned the
## altar into the whole run's build once the points started flowing.
const ROULETTE_PRICE_GROWTH: float = 2.0
var roulette_price_multiplier: float = 1.0
## What the power-up vendor asks for its first sale of the run.
const POWERUP_VENDOR_BASE_PRICE: int = 100
## What the power-up vendor charges next, in run points (iteration 54).
## A run-wide ABSOLUTE price, not a multiplier like the two above: the
## stall sells one rolled power-up whatever it is, so there is no base to
## multiply — the number itself is the ladder, and it climbs only when a
## sale actually happens.
var powerup_vendor_price: int = POWERUP_VENDOR_BASE_PRICE
## Multiplier on everything the party BUYS with run points while the
## golden rain falls (1.0 idle, 0.5 during it). Chests, the roulette and
## the spring read it — and therefore the item vendor, which prices its
## shelf off chest_price. The power-up vendor and the pet prices are
## deliberately outside it: those two ladders are the run's long-term
## economy, and halving them for forty seconds would flatten both.
var price_discount: float = 1.0
## XP curve: cost of the level being climbed to, in gems (level 1 -> 2
## costs XP_BASE + XP_PER_LEVEL). The whole pacing of a run rides on these
## three numbers, so they are named instead of buried in _xp_required.
## Env override that makes a whole run reproducible (see reset()).
## Test-only; nothing in the game sets it.
const GAME_SEED_ENV: String = "BONK_GAME_SEED"

const XP_BASE: int = 5
const XP_PER_LEVEL: int = 3
## Convex term (iteration 46): the old straight line let a late run take a
## level every few seconds, which is what made weapons cap out and cards
## stop meaning anything. Quadratic, so the first levels are untouched
## (level 1 still costs 8) and the late ones bite: level 10 costs 50
## instead of 35 (+43%), level 20 costs 125 instead of 65 (+92%).
const XP_PER_LEVEL_SQUARED: float = 0.15


func _ready() -> void:
	reset()


func _physics_process(delta: float) -> void:
	# Only a live run advances the clock: once RunManager flags the run over
	# (or before one starts), anything reading run_time — victory grading,
	# timed boons, the daily score — must not see it creep forward on the
	# frames where something unpauses the tree.
	if run_active:
		run_time += delta
		stage_time += delta
		if stage_cleared:
			pseudo_infinite_time += delta
			endless_seconds_total += delta


## Call at the start of a new run.
func reset() -> void:
	xp = 0
	level = 1
	kills = 0
	run_time = 0.0
	run_active = true
	stage_index = 0
	lap = 0
	stages_cleared_total = 0
	endless_seconds_total = 0.0
	laps_completed = 0
	visited_map_ids = []
	cleared_map_ids = []
	begin_stage()
	pickup_radius_multiplier = 1.0
	demonic_uses = 0
	elite_chance_bonus = 0.0
	sky_duration_multiplier = 1.0
	event_chance_bonus = 0.0
	disaster_chance_bonus = 0.0
	difficulty_bonus = 0.0
	_difficulty_sources.clear()
	chest_price_multiplier = 1.0
	roulette_price_multiplier = 1.0
	powerup_vendor_price = POWERUP_VENDOR_BASE_PRICE
	price_discount = 1.0
	# Counters credited during a run live in a SaveData buffer that only a
	# run END merges into the persisted ledger; starting (or abandoning) a
	# run drops whatever is still pending, which is what makes save_data's
	# "an abandoned run persists nothing" contract actually hold. Fetched by
	# path: this autoload loads BEFORE SaveData, so the very first reset
	# (app startup) must not touch it by name.
	var ledger := get_node_or_null("/root/SaveData")
	if ledger != null:
		ledger.call("discard_run_counters")
	# Daily Hunt (iteration 36): everyone rolls the same cards, spawns, and
	# world events for a given date; normal runs re-scramble the stream.
	# Fetched by path: this autoload loads BEFORE GameConfig, so the very
	# first reset (app startup, never a daily) must not touch it by name.
	var config := get_node_or_null("/root/GameConfig")
	var game_seed := OS.get_environment(GAME_SEED_ENV)
	if config != null and bool(config.daily_mode) and int(config.daily_seed) != 0:
		seed(int(config.daily_seed))
	elif game_seed.is_valid_int():
		# Test-only (BONK_GAME_SEED): the run's own stream — cards, spawns,
		# the scatter and therefore the terrain — becomes reproducible.
		# Without it a soak is a fresh world every time, which makes any
		# two-sided comparison (balance, fog coverage) measure noise.
		seed(int(game_seed))
	else:
		randomize()
	xp_to_next = _xp_required(level)
	xp_changed.emit(xp, xp_to_next)
	kills_changed.emit(kills)
	difficulty_changed.emit(difficulty_bonus)


## Clears the per-stage fields. Called by reset() and by RunRoot on every
## stage change — the run-level counters above are deliberately NOT here.
func begin_stage() -> void:
	stage_time = 0.0
	stage_boss_dead = false
	stage_cleared = false
	pseudo_infinite_time = 0.0


## Records that the current stage was cleared. Idempotent: the gate is
## polled, so it would otherwise credit a stage once per frame.
func mark_stage_cleared(map_id: String) -> void:
	if stage_cleared:
		return
	stage_cleared = true
	stages_cleared_total += 1
	if not cleared_map_ids.has(map_id):
		cleared_map_ids.append(map_id)


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	# Loop: a single big pickup can grant several levels; one leveled_up
	# fires per level so the card UI can queue extra picks.
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = _xp_required(level)
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next)


func add_kill() -> void:
	kills += 1
	kills_changed.emit(kills)


## Sets one source's difficulty contribution (e.g. "tomes_p0" for player
## 0's Tome of Peril total) and re-sums the run-wide bonus. Sources that
## recompute from scratch (PlayerStats) call this with their whole total.
func set_difficulty_source(source: String, fraction: float) -> void:
	if is_zero_approx(fraction):
		_difficulty_sources.erase(source)
	else:
		_difficulty_sources[source] = fraction
	_resum_difficulty()


## Adds a permanent one-shot contribution (demonic altar uses).
func add_difficulty(fraction: float, source: String = "altars") -> void:
	if fraction <= 0.0:
		return
	_difficulty_sources[source] = float(_difficulty_sources.get(source, 0.0)) + fraction
	_resum_difficulty()


func _resum_difficulty() -> void:
	var total := 0.0
	for source: String in _difficulty_sources:
		total += _difficulty_sources[source]
	difficulty_bonus = maxf(total, 0.0)
	difficulty_changed.emit(difficulty_bonus)


## Current price of a chest of the given rarity, in run points.
func chest_price(rarity_name: String) -> int:
	var base := int(CHEST_BASE_PRICES.get(rarity_name, CHEST_BASE_PRICES["Common"]))
	return ceili(float(base) * chest_price_multiplier * price_discount)


## Every opened chest makes all the others pricier (global multiplier).
func register_chest_opened() -> void:
	chest_price_multiplier *= CHEST_PRICE_GROWTH


## Current price of a roulette spin, in run points: the shrine's own base
## price times the run-wide growth below.
func roulette_price(base_price: int) -> int:
	return ceili(float(base_price) * roulette_price_multiplier * price_discount)


## Every spin makes the next one cost ROULETTE_PRICE_GROWTH times more,
## for the whole party and the rest of the run.
func register_roulette_spin() -> void:
	roulette_price_multiplier *= ROULETTE_PRICE_GROWTH


## XP multiplier the run-wide difficulty grants on every gem.
func difficulty_xp_multiplier() -> float:
	return 1.0 + difficulty_bonus * DIFFICULTY_XP_SHARE


func _xp_required(for_level: int) -> int:
	return XP_BASE + for_level * XP_PER_LEVEL \
			+ roundi(XP_PER_LEVEL_SQUARED * float(for_level * for_level))
