extends MetaScreen
## Armería: gasta esquirlas en rangos permanentes de reliquias (filas de
## RelicCatalog; SaveData guarda los rangos y PlayerStats los aplica en cada
## partida). Una fila por reliquia: nombre, línea de efecto, rombos de rango y
## un botón de compra con el precio del rango siguiente, o MÁX al llegar al
## tope. Comprar hace destellar la fila y descuenta el saldo
## (MetaScreen.payoff), igual que reclamar una misión; un rango que no
## alcanza recibe el vaivén de rechazo compartido.

@export_group("Filas")
## Nombre de la reliquia: tamaño de fuente (píxeles) y color.
@export var name_font_size: int = 16
@export var name_color: Color = UiTheme.TEXT_BRIGHT
## Línea de efecto: tamaño de fuente (píxeles) y color.
@export var effect_font_size: int = 12
@export var effect_color: Color = UiTheme.TEXT_DIM
## Rombos de rango: tamaño de fuente (píxeles), color con algún rango
## comprado y color sin ninguno.
@export var pips_font_size: int = 14
@export var pips_owned_color: Color = UiTheme.ACCENT_AMBER
@export var pips_empty_color: Color = UiTheme.TEXT_FAINT
## Sello de rango máximo: tamaño de fuente (píxeles) y color.
@export var maxed_font_size: int = 13
@export var maxed_color: Color = UiTheme.ACCENT_AMBER

@export_group("Textos")
## Rombo de un rango comprado y de uno que falta.
@export var pip_owned: String = "◆"
@export var pip_empty: String = "◇"
## Sello de una reliquia en su rango máximo.
@export var maxed_text: String = "MÁX"


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
	info.add_child(MetaScreen.label(String(relic.display_name), name_font_size, name_color))
	info.add_child(MetaScreen.label(_effect_line(relic), effect_font_size, effect_color))
	# Rombos de rango: llenos los comprados, huecos los que faltan.
	var pips := ""
	for i in max_ranks:
		pips += pip_owned if i < rank else pip_empty
	info.add_child(MetaScreen.label(pips, pips_font_size,
			pips_owned_color if rank > 0 else pips_empty_color))

	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 4)
	columns.add_child(side)
	if capped:
		var done := MetaScreen.label(maxed_text, maxed_font_size, maxed_color)
		done.add_theme_font_override("font", UiTheme.spaced_font(2))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(done)
	else:
		var cost := RelicCatalog.next_rank_cost(relic_id, rank)
		var buy := Button.new()
		buy.text = UiTheme.SHARDS_AMOUNT % cost
		buy.custom_minimum_size = Vector2(130.0, 34.0)
		buy.pressed.connect(_on_buy_pressed.bind(relic_id, row))
		UiTheme.style_button(buy, UiTheme.SHARD_BLUE, SaveData.can_afford(cost))
		side.add_child(buy)
	return row


## La línea de efecto es una plantilla del catálogo ("Todo el daño %s por
## rango.") rellenada con el texto del monto por rango. Protegida: una fila
## traducida que pierde el %s daría un error de formato en tiempo de
## ejecución y dejaría esa fila en blanco.
func _effect_line(relic: Dictionary) -> String:
	var template := String(relic.description)
	if not template.contains("%s"):
		push_warning("RelicCatalog: description without '%%s' in '%s'" % String(relic.id))
		return template
	return template % String(relic.amount_text)
