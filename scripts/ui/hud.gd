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

const HP_FULL_COLOR := Color(0.36, 0.8, 0.42)
const HP_LOW_COLOR := Color(0.9, 0.22, 0.2)
## Matches the XP gem material, so the bar reads as "gems collected".
const XP_COLOR := Color(0.35, 0.95, 0.6)
## Matches the Rotking's amber core seams.
const BOSS_BAR_COLOR := Color(0.98, 0.62, 0.16)
## Bar value changes ease toward their target instead of snapping.
const BAR_TWEEN_TIME := 0.15

## Kill-streak feedback: kills landing within this rolling window count
## toward the tier thresholds below; 2s+ without a kill resets the streak
## so the tiers can fire again.
const STREAK_WINDOW := 2.0
const STREAK_KILLS: Array[int] = [8, 15, 25]
const STREAK_WORDS: Array[String] = ["¡TRITURANDO!", "¡ARRASANDO!", "¡IMPARABLE!"]
## Streak popup color per tier: gold → hot orange → furnace red.
const STREAK_COLORS: Array[Color] = [
	Color(1.0, 0.86, 0.25), Color(1.0, 0.62, 0.16), Color(1.0, 0.34, 0.2)]

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
@onready var _points_label: Label = %PointsLabel
@onready var _boss_bar: ProgressBar = %BossBar
@onready var _boss_name_label: Label = %BossNameLabel
@onready var _announce_label: Label = %AnnounceLabel
@onready var _curse_label: Label = %CurseLabel
@onready var _tier_label: Label = %TierLabel
@onready var _streak_label: Label = %StreakLabel

var _hp_fill: StyleBoxFlat
var _health: Health
var _hp_value_tween: Tween = null
var _xp_value_tween: Tween = null
var _boss_value_tween: Tween = null
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
## Last whole second painted on the timer: the text only changes once a
## second, so re-formatting (and re-shaping the spaced font) every frame
## is 100+ wasted relayouts per second.
var _shown_second: int = -1

## Loadout strip (iteration 40): bottom-left row of slots for player 1's
## weapons (with level), tomes (with stacks) and items (with copies).
## Rebuilt only when its signature string changes, polled twice a second.
const LOADOUT_REFRESH := 0.5
const LOADOUT_WEAPON_COLOR := Color(0.3, 0.82, 0.76)
const LOADOUT_TOME_COLOR := Color(0.72, 0.5, 0.95)
const LOADOUT_SLOT_SIZE := Vector2(44.0, 44.0)
const LOADOUT_GLYPH_FONT_SIZE := 16
const LOADOUT_CORNER_FONT_SIZE := 10
## Blank spacer between the weapon / tome / item groups of the strip.
const LOADOUT_GROUP_GAP := 8.0
## Teammate readout column (co-op only): bar size and its top-left corner.
const MATE_BAR_SIZE := Vector2(150.0, 16.0)
const MATE_BOX_OFFSET := Vector2(16.0, 96.0)
const MATE_FONT_SIZE := 13
## Tome display names carry their kind as a prefix ("Tomo de Furia"); the
## glyph is derived from what is left. Longest-first, so "Tomo del Azar"
## loses the whole "Tomo del " and not just "Tomo de " (which would leave
## "l Azar"). The English prefix stays for untranslated rows.
const TOME_NAME_PREFIXES: Array[String] = ["Tome of ", "Tomo del ", "Tomo de "]
var _loadout_box: HBoxContainer = null
var _loadout_player: Node = null
var _loadout_signature: String = ""
var _loadout_refresh_left: float = 0.0


func _ready() -> void:
	# Bosses and the spawner reach this layer through "boss_ui"; shrines
	# use the plain "hud" group (announce, curse readout). Never node paths.
	add_to_group("boss_ui")
	add_to_group("hud")
	_apply_styles()
	RunState.xp_changed.connect(_on_xp_changed)
	RunState.leveled_up.connect(_on_leveled_up)
	RunState.kills_changed.connect(_on_kills_changed)
	RunState.difficulty_changed.connect(_on_difficulty_changed)
	_on_xp_changed(RunState.xp, RunState.xp_to_next)
	_on_leveled_up(RunState.level)
	_on_kills_changed(RunState.kills)
	_on_difficulty_changed(RunState.difficulty_bonus)
	# Deferred: in co-op the extra party members spawn in RunSystems._ready,
	# which runs after this child's ready; one deferred hop sees them all.
	_bind_party.call_deferred()
	if show_perf_probe or OS.get_environment(PERF_PROBE_ENV) == "1":
		_build_perf_probe()


## Binds the main HP bar to player 1 and, in co-op, builds one compact
## teammate bar per extra raider (tag + themed bar + points chip; K.O.
## state while downed).
func _bind_party() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	players.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get("player_index")) < int(b.get("player_index")))
	for node: Node in players:
		var health := Health.find_in(node)
		if health == null:
			continue
		if _health == null and int(node.get("player_index")) == 0:
			_health = health
			_health.damaged.connect(_on_health_damaged)
			_health.hp_changed.connect(_refresh_hp)
			_health.died.connect(_on_health_died)
			_refresh_hp(_health.current_hp, _health.max_hp)
			_loadout_player = node
			if node.has_signal("points_changed"):
				node.connect("points_changed", _on_points_changed)
				_on_points_changed(int(node.get("points")))
			_refresh_loadout()
		elif Coop.is_coop():
			_build_mate_bar(int(node.get("player_index")), health, node)


## Teammate readout column (built only in co-op): "J2" tag + slim HP bar
## + points chip per extra player, top-left under the main cluster.
var _mate_box: VBoxContainer = null


func _build_mate_bar(slot: int, health: Health, body: Node) -> void:
	if _mate_box == null:
		_mate_box = VBoxContainer.new()
		_mate_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_mate_box.offset_left = MATE_BOX_OFFSET.x
		_mate_box.offset_top = MATE_BOX_OFFSET.y
		_mate_box.add_theme_constant_override("separation", 6)
		# Direct CanvasLayer child: anchors resolve against the viewport.
		add_child(_mate_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag := Label.new()
	tag.text = "J%d" % (slot + 1)
	UiTheme.style_badge(tag, UiTheme.TEXT_BRIGHT)
	row.add_child(tag)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = MATE_BAR_SIZE
	bar.show_percentage = false
	bar.max_value = health.max_hp
	bar.value = health.current_hp
	var fill := UiTheme.style_bar(bar, HP_FULL_COLOR, 6)
	row.add_child(bar)
	# Points are a PER-RAIDER wallet (chests, spring, roulette all charge
	# the one who interacts), so every slot needs its own readout — the
	# amber chip on the right belongs to player 1 alone.
	_add_mate_points_chip(row, body)
	_mate_box.add_child(row)
	var refresh := func(current: float, max_hp: float) -> void:
		bar.max_value = max_hp
		bar.value = current
		var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
		UiTheme.recolor_fill(fill,
				HP_LOW_COLOR.lerp(HP_FULL_COLOR, clampf(ratio / LOW_HP_RATIO, 0.0, 1.0)))
		tag.text = "J%d" % (slot + 1) if current > 0.0 else "J%d K.O." % (slot + 1)
		tag.modulate = Color.WHITE if current > 0.0 else Color(1.0, 0.45, 0.4)
	health.hp_changed.connect(refresh)
	health.damaged.connect(func(_amount: float, current: float) -> void:
		refresh.call(current, health.max_hp)
		# NOT Juice.player_hurt(): the vignette and the shake cover the
		# whole window, so a teammate tanking a boss on the far side of
		# the map used to strobe everybody's half of the split screen.
		# A mate getting hit is THEIR readout popping, not your screen.
		UiTheme.pop(tag, 1.18, 0.18))
	health.died.connect(func() -> void: refresh.call(0.0, health.max_hp))


## Per-slot points chip on a teammate row (hidden for bodies without the
## wallet, e.g. a stand-in in a test scene).
func _add_mate_points_chip(row: HBoxContainer, body: Node) -> void:
	if not body.has_signal("points_changed"):
		return
	var points := Label.new()
	points.add_theme_font_size_override("font_size", MATE_FONT_SIZE)
	UiTheme.style_badge(points, UiTheme.ACCENT_AMBER)
	points.text = "%d pts" % int(body.get("points"))
	row.add_child(points)
	body.connect("points_changed", func(total: int) -> void:
		points.text = "%d pts" % total
		UiTheme.pop(points, 1.15, 0.18))


func _process(delta: float) -> void:
	var total := int(RunState.run_time)
	if total != _shown_second:
		_shown_second = total
		_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	if _probe_label != null:
		_probe_refresh_left -= delta
		if _probe_refresh_left <= 0.0:
			_probe_refresh_left = PERF_PROBE_REFRESH
			_probe_label.text = _probe_text()
	_loadout_refresh_left -= delta
	if _loadout_refresh_left <= 0.0:
		_loadout_refresh_left = LOADOUT_REFRESH
		_refresh_loadout()


func _on_points_changed(total: int) -> void:
	_points_label.text = "%d pts" % total
	UiTheme.pop(_points_label, 1.15, 0.18)


## --- loadout strip ----------------------------------------------------------

## Rebuilds the strip when the loadout changed: weapons (level, ★ when
## evolved), tomes (stack numeral) and items (copies). Placeholder look
## until real sprites land: a rarity/kind-colored tile with the 2-letter
## glyph its catalog row declares; rows with an `icon` texture path show it
## instead.
func _refresh_loadout() -> void:
	if _loadout_player == null or not is_instance_valid(_loadout_player):
		return
	var entries: Array[Dictionary] = []
	var mount := _loadout_player.get_node_or_null("Weapons")
	if mount != null:
		for child: Node in mount.get_children():
			var weapon := child as WeaponBase
			if weapon == null:
				continue
			# Name and glyph both come from the catalogs: the evolution
			# recipe once the weapon evolved, the weapon library before.
			var row := EvolutionCatalog.by_weapon_node(weapon.name) if weapon.evolved \
					else UpgradePool.weapon_by_node(weapon.name)
			var title := weapon.evolved_name if weapon.evolved \
					else UpgradePool.weapon_display_name(weapon.name)
			entries.append({
				"glyph": _catalog_glyph(row, title),
				"color": UiTheme.ACCENT_AMBER if weapon.evolved else LOADOUT_WEAPON_COLOR,
				# Same scale EvolutionCatalog.EVOLVE_AT_LEVEL and the
				# Collection screen quote, so "sube el arma al nivel 6"
				# means the number on this corner reaching 6.
				"corner": ("★%d" if weapon.evolved else UiTheme.WEAPON_LEVEL_ABBREV) % weapon.upgrade_level,
				"tip": title, "icon": "",
			})
	var stats := PlayerStats.find_in(_loadout_player)
	if stats != null:
		for tome_id: String in stats.carried_tome_ids():
			var tome := Tome.by_id(tome_id)
			var title := String(tome.get("display_name", tome_id))
			entries.append({
				"glyph": _catalog_glyph(tome, _tome_short_name(title)),
				"color": LOADOUT_TOME_COLOR,
				"corner": Tome.STACK_NUMERALS[clampi(stats.stack_count(tome_id), 1, Tome.MAX_STACKS) - 1],
				"tip": title, "icon": "",
			})
	var bag := ItemBag.find_in(_loadout_player)
	if bag != null:
		for item_id: String in bag.carried_ids():
			var row := ItemCatalog.by_id(item_id)
			var copies := bag.count(item_id)
			entries.append({
				"glyph": _catalog_glyph(row, item_id),
				"color": ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
				"corner": "x%d" % copies if copies > 1 else "",
				"tip": String(row.get("display_name", item_id)), "icon": String(row.get("icon", "")),
			})
	var signature := ""
	for entry: Dictionary in entries:
		signature += "%s|%s|%s;" % [entry.tip, entry.corner, entry.icon]
	if signature == _loadout_signature:
		return
	_loadout_signature = signature
	_rebuild_loadout(entries)


## Glyph for one slot: the catalog row's own two-letter `glyph` when it
## declares one, else the derived fallback. Every shipped weapon, evolution,
## tome and item row declares one — deriving initials from the Spanish names
## collapsed whole families onto the same two letters ("Vial de sangre" and
## "Vara de brasas" both gave "VD"), which is exactly what this strip exists
## to tell apart.
func _catalog_glyph(row: Dictionary, fallback_title: String) -> String:
	var glyph := String(row.get("glyph", ""))
	return glyph if not glyph.is_empty() else _glyph_for(fallback_title)


## The distinguishing half of a tome name ("Tomo de Furia" -> "Furia"),
## feeding the _glyph_for fallback: every row shares the kind prefix, so
## keeping it would collapse all fifteen fallback glyphs into the same two
## letters. Prefixes are tried longest-first (see TOME_NAME_PREFIXES) and
## only one is ever stripped.
func _tome_short_name(display_name: String) -> String:
	for prefix: String in TOME_NAME_PREFIXES:
		if display_name.begins_with(prefix):
			return display_name.substr(prefix.length())
	return display_name


## FALLBACK only (see _catalog_glyph): initials of a multi-word name, else
## its first two letters. Kept for a catalog row that forgets to declare a
## glyph — never trustworthy enough to be the primary source, since Spanish
## names share their second word ("... de ...") far too often.
func _glyph_for(title: String) -> String:
	var words := title.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return title.substr(0, 2).to_upper()


func _rebuild_loadout(entries: Array[Dictionary]) -> void:
	if _loadout_box == null:
		_loadout_box = HBoxContainer.new()
		_loadout_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_loadout_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_loadout_box.offset_left = 16.0
		_loadout_box.offset_bottom = -20.0
		_loadout_box.offset_top = -68.0
		_loadout_box.add_theme_constant_override("separation", 6)
		# PASS, not IGNORE: the slots need to be hit-testable for their
		# tooltips, and PASS still lets the click through to the 3D world.
		_loadout_box.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_loadout_box)
	for child: Node in _loadout_box.get_children():
		# Out of the container FIRST: queue_free() only lands at the end of
		# the frame, so the old slots would lay out beside the new ones for
		# one frame and make the strip jump every time the loadout changes.
		_loadout_box.remove_child(child)
		child.queue_free()
	var last_color := Color.TRANSPARENT
	for entry: Dictionary in entries:
		# A thin gap between the weapon / tome / item groups.
		var color: Color = entry.color
		if last_color != Color.TRANSPARENT and not color.is_equal_approx(last_color) \
				and (color.is_equal_approx(LOADOUT_TOME_COLOR) or last_color.is_equal_approx(LOADOUT_TOME_COLOR)
				or last_color.is_equal_approx(LOADOUT_WEAPON_COLOR) or last_color.is_equal_approx(UiTheme.ACCENT_AMBER)):
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(LOADOUT_GROUP_GAP, 0.0)
			_loadout_box.add_child(spacer)
		last_color = color
		_loadout_box.add_child(_make_loadout_slot(entry))


func _make_loadout_slot(entry: Dictionary) -> Control:
	var color: Color = entry.color
	var slot := PanelContainer.new()
	slot.custom_minimum_size = LOADOUT_SLOT_SIZE
	slot.tooltip_text = String(entry.tip)
	# PASS so hovering the tile can raise its tooltip (the name behind the
	# two-letter glyph); IGNORE keeps it out of the hit-test entirely and
	# the tooltip never fires.
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := UiTheme.flat(Color(0.07, 0.075, 0.11, 0.9), UiTheme.RADIUS_SMALL)
	style.border_color = color
	style.set_border_width_all(2)
	UiTheme.add_glow(style, color, 6, 0.25)
	slot.add_theme_stylebox_override("panel", style)
	# PanelContainer is a Container: it re-fits every DIRECT child to its
	# full rect on each layout pass, wiping anchors and offsets. One plain
	# Control absorbs that fit; anchors work normally inside it, which is
	# what puts the corner tag in the corner instead of over the glyph.
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(inner)
	var icon_path := String(entry.icon)
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var texture := TextureRect.new()
		texture.texture = load(icon_path)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.add_child(texture)
	else:
		var glyph := Label.new()
		glyph.text = String(entry.glyph)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", LOADOUT_GLYPH_FONT_SIZE)
		glyph.add_theme_color_override("font_color", color.lightened(0.25))
		glyph.add_theme_font_override("font", UiTheme.spaced_font(1))
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.add_child(glyph)
	var corner_text := String(entry.corner)
	if not corner_text.is_empty():
		var corner := Label.new()
		corner.text = corner_text
		corner.add_theme_font_size_override("font_size", LOADOUT_CORNER_FONT_SIZE)
		corner.add_theme_color_override("font_color", UiTheme.TEXT_BRIGHT)
		corner.add_theme_color_override("font_outline_color", UiTheme.OUTLINE_DARK)
		corner.add_theme_constant_override("outline_size", 4)
		corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		corner.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# MINSIZE preset: pinned to the bottom-right corner at its own text
		# size, 3 px in from the border.
		corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
				Control.PRESET_MODE_MINSIZE, 3)
		inner.add_child(corner)
	return slot


func _on_health_damaged(_amount: float, current: float) -> void:
	_refresh_hp(current, _health.max_hp)
	Juice.player_hurt()


func _on_health_died() -> void:
	_refresh_hp(0.0, _health.max_hp)


func _refresh_hp(current: float, max_hp: float) -> void:
	# Snap when the scale itself changes (new run / max-HP growth) so the
	# bar never animates across two different scales; otherwise ease.
	if not is_equal_approx(_hp_bar.max_value, max_hp):
		_hp_bar.max_value = max_hp
		_hp_bar.value = current
	else:
		_hp_value_tween = _tween_bar_value(_hp_bar, current, _hp_value_tween)
	# ceili, so a last sliver of HP reads "1", not a premature "0".
	_hp_label.text = "%d / %d" % [ceili(current), roundi(max_hp)]
	var ratio := clampf(current / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	UiTheme.recolor_fill(_hp_fill,
			HP_LOW_COLOR.lerp(HP_FULL_COLOR, clampf(ratio / LOW_HP_RATIO, 0.0, 1.0)))
	_update_low_hp_pulse(current > 0.0 and ratio < low_hp_pulse_ratio)


## Shared ~0.15s ease toward a bar's new value (kills the previous ease
## first, so damage spam converges instead of stacking).
func _tween_bar_value(bar: ProgressBar, target: float, previous: Tween) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	tween.tween_property(bar, "value", target, BAR_TWEEN_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween


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
	# A new threshold means a level rolled over: snap to the fresh scale.
	if not is_equal_approx(_xp_bar.max_value, float(xp_to_next)):
		_xp_bar.max_value = xp_to_next
		_xp_bar.value = current_xp
	else:
		_xp_value_tween = _tween_bar_value(_xp_bar, float(current_xp), _xp_value_tween)


func _on_leveled_up(new_level: int) -> void:
	_level_label.text = UiTheme.LEVEL_ABBREV % new_level
	UiTheme.pop(_level_label, 1.3, 0.3)


func _on_kills_changed(kills: int) -> void:
	_kills_label.text = "Bajas: %d" % kills
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
		_pop_streak(STREAK_WORDS[tier], tier)


## Punchy scale-pop text (slams in oversized with a tilt, settles, holds,
## fades). Color escalates per tier so bigger streaks read hotter.
func _pop_streak(word: String, tier: int) -> void:
	Sfx.play(&"streak")
	_streak_label.text = word
	_streak_label.add_theme_color_override("font_color", STREAK_COLORS[tier])
	_streak_label.reset_size()
	_streak_label.pivot_offset = _streak_label.size * 0.5
	_streak_label.visible = true
	_streak_label.modulate.a = 1.0
	_streak_label.scale = Vector2(2.3, 2.3)
	_streak_label.rotation_degrees = -5.0
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	_streak_tween = create_tween()
	_streak_tween.tween_property(_streak_label, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.parallel().tween_property(_streak_label, "rotation_degrees", 0.0, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.tween_interval(0.55)
	_streak_tween.tween_property(_streak_label, "modulate:a", 0.0, 0.3)
	_streak_tween.tween_callback(_streak_label.hide)


## Run-wide difficulty readout beside the run timer (demonic altars, Tome
## of Peril, roulette); hidden while it is zero.
func _on_difficulty_changed(bonus: float) -> void:
	_curse_label.visible = bonus > 0.001
	_curse_label.text = "Dificultad +%d%%" % roundi(bonus * 100.0)


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
## "G" for Grado — the same badge the select screen shows on a map card.
func show_tier_tag(tier: int) -> void:
	_tier_label.visible = tier > 1
	_tier_label.text = "G%d" % tier


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
	_reset_announce_style()
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


## Bigger sibling of announce() for payoff moments (weapon evolutions):
## gold, scaled up with a pop, and held on screen longer.
func announce_major(message: String) -> void:
	_reset_announce_style()
	_announce_label.text = message
	_announce_label.add_theme_color_override("font_color", UiTheme.ACCENT_AMBER)
	_announce_label.visible = true
	_announce_label.modulate.a = 0.0
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_label, "modulate:a", 1.0, 0.15)
	_announce_tween.tween_interval(3.2)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, 0.6)
	_announce_tween.tween_callback(func() -> void:
		_announce_label.hide()
		# Restore the standard banner color for the next plain announce.
		_reset_announce_style())
	UiTheme.pop(_announce_label, 1.35, 0.4)


## Wipes whatever the previous banner left behind (announce_major's amber
## override, a pop mid-flight). Every banner starts from the scene's own
## look: without this, an announce() landing inside announce_major's ~4 s
## window kills the tween that was going to clean up, and EVERY later
## banner in the run stays amber and slightly oversized.
func _reset_announce_style() -> void:
	UiTheme.kill_meta_tween(_announce_label, &"ui_pop_tween")
	_announce_label.remove_theme_color_override("font_color")
	_announce_label.scale = Vector2.ONE


func _on_boss_damaged(_amount: float, current: float) -> void:
	_boss_value_tween = _tween_bar_value(_boss_bar, current, _boss_value_tween)


func _on_boss_hp_changed(current: float, max_hp: float) -> void:
	if not is_equal_approx(_boss_bar.max_value, max_hp):
		_boss_bar.max_value = max_hp
		_boss_bar.value = current
	else:
		_boss_value_tween = _tween_bar_value(_boss_bar, current, _boss_value_tween)


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


## UiTheme design system (iteration 29): layered rounded bars (trough /
## fill / gloss line / leading-edge tick), badge pills for level and
## kills, spaced timer numerals, and an amber boss bar with quarter
## segment ticks under a spaced name plate. Contrast over 3D chaos first:
## everything keeps a dark trough and an outline.
func _apply_styles() -> void:
	_hp_fill = UiTheme.style_bar(_hp_bar, HP_FULL_COLOR, 8)

	# The XP strip stays edge-to-edge and square, but gains the gloss line
	# and a bright leading-edge tick so progress reads at a glance.
	var xp_bg := UiTheme.flat(Color(0.04, 0.045, 0.07, 0.85), 0)
	xp_bg.border_width_bottom = 1
	xp_bg.border_color = Color(0.0, 0.0, 0.0, 0.6)
	_xp_bar.add_theme_stylebox_override("background", xp_bg)
	_xp_bar.add_theme_stylebox_override("fill", UiTheme.bar_fill(XP_COLOR, 0))

	var boss_fill := UiTheme.style_bar(_boss_bar, BOSS_BAR_COLOR, 7)
	UiTheme.recolor_fill(boss_fill, BOSS_BAR_COLOR)
	var boss_bg := _boss_bar.get_theme_stylebox("background") as StyleBoxFlat
	boss_bg.border_color = Color(0.35, 0.22, 0.06, 0.9)
	UiTheme.add_glow(boss_bg, BOSS_BAR_COLOR, 6, 0.25)
	_build_boss_ticks()
	_boss_name_label.add_theme_font_override("font", UiTheme.spaced_font(3))

	UiTheme.style_badge(_level_label, UiTheme.TEXT_BRIGHT)
	UiTheme.style_badge(_kills_label, UiTheme.TEXT_BRIGHT)
	UiTheme.style_badge(_points_label, UiTheme.ACCENT_AMBER)
	UiTheme.style_badge(_timer_label, UiTheme.TEXT_BRIGHT)
	_timer_label.add_theme_font_override("font", UiTheme.spaced_font(4))
	_streak_label.add_theme_font_override("font", UiTheme.spaced_font(3))
	_announce_label.add_theme_font_override("font", UiTheme.spaced_font(3))


## Quarter-mark ticks over the boss bar: thin dark lines at 25/50/75% so
## phase thresholds read like a segmented health pool.
func _build_boss_ticks() -> void:
	for quarter in range(1, 4):
		var tick := ColorRect.new()
		tick.color = Color(0.0, 0.0, 0.0, 0.5)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.anchor_left = 0.25 * quarter
		tick.anchor_right = 0.25 * quarter
		tick.anchor_top = 0.0
		tick.anchor_bottom = 1.0
		tick.offset_left = -1.0
		tick.offset_right = 1.0
		tick.offset_top = 4.0
		tick.offset_bottom = -4.0
		_boss_bar.add_child(tick)
		_boss_bar.move_child(tick, 0)  # under the name label
