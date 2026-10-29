extends MetaScreen
## Armory screen (iteration 36): spend Shards on permanent Relic ranks
## (RelicCatalog rows; SaveData persists the ranks and PlayerStats applies
## them every run). One row per relic: name, effect line, rank pips, and a
## buy button with the next rank's price — or MÁX once capped. Buying
## flashes the row and counts the balance down (MetaScreen.payoff),
## mirroring the quest log's claim so spending feels as good as earning;
## an unaffordable rank gets the shared reject wobble.


func _build_rows(list_node: VBoxContainer) -> void:
	for relic: Dictionary in RelicCatalog.RELIC_LIBRARY:
		list_node.add_child(_build_row(relic))


func _on_buy_pressed(relic_id: String, row: PanelContainer) -> void:
	var before := SaveData.shards
	if not SaveData.purchase_relic(relic_id):
		reject(row)
		return
	payoff(row, before, SaveData.shards, &"chest_open")


func _build_row(relic: Dictionary) -> PanelContainer:
	var relic_id := String(relic.id)
	var rank := SaveData.relic_rank(relic_id)
	var max_ranks := int(relic.max_ranks)
	var capped := rank >= max_ranks
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", MetaScreen.card_style(
			UiTheme.ACCENT_AMBER if capped else UiTheme.BORDER_DIM, capped))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	row.add_child(columns)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	columns.add_child(info)
	info.add_child(MetaScreen.label(String(relic.display_name), 16, UiTheme.TEXT_BRIGHT))
	info.add_child(MetaScreen.label(_effect_line(relic), 12, UiTheme.TEXT_DIM))
	# Rank pips: filled diamonds for owned ranks, hollow for the rest.
	var pips := ""
	for i in max_ranks:
		pips += "◆" if i < rank else "◇"
	info.add_child(MetaScreen.label(pips, 14,
			UiTheme.ACCENT_AMBER if rank > 0 else UiTheme.TEXT_FAINT))

	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 4)
	columns.add_child(side)
	if capped:
		var done := MetaScreen.label("MÁX", 13, UiTheme.ACCENT_AMBER)
		done.add_theme_font_override("font", UiTheme.spaced_font(2))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(done)
	else:
		var cost := RelicCatalog.next_rank_cost(relic_id, rank)
		var buy := Button.new()
		buy.text = "%d esquirlas" % cost
		buy.custom_minimum_size = Vector2(130.0, 34.0)
		buy.pressed.connect(_on_buy_pressed.bind(relic_id, row))
		UiTheme.style_button(buy, UiTheme.SHARD_BLUE, SaveData.can_afford(cost))
		side.add_child(buy)
	return row


## The effect line is a catalog template ("Todo el daño %s por rango.")
## filled with the per-rank amount text. Guarded: a translated row that
## drops the %s would otherwise raise a formatting error at runtime and
## leave that single row blank while its five neighbours look fine.
func _effect_line(relic: Dictionary) -> String:
	var template := String(relic.description)
	if not template.contains("%s"):
		push_warning("RelicCatalog: description without '%%s' in '%s'" % String(relic.id))
		return template
	return template % String(relic.amount_text)
