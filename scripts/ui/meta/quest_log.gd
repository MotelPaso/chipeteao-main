extends MetaScreen
## Registro de misiones (GDD 8), abierto desde la tarjeta Misiones del menú:
## cada desafío de QuestCatalog como una tarjeta (QuestCard.tscn), en grupos
## con un título pequeño. Arriba van las completas sin reclamar («Para
## reclamar»), después las que siguen en curso agrupadas por tipo (bajas,
## jefes, altares… según QuestTypes) y al final las ya reclamadas, atenuadas.
## Reclamar es el pago manual que acredita las esquirlas (SaveData guarda al
## instante).
##
## El aspecto de cada tarjeta vive en QuestCard.tscn. El cromo, la salida con
## Esc/Volver y el pago (la tarjeta destella en oro y el saldo cuenta y salta)
## vienen de MetaScreen. La entrada es propia: las tarjetas llegan una tras
## otra en vez de deslizarse toda la pantalla.

const CARD_SCENE: PackedScene = preload("res://scenes/ui/meta/QuestCard.tscn")

@export_group("Grupos")
## Título del grupo de misiones completas sin reclamar.
@export var claimable_title: String = "Para reclamar"
## Título del grupo de misiones ya reclamadas.
@export var claimed_title: String = "Reclamadas"
## Título de cada grupo: su nombre y cuántas misiones tiene.
@export var group_title_format: String = "%s · %d"
## Tamaño de fuente del título de cada grupo, en píxeles.
@export var group_title_font_size: int = 15
## Color del título de cada grupo.
@export var group_title_color: Color = UiTheme.ACCENT
## Color del título del grupo de reclamadas.
@export var claimed_title_color: Color = UiTheme.TEXT_FAINT
## Espacio extra entre las letras del título de cada grupo, en píxeles.
@export var group_title_spacing: int = 1
## Aire sobre el título de un grupo, en píxeles (separa un grupo del anterior).
@export var group_gap: float = 8.0

@export_group("Entrada")
## Espera entre la primera tarjeta y la segunda al abrir, en segundos.
@export var card_stagger: float = 0.06
## Cuánto se acorta cada espera respecto de la anterior (1 = todas iguales).
@export_range(0.5, 1.0) var card_stagger_shrink: float = 0.8
## Desde esta tarjeta todas llegan juntas: las de más abajo no se ven al abrir.
@export var card_stagger_cap: int = 6


func _slides_in() -> bool:
	return false


## Entrada al abrir: las tarjetas llegan una tras otra con esperas que se
## acortan, y desde card_stagger_cap todas juntas. Los títulos de grupo, el
## título y Volver ya están ahí: una sola entrada por pantalla. Es decorativa:
## el foco y los botones funcionan desde el primer frame.
func play_entrance() -> void:
	var index := 0
	for child: Node in _list.get_children():
		var card := child as QuestCard
		if card != null:
			card.play_entrance(_card_delay(index))
			index += 1


func _build_rows(list_node: VBoxContainer) -> void:
	var claimable: Array[Dictionary] = []
	var claimed: Array[Dictionary] = []
	var by_type: Dictionary[String, Array] = {}
	for quest: Dictionary in QuestCatalog.QUEST_LIBRARY:
		var quest_id := String(quest.id)
		if SaveData.is_quest_claimed(quest_id):
			claimed.append(quest)
		elif SaveData.is_quest_completed(quest_id):
			claimable.append(quest)
		else:
			var type_id := QuestTypes.type_of(String(quest.stat))
			if not by_type.has(type_id):
				by_type[type_id] = []
			by_type[type_id].append(quest)
	_add_group(list_node, claimable_title, group_title_color, claimable,
			QuestCard.State.CLAIMABLE)
	for type_id: String in QuestTypes.ids():
		var quests: Array[Dictionary] = []
		quests.assign(by_type.get(type_id, []))
		_add_group(list_node, QuestTypes.title(type_id), group_title_color, quests,
				QuestCard.State.IN_PROGRESS)
	_add_group(list_node, claimed_title, claimed_title_color, claimed,
			QuestCard.State.CLAIMED)


## Un grupo: su título y una tarjeta por misión. Un grupo vacío no se dibuja.
func _add_group(list_node: VBoxContainer, title: String, title_color: Color,
		quests: Array[Dictionary], state: QuestCard.State) -> void:
	if quests.is_empty():
		return
	list_node.add_child(_group_title(group_title_format % [title, quests.size()],
			title_color, list_node.get_child_count() > 0))
	for quest: Dictionary in quests:
		var card: QuestCard = CARD_SCENE.instantiate()
		list_node.add_child(card)
		card.show_quest(quest, state, SaveData.stat(String(quest.stat)))
		card.claim_pressed.connect(_on_claim_pressed.bind(card))


func _group_title(text: String, color: Color, spaced: bool) -> Control:
	var title := MetaScreen.label(text, group_title_font_size, color)
	title.add_theme_font_override("font", UiTheme.display_font(group_title_spacing))
	if not spaced:
		return title
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", int(group_gap))
	margin.add_child(title)
	return margin


## El pago: acredita las esquirlas y deja que MetaScreen haga destellar la
## tarjeta, cuente el saldo y reordene la lista.
func _on_claim_pressed(quest_id: String, card: QuestCard) -> void:
	var before := SaveData.shards
	if SaveData.claim_quest(quest_id) <= 0:
		return
	payoff(card, before, SaveData.shards, &"gem_pickup")


## Espera de la tarjeta número `index` (desde 0): cada paso es más corto que
## el anterior (card_stagger_shrink) y se detiene en card_stagger_cap.
func _card_delay(index: int) -> float:
	var delay := 0.0
	var step := card_stagger
	for i in mini(index, card_stagger_cap):
		delay += step
		step *= card_stagger_shrink
	return delay
