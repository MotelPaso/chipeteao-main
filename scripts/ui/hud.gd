extends CanvasLayer
## In-game HUD (GDD 9.5): HP bar with numeric readout, thin XP bar with a
## level tag, MM:SS run timer, kill counter, plus a top-center boss HP bar
## (shown only while a boss lives) and a boss-arrival banner, both driven
## through the "boss_ui" group. Loose coupling: finds the player via its
## group at ready and RunState via the autoload; signals
## drive every update (only the timer text polls, in _process). Default
## pausable process mode is fine — run_time freezes with the tree and the
## upgrade-card layer (10) draws above this one (5).

## At or above this HP ratio the bar is full green; below it the color
## ramps toward red.
const LOW_HP_RATIO := 0.6

const BAR_BG_COLOR := Color(0.05, 0.06, 0.09, 0.8)
const PANEL_COLOR := Color(0.07, 0.08, 0.11, 0.72)
const HP_FULL_COLOR := Color(0.36, 0.8, 0.42)
const HP_LOW_COLOR := Color(0.9, 0.22, 0.2)
## Matches the XP gem material, so the bar reads as "gems collected".
const XP_COLOR := Color(0.35, 0.95, 0.6)
## Matches the Rotking's amber core seams.
const BOSS_BAR_COLOR := Color(0.98, 0.62, 0.16)

## Kill-streak feedback: kills landing within this rolling window count
## toward the tier thresholds below; 2s+ without a kill resets the streak
## so the tiers can fire again.
const STREAK_WINDOW := 2.0
const STREAK_KILLS: Array[int] = [8, 15, 25]
const STREAK_WORDS: Array[String] = ["SHREDDING!", "RAMPAGING!", "UNSTOPPABLE!"]

## Env var that force-enables the perf probe (headless perf verification).
const PERF_PROBE_ENV := "BONK_PERF"
const PERF_PROBE_REFRESH := 0.25

## Debug-only counter overlay (hidden by default, NOT a user-facing
## feature): live FPS plus active enemy/gem/projectile counts and per-pool
## created/parked sizes, for perf verification. Ships disabled; flip this
## in the editor or launch with BONK_PERF=1.
@export var show_perf_probe: bool = false

## Below this HP ratio the HP bar gains a gentle alpha/scale pulse (on top
## of the existing color ramp) nudging the player toward health orbs;
## healing back above it stops the pulse and restores the bar.
@export var low_hp_pulse_ratio: float = 0.35
## One full pulse cycle (fade down + back) takes twice this many seconds.
@export var low_hp_pulse_half_period: float = 0.45

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _level_label: Label = %LevelLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _kills_label: Label = %KillsLabel
@onready var _boss_bar: ProgressBar = %BossBar
@onready var _boss_name_label: Label = %BossNameLabel
@onready var _announce_label: Label = %AnnounceLabel
@onready var _curse_label: Label = %CurseLabel
@onready var _tier_label: Label = %TierLabel
@onready var _streak_label: Label = %StreakLabel

var _hp_fill: StyleBoxFlat
var _health: Health
var _hp_pulse_tween: Tween = null
var _hp_pulsing: bool = false
var _tracked_boss: Node3D = null
var _boss_health: Health = null
var _announce_tween: Tween
var _streak_tween: Tween
## Run-time stamps of recent kills (pruned to STREAK_WINDOW on each kill).
var _streak_kill_times: Array[float] = []
## Highest STREAK_KILLS index fired this streak; -1 until one fires.
var _streak_tier: int = -1
var _last_kills: int = 0
var _probe_label: Label = null
var _probe_refresh_left: float = 0.0


func _ready() -> void:
	# Bosses and the spawner reach this layer through "boss_ui"; shrines
	# use the plain "hud" group (announce, curse readout). Never node paths.
	add_to_group("boss_ui")
	add_to_group("hud")
	_apply_styles()
	RunState.xp_changed.connect(_on_xp_changed)
	RunState.leveled_up.connect(_on_leveled_up)
	RunState.kills_changed.connect(_on_kills_changed)
	RunState.curse_changed.connect(_on_curse_changed)
	_on_xp_changed(RunState.xp, RunState.xp_to_next)
	_on_leveled_up(RunState.level)
	_on_kills_changed(RunState.kills)
	_on_curse_changed(RunState.curse_stacks)
	var player := get_tree().get_first_node_in_group("player")
	_health = Health.find_in(player) if player != null else null
	if _health != null:
		_health.damaged.connect(_on_health_damaged)
		_health.hp_changed.connect(_refresh_hp)
		_health.died.connect(_on_health_died)
		_refresh_hp(_health.current_hp, _health.max_hp)
	if show_perf_probe or OS.get_environment(PERF_PROBE_ENV) == "1":
		_build_perf_probe()


func _process(delta: float) -> void:
	var total := int(RunState.run_time)
	_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	if _probe_label != null:
		_probe_refresh_left -= delta
		if _probe_refresh_left <= 0.0:
			_probe_refresh_left = PERF_PROBE_REFRESH
			_probe_label.text = _probe_text()


func _on_health_damaged(_amount: float, current: float) -> void:
	_refresh_hp(current, _health.max_hp)
	Juice.player_hurt()


func _on_health_died() -> void:
	_refresh_hp(0.0, _health.max_hp)


func _refresh_hp(current: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	# ceili, so a last sliver of HP reads "1", not a premature "0".
	_hp_label.text = "%d / %d" % [ceili(current), roundi(max_hp)]
	var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	_hp_fill.bg_color = HP_LOW_COLOR.lerp(HP_FULL_COLOR, clampf(ratio / LOW_HP_RATIO, 0.0, 1.0))
	_update_low_hp_pulse(current > 0.0 and ratio < low_hp_pulse_ratio)


## Starts/stops the low-HP bar pulse; idempotent per state so damage spam
## never restarts the loop mid-cycle. Zero HP (death) also stops it — the
## run-end screen owns that moment.
func _update_low_hp_pulse(should_pulse: bool) -> void:
	if should_pulse == _hp_pulsing:
		return
	_hp_pulsing = should_pulse
	if _hp_pulse_tween != null and _hp_pulse_tween.is_valid():
		_hp_pulse_tween.kill()
		_hp_pulse_tween = null
	_hp_bar.pivot_offset = _hp_bar.size * 0.5
	if not should_pulse:
		_hp_bar.modulate.a = 1.0
		_hp_bar.scale = Vector2.ONE
		return
	_hp_pulse_tween = create_tween().set_loops()
	_hp_pulse_tween.tween_property(_hp_bar, "modulate:a", 0.6, low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.parallel().tween_property(_hp_bar, "scale",
			Vector2(1.03, 1.08), low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.chain().tween_property(_hp_bar, "modulate:a", 1.0, low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hp_pulse_tween.parallel().tween_property(_hp_bar, "scale", Vector2.ONE,
			low_hp_pulse_half_period) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_xp_changed(current_xp: int, xp_to_next: int) -> void:
	_xp_bar.max_value = xp_to_next
	_xp_bar.value = current_xp


func _on_leveled_up(new_level: int) -> void:
	_level_label.text = "Lv %d" % new_level


func _on_kills_changed(kills: int) -> void:
	_kills_label.text = "Kills: %d" % kills
	if kills <= _last_kills:
		# Counter reset (new run), not a fresh kill: clear the streak.
		_last_kills = kills
		_streak_kill_times.clear()
		_streak_tier = -1
		return
	_last_kills = kills
	_register_streak_kill()


func _register_streak_kill() -> void:
	var now: float = RunState.run_time
	while not _streak_kill_times.is_empty() and now - _streak_kill_times[0] > STREAK_WINDOW:
		_streak_kill_times.pop_front()
	if _streak_kill_times.is_empty():
		_streak_tier = -1  # streak lapsed: every tier may fire again
	_streak_kill_times.append(now)
	var in_window := _streak_kill_times.size()
	var tier := -1
	for i in STREAK_KILLS.size():
		if in_window >= STREAK_KILLS[i]:
			tier = i
	if tier > _streak_tier:
		_streak_tier = tier
		_pop_streak(STREAK_WORDS[tier])


## Punchy scale-pop text (settles from oversized, holds, fades out).
func _pop_streak(word: String) -> void:
	Sfx.play(&"streak")
	_streak_label.text = word
	_streak_label.reset_size()
	_streak_label.pivot_offset = _streak_label.size * 0.5
	_streak_label.visible = true
	_streak_label.modulate.a = 1.0
	_streak_label.scale = Vector2(2.1, 2.1)
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	_streak_tween = create_tween()
	_streak_tween.tween_property(_streak_label, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.tween_interval(0.55)
	_streak_tween.tween_property(_streak_label, "modulate:a", 0.0, 0.3)
	_streak_tween.tween_callback(_streak_label.hide)


## Subtle Curse Shrine readout beside the run timer; hidden at 0 stacks
## (each boss spawn consumes the stacks, which re-hides it).
func _on_curse_changed(stacks: int) -> void:
	_curse_label.visible = stacks > 0
	_curse_label.text = "Cursed x%d" % stacks


## Debug-only perf counters, top-right, built in code so the shipping
## scene carries nothing (see show_perf_probe).
func _build_perf_probe() -> void:
	_probe_label = Label.new()
	_probe_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_probe_label.offset_left = -560.0
	_probe_label.offset_right = -12.0
	_probe_label.offset_top = 46.0
	_probe_label.offset_bottom = 120.0
	_probe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_probe_label.add_theme_font_size_override("font_size", 12)
	_probe_label.modulate = Color(1.0, 1.0, 1.0, 0.85)
	add_child(_probe_label)


func _probe_text() -> String:
	var tree := get_tree()
	return "FPS %d | enemies %d | gems %d | shots %d | bolts %d\npools (created/parked): %s" % [
			Engine.get_frames_per_second(),
			tree.get_node_count_in_group(&"enemies"),
			tree.get_node_count_in_group(&"xp_gems"),
			tree.get_node_count_in_group(&"player_shots"),
			tree.get_node_count_in_group(&"enemy_bolts"),
			Pools.stats_line()]


## Map-tier tag on the timer's other flank, pushed through the "hud" group
## by RunSystems once it settles the run's tier; hidden on the baseline.
func show_tier_tag(tier: int) -> void:
	_tier_label.visible = tier > 1
	_tier_label.text = "T%d" % tier


## Called through the "boss_ui" group by a boss entering the arena. If one
## is already tracked, the bar re-targets to the newest boss (bosses are
## sequential by design; two alive shows the latest).
func track_boss(boss: Node3D, title: String) -> void:
	_untrack_boss()
	var boss_health := Health.find_in(boss)
	if boss_health == null:
		return
	_tracked_boss = boss
	_boss_health = boss_health
	boss_health.damaged.connect(_on_boss_damaged)
	boss_health.hp_changed.connect(_on_boss_hp_changed)
	boss_health.died.connect(_on_boss_health_died)
	boss.tree_exited.connect(_on_boss_gone)
	_boss_name_label.text = title
	_boss_bar.visible = true
	_on_boss_hp_changed(boss_health.current_hp, boss_health.max_hp)


## Called through the "boss_ui" group (boss arrival warnings): a brief
## centered banner that fades itself out.
func announce(message: String) -> void:
	_announce_label.text = message
	_announce_label.visible = true
	_announce_label.modulate.a = 0.0
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_label, "modulate:a", 1.0, 0.3)
	_announce_tween.tween_interval(2.4)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, 0.6)
	_announce_tween.tween_callback(_announce_label.hide)


func _on_boss_damaged(_amount: float, current: float) -> void:
	_boss_bar.value = current


func _on_boss_hp_changed(current: float, max_hp: float) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = current


func _on_boss_health_died() -> void:
	_boss_bar.visible = false


## Fallback for a boss leaving the tree without dying (scene teardown).
func _on_boss_gone() -> void:
	_untrack_boss()
	_boss_bar.visible = false


func _untrack_boss() -> void:
	if _boss_health != null and is_instance_valid(_boss_health):
		_boss_health.damaged.disconnect(_on_boss_damaged)
		_boss_health.hp_changed.disconnect(_on_boss_hp_changed)
		_boss_health.died.disconnect(_on_boss_health_died)
	if _tracked_boss != null and is_instance_valid(_tracked_boss):
		_tracked_boss.tree_exited.disconnect(_on_boss_gone)
	_boss_health = null
	_tracked_boss = null


## Placeholder look built in code (no assets): dark translucent flat boxes,
## rounded HP bar, edge-to-edge XP strip, padded pill panels on the labels.
func _apply_styles() -> void:
	var hp_bg := _flat_box(BAR_BG_COLOR, 7)
	hp_bg.set_border_width_all(2)
	hp_bg.border_color = Color(0.0, 0.0, 0.0, 0.55)
	hp_bg.set_content_margin_all(3)
	_hp_fill = _flat_box(HP_FULL_COLOR, 5)
	_hp_bar.add_theme_stylebox_override("background", hp_bg)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)

	_xp_bar.add_theme_stylebox_override("background", _flat_box(BAR_BG_COLOR, 0))
	_xp_bar.add_theme_stylebox_override("fill", _flat_box(XP_COLOR, 0))

	var boss_bg := _flat_box(BAR_BG_COLOR, 6)
	boss_bg.set_border_width_all(2)
	boss_bg.border_color = Color(0.0, 0.0, 0.0, 0.55)
	boss_bg.set_content_margin_all(3)
	_boss_bar.add_theme_stylebox_override("background", boss_bg)
	_boss_bar.add_theme_stylebox_override("fill", _flat_box(BOSS_BAR_COLOR, 4))

	for label: Label in [_level_label, _timer_label, _kills_label]:
		var panel := _flat_box(PANEL_COLOR, 6)
		panel.content_margin_left = 10.0
		panel.content_margin_right = 10.0
		panel.content_margin_top = 3.0
		panel.content_margin_bottom = 3.0
		label.add_theme_stylebox_override("normal", panel)


static func _flat_box(color: Color, corner_radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(corner_radius)
	return box
