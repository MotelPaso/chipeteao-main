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

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _level_label: Label = %LevelLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _kills_label: Label = %KillsLabel
@onready var _boss_bar: ProgressBar = %BossBar
@onready var _boss_name_label: Label = %BossNameLabel
@onready var _announce_label: Label = %AnnounceLabel

var _hp_fill: StyleBoxFlat
var _health: Health
var _tracked_boss: Node3D = null
var _boss_health: Health = null
var _announce_tween: Tween


func _ready() -> void:
	# Bosses and the spawner reach this layer through the group, never by
	# node path.
	add_to_group("boss_ui")
	_apply_styles()
	RunState.xp_changed.connect(_on_xp_changed)
	RunState.leveled_up.connect(_on_leveled_up)
	RunState.kills_changed.connect(_on_kills_changed)
	_on_xp_changed(RunState.xp, RunState.xp_to_next)
	_on_leveled_up(RunState.level)
	_on_kills_changed(RunState.kills)
	var player := get_tree().get_first_node_in_group("player")
	_health = Health.find_in(player) if player != null else null
	if _health != null:
		_health.damaged.connect(_on_health_damaged)
		_health.hp_changed.connect(_refresh_hp)
		_health.died.connect(_on_health_died)
		_refresh_hp(_health.current_hp, _health.max_hp)


func _process(_delta: float) -> void:
	var total := int(RunState.run_time)
	_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]


func _on_health_damaged(_amount: float, current: float) -> void:
	_refresh_hp(current, _health.max_hp)


func _on_health_died() -> void:
	_refresh_hp(0.0, _health.max_hp)


func _refresh_hp(current: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	# ceili, so a last sliver of HP reads "1", not a premature "0".
	_hp_label.text = "%d / %d" % [ceili(current), roundi(max_hp)]
	var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	_hp_fill.bg_color = HP_LOW_COLOR.lerp(HP_FULL_COLOR, clampf(ratio / LOW_HP_RATIO, 0.0, 1.0))


func _on_xp_changed(current_xp: int, xp_to_next: int) -> void:
	_xp_bar.max_value = xp_to_next
	_xp_bar.value = current_xp


func _on_leveled_up(new_level: int) -> void:
	_level_label.text = "Lv %d" % new_level


func _on_kills_changed(kills: int) -> void:
	_kills_label.text = "Kills: %d" % kills


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
