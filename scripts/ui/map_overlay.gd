class_name MapOverlay
extends Control
## The Tab map (iteration 52): a full-cell overlay showing the whole stage
## plus this raider's build, the party and what they are carrying.
##
## It does NOT pause. A bullet-heaven has no safe moment to read a menu in,
## so the horde keeps coming while the map is up — checking it is a choice
## with a cost, which is what makes it interesting. The overlay hides
## itself the moment the run is over, the tree is paused by something that
## DOES own the pause (the card picker, the pause menu), or this slot's
## raider is gone.
##
## One instance per player, built by the HUD on its own CanvasLayer (layer
## 8: above the HUD, below the card picker) and anchored to that player's
## split-screen cell — a single map in a window corner belongs to nobody.
##
## Focus: every Control here is FOCUS_NONE. Tab is Godot's built-in
## `ui_focus_next`, and one focusable Control anywhere in this tree would
## eat the key before the toggle ever sees it.

## Which raider this overlay belongs to. Set by the HUD.
@export var slot: int = 0

## Share of the cell the map takes; the panels take the rest.
const MAP_SHARE: float = 0.6
## Padding around everything.
const PAD: float = 18.0
## Gap between the map and the panel column.
const GUTTER: float = 14.0
## Seconds between refreshes while the overlay is open. Markers move and
## HP changes; a tenth of a second is invisible and costs nothing, and
## NOTHING is refreshed while the overlay is hidden.
const REFRESH: float = 0.1
## Legend swatch size.
const SWATCH := Vector2(12.0, 12.0)
const HEADER_FONT_SIZE: int = 20
const SECTION_FONT_SIZE: int = 15
const BODY_FONT_SIZE: int = 13

var _map: MapDraw = null
var _dim: ColorRect = null
var _header: Label = null
var _legend: VBoxContainer = null
var _stats_body: Label = null
var _players_body: Label = null
var _items_body: Label = null
var _refresh_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"map_overlay")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_map = MapDraw.new(get_tree())
	_map.build_background()
	_build_ui()


## Stage hook, relayed by the HUD from WorldDirector.on_stage_started.
func on_stage_started(arena: Node3D = null) -> void:
	if _map == null:
		_map = MapDraw.new(get_tree())
	_map.build_background(arena)
	_map.collect_markers()
	queue_redraw()


## Markers currently on this overlay's map (the soak reads it).
func marker_count() -> int:
	return _map.marker_count() if _map != null else 0


func _process(delta: float) -> void:
	# Hidden whenever something else owns the screen. Checked BEFORE the
	# toggle so a press landing on the same frame as a death cannot open a
	# map over the run-end screen.
	if not RunState.run_active or get_tree().paused or _raider() == null:
		if visible:
			visible = false
		return
	if Input.is_action_just_pressed(Coop.action(slot, &"map_overlay")):
		visible = not visible
		if visible and _map != null:
			# Refreshed HERE, not on the next tick: the map has to be
			# correct on the very frame it appears, and a tick of delay
			# would show the previous refresh's markers and stats.
			_refresh_left = REFRESH
			_map.collect_markers()
			_map.composite()
			_refresh_panels()
			queue_redraw()
	if not visible or _map == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH
	# Plain methods, no Control involved: a headless soak exercises the
	# whole map path whether or not _draw() is ever dispatched.
	_map.collect_markers()
	_map.composite()
	_refresh_panels()
	queue_redraw()


## --- layout ---------------------------------------------------------------

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(UiTheme.BG_DEEP, 0.88)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_own(_dim)
	add_child(_dim)
	_header = Label.new()
	_header.position = Vector2(PAD, PAD)
	UiTheme.style_title(_header, HEADER_FONT_SIZE, UiTheme.TEXT_BRIGHT, 3, 6)
	_own(_header)
	add_child(_header)
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 3)
	_own(_legend)
	add_child(_legend)
	_build_legend()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_own(column)
	add_child(column)
	_stats_body = _add_section(column, "Estadísticas")
	_players_body = _add_section(column, "Jugadores")
	_items_body = _add_section(column, "Objetos")
	_anchor_column(column)


## One titled panel with a multi-line body; returns the body label.
func _add_section(column: VBoxContainer, title: String) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiTheme.flat(UiTheme.PANEL_BG, UiTheme.RADIUS_SMALL))
	_own(panel)
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_own(box)
	panel.add_child(box)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	header.add_theme_font_override("font", UiTheme.spaced_font(2))
	header.add_theme_color_override("font_color", UiTheme.ACCENT)
	_own(header)
	box.add_child(header)
	var body := Label.new()
	body.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	body.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_own(body)
	box.add_child(body)
	return body


func _anchor_column(column: VBoxContainer) -> void:
	column.anchor_left = MAP_SHARE
	column.anchor_right = 1.0
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_left = GUTTER
	column.offset_top = PAD
	column.offset_right = -PAD
	column.offset_bottom = -PAD


## Legend rows straight off MapDraw.MARKER_LABELS, so a kind added there
## for part C shows up here with no edit.
func _build_legend() -> void:
	for kind: StringName in MapDraw.MARKER_LABELS:
		var style: Dictionary = MapDraw.MARKER_STYLES.get(kind, {})
		if style.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_own(row)
		_legend.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = style["color"]
		swatch.custom_minimum_size = SWATCH
		_own(swatch)
		row.add_child(swatch)
		var label := Label.new()
		label.text = MapDraw.MARKER_LABELS[kind]
		label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		label.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
		_own(label)
		row.add_child(label)


## Every Control this overlay builds: never focusable (Tab is
## ui_focus_next), never hit-testable (the world is still live behind it).
func _own(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


## --- content --------------------------------------------------------------

func _refresh_panels() -> void:
	var seconds := int(RunState.run_time)
	var title := "Etapa %d" % (RunState.stage_index + 1)
	if RunState.lap > 0:
		title += " · Vuelta %d" % (RunState.lap + 1)
	_header.text = "%s — %02d:%02d" % [title, seconds / 60, seconds % 60]
	_legend.position = Vector2(PAD, size.y - PAD - _legend.size.y)
	_stats_body.text = _stats_text()
	_players_body.text = _players_text()
	_items_body.text = _items_text()


## This slot's raider, standing or downed; null when the slot is empty.
func _raider() -> Node3D:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and int(body.get("player_index")) == slot:
				return body
	return null


## The derived stat layer, as the player reads it.
## `cooldown_multiplier` is shown as ATTACK SPEED and POSITIVE (GLOSARIO
## rule 7): 0.8 is "+20% de velocidad de ataque", never "-20% de
## enfriamiento". The multiplier itself is untouched, only the wording.
func _stats_text() -> String:
	var body := _raider()
	var stats := PlayerStats.find_in(body) if body != null else null
	if stats == null:
		return "—"
	var rows: PackedStringArray = PackedStringArray()
	rows.append("Daño  %s" % _percent(stats.damage_multiplier - 1.0))
	rows.append("Velocidad de ataque  %s" % _percent(1.0 / maxf(stats.cooldown_multiplier, 0.01) - 1.0))
	rows.append("Área  %s" % _percent(stats.area_multiplier - 1.0))
	rows.append("Velocidad  %s" % _percent(stats.move_speed_multiplier - 1.0))
	rows.append("Prob. de crítico  %s" % _percent(stats.crit_chance))
	rows.append("Daño crítico  %s" % _percent(stats.crit_damage - 1.0))
	rows.append("Robo de vida  %s" % _percent(stats.lifesteal))
	rows.append("Armadura  %s" % _flat(stats.armor))
	rows.append("Evasión  %s" % _percent(stats.evasion))
	rows.append("Espinas  %s" % _flat(stats.thorns))
	rows.append("Suerte  %s" % _flat(stats.luck))
	rows.append("HP máx.  %s" % _flat(stats.bonus_max_hp))
	rows.append("Proyectiles  %s" % _flat(float(stats.projectile_bonus)))
	rows.append("Duración  %s" % _percent(stats.duration_multiplier - 1.0))
	rows.append("XP  %s" % _percent(stats.xp_multiplier - 1.0))
	rows.append("Saltos  %s" % _flat(float(stats.extra_jumps)))
	return "\n".join(rows)


func _percent(fraction: float) -> String:
	return "%+d%%" % roundi(fraction * 100.0)


func _flat(amount: float) -> String:
	return "%+d" % roundi(amount)


## The whole party, downed raiders included: knowing a teammate is at 0 HP
## across the map is most of what this panel is for in co-op.
func _players_text() -> String:
	var rows: PackedStringArray = PackedStringArray()
	for player_slot: int in maxi(Coop.player_count, 1):
		var body := _raider_at(player_slot)
		var name_text := String(CharacterCatalog.by_id_or_default(
				Coop.character_for_slot(player_slot)).get("display_name", "—"))
		if body == null:
			rows.append("J%d  %s  —" % [player_slot + 1, name_text])
			continue
		var health := Health.find_in(body)
		var hp := "%d/%d" % [ceili(health.current_hp), roundi(health.max_hp)] \
				if health != null else "—"
		var points: Variant = body.get("points")
		rows.append("J%d  %s  %s  %s  %d pts" % [
				player_slot + 1, name_text, hp,
				UiTheme.LEVEL_ABBREV % RunState.level,
				int(points) if points != null else 0])
	return "\n".join(rows)


func _raider_at(player_slot: int) -> Node3D:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and int(body.get("player_index")) == player_slot:
				return body
	return null


## Items with copies, then weapons with their level or milestone tier,
## then tomes with their stack numeral — the same three families the HUD
## strip shows, spelled out with full names because there is room here.
func _items_text() -> String:
	var body := _raider()
	if body == null:
		return "—"
	var rows: PackedStringArray = PackedStringArray()
	var bag := ItemBag.find_in(body)
	if bag != null:
		for item_id: String in bag.carried_ids():
			var row := ItemCatalog.by_id(item_id)
			var display := String(row.get("display_name", item_id))
			var copies := bag.count(item_id)
			rows.append(display if copies <= 1 else "%s ×%d" % [display, copies])
	var mount := body.get_node_or_null("Weapons")
	if mount != null:
		for child: Node in mount.get_children():
			var weapon := child as WeaponBase
			if weapon == null:
				continue
			var display := weapon.evolved_name if weapon.evolved and not weapon.evolved_name.is_empty() \
					else UpgradePool.weapon_display_name(weapon.name)
			var tag := ("★%d" % weapon.ascension_tier) if weapon.ascension_tier > 0 \
					else (UiTheme.WEAPON_LEVEL_ABBREV % weapon.upgrade_level)
			rows.append("%s  %s" % [display, tag])
	var stats := PlayerStats.find_in(body)
	if stats != null:
		for tome_id: String in stats.carried_tome_ids():
			var tome := Tome.by_id(tome_id)
			rows.append("%s %s" % [String(tome.get("display_name", tome_id)),
					Tome.stack_label(stats.stack_count(tome_id))])
	return "\n".join(rows) if not rows.is_empty() else "—"


## --- drawing --------------------------------------------------------------

func _draw() -> void:
	if _map == null:
		return
	var side := minf(size.x * MAP_SHARE - PAD * 2.0, size.y - PAD * 2.0 - HEADER_FONT_SIZE * 2.0)
	if side <= 0.0:
		return
	var rect := Rect2(Vector2(PAD, PAD + HEADER_FONT_SIZE * 2.0), Vector2(side, side))
	draw_rect(rect.grow(3.0), Color(0.05, 0.055, 0.08, 0.9), true)
	_map.draw_into(self, rect)
	draw_rect(rect.grow(3.0), UiTheme.ACCENT.darkened(0.2), false, 2.0)
