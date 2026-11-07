extends MetaScreen
## Registro de misiones (GDD 8), abierto desde el botón Misiones del
## selector: cada desafío de QuestCatalog como una fila con nombre,
## descripción, barra de progreso x/y y su recompensa en esquirlas. Las
## misiones completas sin reclamar suben arriba con borde brillante y un
## botón Reclamar: reclamar es el pago manual que acredita las esquirlas
## (SaveData guarda al instante). Las reclamadas bajan al fondo, atenuadas.
##
## El cromo, la salida con Esc/Volver, la entrada escalonada y el pago (la
## fila destella en oro y el saldo cuenta y salta) vienen de MetaScreen.

## Modulate de las filas ya reclamadas.
const CLAIMED_MODULATE := Color(1.0, 1.0, 1.0, 0.45)

## Tres estados de fila que se excluyen entre sí.
enum RowState { IN_PROGRESS, CLAIMABLE, CLAIMED }

@export_group("Filas")
## Nombre de la misión: tamaño de fuente (píxeles) y color.
@export var name_font_size: int = 16
@export var name_color: Color = UiTheme.TEXT_BRIGHT
## Descripción de la misión: tamaño de fuente (píxeles) y color.
@export var description_font_size: int = 12
@export var description_color: Color = UiTheme.TEXT_DIM
## Recompensa "+N esquirlas" a la derecha: tamaño de fuente (píxeles) y color.
@export var reward_font_size: int = 14
@export var reward_color: Color = UiTheme.SHARD_BLUE
## Contador "x/y" junto a la barra: tamaño de fuente (píxeles) y color.
@export var progress_font_size: int = 12
@export var progress_color: Color = Color(0.72, 0.74, 0.78)
## Sello de misión reclamada: tamaño de fuente (píxeles) y color.
@export var claimed_font_size: int = 12
@export var claimed_color: Color = UiTheme.TEXT_FAINT

@export_group("Textos")
## Botón de una misión completa sin reclamar.
@export var claim_text: String = "Reclamar"
## Sello de una misión ya reclamada.
@export var claimed_text: String = "RECLAMADA"


## Primero las reclamables, luego las en curso en orden de catálogo y al
## final las reclamadas, atenuadas.
func _build_rows(list_node: VBoxContainer) -> void:
	var claimable: Array[Dictionary] = []
	var in_progress: Array[Dictionary] = []
	var claimed: Array[Dictionary] = []
	for quest: Dictionary in QuestCatalog.QUEST_LIBRARY:
		var quest_id := String(quest.id)
		if SaveData.is_quest_claimed(quest_id):
			claimed.append(quest)
		elif SaveData.is_quest_completed(quest_id):
			claimable.append(quest)
		else:
			in_progress.append(quest)
	for quest: Dictionary in claimable:
		list_node.add_child(_build_row(quest, RowState.CLAIMABLE))
	for quest: Dictionary in in_progress:
		list_node.add_child(_build_row(quest, RowState.IN_PROGRESS))
	for quest: Dictionary in claimed:
		list_node.add_child(_build_row(quest, RowState.CLAIMED))


## El pago: acredita las esquirlas y deja que MetaScreen haga destellar la
## fila, cuente el saldo y reordene la lista.
func _on_claim_pressed(quest_id: String, row: PanelContainer) -> void:
	var before := SaveData.shards
	if SaveData.claim_quest(quest_id) <= 0:
		return
	payoff(row, before, SaveData.shards, &"gem_pickup")


func _build_row(quest: Dictionary, state: RowState) -> PanelContainer:
	var row := PanelContainer.new()
	var claimable := state == RowState.CLAIMABLE
	row.add_theme_stylebox_override("panel", MetaScreen.card_style(
			UiTheme.ACCENT_AMBER if claimable else UiTheme.BORDER_DIM, claimable))
	if state == RowState.CLAIMED:
		row.modulate = CLAIMED_MODULATE
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	row.add_child(columns)
	columns.add_child(_build_info(quest, state))
	columns.add_child(_build_side(quest, state, row))
	return row


## Columna izquierda: nombre, descripción y la línea de progreso.
func _build_info(quest: Dictionary, state: RowState) -> VBoxContainer:
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	info.add_child(MetaScreen.label(String(quest.display_name), name_font_size, name_color))
	info.add_child(MetaScreen.label(String(quest.description), description_font_size,
			description_color))
	info.add_child(_progress_line(SaveData.stat(String(quest.stat)), int(quest.target),
			state != RowState.IN_PROGRESS))
	return info


## Columna derecha: la recompensa y lo propio del estado (botón Reclamar,
## sello RECLAMADA o nada mientras sigue en curso).
func _build_side(quest: Dictionary, state: RowState,
		row: PanelContainer) -> VBoxContainer:
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 4)
	var reward := MetaScreen.label(UiTheme.SHARDS_GAIN % int(quest.reward),
			reward_font_size, reward_color)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(reward)
	if state == RowState.CLAIMABLE:
		var claim := Button.new()
		claim.text = claim_text
		claim.custom_minimum_size = Vector2(110.0, 34.0)
		claim.pressed.connect(_on_claim_pressed.bind(String(quest.id), row))
		UiTheme.style_button(claim, UiTheme.ACCENT_AMBER, true)
		side.add_child(claim)
	elif state == RowState.CLAIMED:
		var done := MetaScreen.label(claimed_text, claimed_font_size, claimed_color)
		done.add_theme_font_override("font", UiTheme.spaced_font(2))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(done)
	return side


## Barra "x/y" con contador; la barra se acota, así pasarse se lee lleno.
## Las misiones terminadas pintan el relleno de ámbar.
func _progress_line(current: int, target: int, complete: bool) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(260.0, 14.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = float(target)
	bar.value = float(mini(current, target))
	bar.show_percentage = false
	UiTheme.style_bar(bar,
			UiTheme.ACCENT_AMBER if complete else UiTheme.SHARD_BLUE.darkened(0.15),
			5, 2)
	line.add_child(bar)
	line.add_child(MetaScreen.label("%d/%d" % [mini(current, target), target],
			progress_font_size, progress_color))
	return line
