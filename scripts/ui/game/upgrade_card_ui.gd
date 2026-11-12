extends CanvasLayer
## Selector de cartas: al subir de nivel (RunState.leveled_up) pausa el árbol,
## libera el mouse y ofrece 3 mejoras sorteadas de UpgradePool, todas de UN lado
## del grupo (armas o tomos/stats), que el título nombra; las elecciones extra
## mezclan ambos lados. Procesa siempre (process_mode ALWAYS) para que sus
## botones funcionen con todo lo demás en pausa.
##
## Los altares, la caja de mascota y el bloque de la suerte lo abren por el grupo "upgrade_ui":
## open_bonus_pick() da una elección gratis (con suerte extra o rareza mínima) y
## open_choice() muestra opciones que armó quien llama. Lo que llega con el
## selector abierto se encola (primero los niveles pendientes, después el resto)
## y se sirve en tandas seguidas antes de quitar la pausa.
##
## Cada carta es una instancia de UpgradeCard.tscn: este script decide qué
## mostrar y la coreografía (reparto, elección, cola); la carta decide cómo se
## ve. Todo el movimiento corre en esta capa ALWAYS e ignora la escala de
## tiempo, así que ni la pausa ni el hit-stop lo frenan. Cada reparto enfoca la
## primera carta y enlaza las vecinas izquierda/derecha: con el árbol pausado y
## Esc bloqueado, un selector que no se puede contestar con control o teclado
## congela la partida.

## Tipos de pedido en la cola (ver _open_request).
const KIND_BONUS := "bonus"
const KIND_CHOICE := "choice"

@export_group("Título")
## Espaciado extra entre letras del título, en píxeles. Tamaño, color y contorno
## del título están en el nodo LevelLabel de UpgradeCardUI.tscn.
@export var title_letter_spacing: int = 4

@export_group("Aviso del Tomo del Azar")
## Título del aviso de botín que lista las stats que movió el Tomo del Azar.
@export var gamble_toast_title: String = "Azar"
## Color de ese aviso.
@export var gamble_toast_color: Color = UiTheme.ACCENT_AMBER

@export_group("Textos")
## Título de una elección por nivel: número de nivel y el lado que ofrece.
@export var level_title_template: String = "Nivel %d — elige: %s"
## Título en co-op: el título de la elección y el número del jugador dueño.
@export var recipient_title_template: String = "%s  ·  Jugador %d"
## Indicación del botón de aceptar bajo las cartas.
@export var accept_hint_text: String = "Elegir"

@onready var _dim: ColorRect = %Dim
## Tiempos y escalas del reparto y de la elección (nodo Motion de esta escena).
@onready var _motion: UpgradePickMotion = $Motion
@onready var _level_label: Label = %LevelLabel
@onready var _cards: Array[UpgradeCard] = [%Card1 as UpgradeCard, %Card2 as UpgradeCard,
		%Card3 as UpgradeCard]

var _offer: Array[Dictionary] = []
## true desde la pausa hasta que aparecen las cartas: lo que llega en esa
## ventana se encola igual que si el selector ya estuviera a la vista.
var _opening: bool = false
var _pending_levels: int = 0
## Elecciones ganadas en espera, en orden de llegada: las tiradas extra y las
## opciones armadas comparten cola para que ninguna se adelante a la otra.
var _pending_bonus: Array[Dictionary] = []
## La elección en pantalla ({options, on_pick, tag}); vacía si es una oferta sorteada.
var _choice: Dictionary = {}
## Contexto de la tirada en pantalla (en cero para las elecciones por nivel).
var _luck_bonus: float = 0.0
var _min_rarity: String = ""
## Lado del grupo del que sale la elección en pantalla (UpgradePool SIDE_*);
## "" en las elecciones extra, que mezclan ambos lados.
var _side: String = ""
## true durante la animación de elección: ignora más clics, así un doble clic
## nunca aplica dos mejoras de la misma oferta.
var _picking: bool = false
## El raider dueño de esta elección (ver PickRecipients).
var _recipient: Node = null
var _recipients := PickRecipients.new()


func _ready() -> void:
	visible = false
	add_to_group("upgrade_ui")
	add_to_group(BlockingUi.GROUP)
	RunState.leveled_up.connect(_on_leveled_up)
	_level_label.add_theme_font_override("font", UiTheme.spaced_font(title_letter_spacing))
	# Indicación de botón bajo las cartas; sigue al último dispositivo usado.
	_level_label.get_parent().add_child(InputHints.build([["ui_accept", accept_hint_text]]))
	for i in _cards.size():
		_cards[i].pressed.connect(_on_card_pressed.bind(i))


## Contrato de PauseMenu ("ui_blocking"): true mientras esta capa es dueña de la
## pausa del árbol, incluida la ventana previa en la que todavía no se ve nada.
func is_blocking() -> bool:
	return visible or _opening


## Público (hoy lo llama el Altar de codicia, por el grupo "upgrade_ui"): una elección gratis
## fuera del flujo de nivel. luck_bonus es suerte temporal solo para esta tirada;
## min_rarity (p. ej. "Rare") pone piso a cada rareza sorteada. `recipient` es el
## raider dueño del premio: pásalo siempre que alguien PAGÓ la elección (el
## Altar de codicia cobra HP), o la rotación puede
## darle el premio a un compañero. Sin él se usa la rotación, así que los
## llamadores de 3 argumentos por call_group siguen funcionando. Se encola detrás
## de lo que ya esté abierto: un nivel y una elección extra del mismo frame nunca
## se pisan.
func open_bonus_pick(title: String, luck_bonus: float = 0.0, min_rarity: String = "",
		recipient: Node = null) -> void:
	if not RunState.run_active:
		return
	var request := {"kind": KIND_BONUS, "title": title, "luck_bonus": luck_bonus,
			"min_rarity": min_rarity, "recipient": recipient}
	_serve_or_queue(request)


## Público (altares, por el grupo "upgrade_ui"): una elección entre opciones que
## armó QUIEN LLAMA. `options` son filas listas para mostrar ({title,
## description, color} más lo que el llamador necesite de vuelta) y `on_pick`
## recibe la fila elegida. Aquí no se sortea rareza ni se toca UpgradePool: el
## llamador decide qué significa y esta capa pone el momento. `recipient` es el
## raider dueño de la elección (quien sostuvo el anillo del altar), y su nombre
## va en el título co-op.
func open_choice(title: String, options: Array[Dictionary], recipient: Node = null,
		on_pick: Callable = Callable(), tag: String = "") -> void:
	if not RunState.run_active or options.is_empty():
		return
	if options.size() > _cards.size():
		# Lo que sobra se descarta más abajo, y la opción que el llamador agrega
		# al FINAL suele ser la importante (la carta de rechazo del pozo de la
		# suerte): se avisa en vez de perderla en silencio.
		push_warning("UpgradeCardUI: %d options for %d cards — '%s' drops the surplus"
				% [options.size(), _cards.size(), title])
	_serve_or_queue({"kind": KIND_CHOICE, "title": title, "options": options,
			"recipient": recipient, "on_pick": on_pick, "tag": tag})


## Abre una elección ganada ahora o la encola detrás de la que ya está arriba.
## Un pedido que no puede abrirse (nadie en pie) vuelve a la cola en vez de
## perderse.
func _serve_or_queue(request: Dictionary) -> void:
	if visible or _opening:
		_pending_bonus.append(request)
		return
	if not _open_request(request):
		_pending_bonus.append(request)


func _on_leveled_up(new_level: int) -> void:
	# Si la partida terminó en el mismo frame, gana el fin de partida: desde ahí
	# la pantalla de fin (capa 20) es dueña de la pausa y del mouse.
	if not RunState.run_active:
		return
	if visible or _opening:
		_pending_levels += 1
		return
	if not _open_level_pick(new_level):
		_pending_levels += 1


## Las dos funciones que abren devuelven false si la elección no pudo abrirse
## (nadie en pie para recibirla), y quien llama la vuelve a encolar.
func _open_level_pick(new_level: int) -> bool:
	_luck_bonus = 0.0
	_min_rarity = ""
	_choice = {}
	# El lado se sortea contra el equipo de ESTE raider y va en el título, así
	# que el destinatario se resuelve antes que el título. _pick_recipient()
	# avanza la rotación una sola vez, y _open ya no puede fallar (su único
	# fallo es un destinatario nulo).
	var recipient := _pick_recipient()
	if recipient == null:
		return false
	_side = UpgradePool.roll_side(recipient)
	return _open(level_title_template % [new_level, UpgradePool.side_label(_side)],
			recipient)


## Sirve un pedido encolado de cualquier tipo. Ambos terminan en _open(), que
## comparte la pausa, el respiro previo y el título co-op.
func _open_request(request: Dictionary) -> bool:
	_side = ""
	if String(request.get("kind", KIND_BONUS)) == KIND_CHOICE:
		_luck_bonus = 0.0
		_min_rarity = ""
		_choice = request
		if _open(String(request.title), request.get("recipient", null) as Node):
			return true
		_choice = {}
		return false
	_choice = {}
	_luck_bonus = float(request.luck_bonus)
	_min_rarity = String(request.min_rarity)
	return _open(String(request.title), request.get("recipient", null) as Node)


func _open(title: String, requested_recipient: Node = null) -> bool:
	# Un premio pagado va a quien pagó; todo lo demás rota.
	var recipient := requested_recipient if is_instance_valid(requested_recipient) \
			else _pick_recipient()
	if recipient == null:
		# Todo el grupo caído (co-op): la oferta se sortea con las armas de un
		# CUERPO y no hay contra qué sortear. Se resuelve ANTES de pausar: un
		# selector vacío sobre un árbol pausado traba la partida.
		return false
	get_tree().paused = true
	_recipient = recipient
	if Coop.is_coop():
		title = recipient_title_template % [title, int(_recipient.get("player_index")) + 1]
	_level_label.text = title
	_roll()
	if visible:
		# Elección encadenada (recién se presionó una carta): ya está en
		# pantalla, así que la oferta nueva entra con un reparto rápido.
		_deal(true)
		return true
	# La pausa entra de inmediato (ningún combate se cuela en la ventana previa);
	# las cartas aparecen tras un respiro para que se lea el pulso de nivel. El
	# temporizador corre en pausa e ignora la escala de tiempo del hit-stop.
	_opening = true
	var timer := get_tree().create_timer(_motion.reveal_delay, true, false, true)
	timer.timeout.connect(_reveal, CONNECT_ONE_SHOT)
	return true


func _reveal() -> void:
	_opening = false
	# La partida puede terminar en la ventana previa (una gema te sube de nivel
	# al inicio del tick y un enemigo te mata antes de que acabe): desde ahí la
	# pantalla de fin es dueña de la pausa y del mouse, así que esta elección se
	# pliega en silencio en vez de dibujarse debajo.
	if not RunState.run_active:
		_cancel_pick()
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	_deal(false)


## Reparte la oferta en pantalla (quick = cambio en el lugar entre elecciones
## encadenadas) y enfoca la primera carta.
func _deal(quick: bool) -> void:
	_motion.deal(_dim, _level_label, _cards, quick)
	_focus_first_card()


## Acceso con teclado y control: sin un foco explícito nada aquí responde a
## ui_left/ui_right/ui_accept, y con el árbol pausado y Esc bloqueado por el
## contrato "ui_blocking", quien juega solo con control queda atascado. El foco
## se vuelve a tomar en cada reparto (una elección encadenada cambia la oferta
## bajo el cursor).
func _focus_first_card() -> void:
	var visible_cards: Array[Button] = []
	for card: Button in _cards:
		if card.visible:
			visible_cards.append(card)
	if visible_cards.is_empty():
		return
	# Vecinas izquierda/derecha con vuelta, para que la fila navegue como un anillo.
	for i in visible_cards.size():
		var previous := visible_cards[(i - 1 + visible_cards.size()) % visible_cards.size()]
		var next := visible_cards[(i + 1) % visible_cards.size()]
		visible_cards[i].focus_neighbor_left = previous.get_path()
		visible_cards[i].focus_neighbor_right = next.get_path()
	visible_cards[0].grab_focus()


func _roll() -> void:
	_kill_shines()
	if not _choice.is_empty():
		# Opciones del llamador: no hay nada que sortear, y _offer queda vacía
		# para que ninguna carta de aquí se aplique por UpgradePool.
		_offer = []
		var options: Array[Dictionary] = _choice.options
		var tag := String(_choice.get("tag", ""))
		for i in _cards.size():
			_cards[i].visible = i < options.size()
			if i < options.size():
				_cards[i].show_choice(options[i], tag)
		return
	# El grupo necesita al destinatario para ofrecer solo mejoras de SUS armas
	# y cartas de armas nuevas (se recalcula en cada tirada).
	var player := _resolve_recipient()
	_offer = UpgradePool.roll_offer(player, _cards.size(), _luck_bonus, _min_rarity, _side)
	for i in _cards.size():
		_cards[i].visible = i < _offer.size()
		if i < _offer.size():
			_cards[i].show_rolled(_offer[i])


func _on_card_pressed(index: int) -> void:
	if _picking:
		return
	if not _choice.is_empty():
		_pick_choice(index)
		return
	if index >= _offer.size():
		return
	_picking = true
	Sfx.play(&"card_pick")
	# Se aplica de inmediato; solo el gesto visual espera. Va al mismo
	# destinatario para el que se sorteó la oferta (una mejora de arma debe caer
	# en el cuerpo que tiene esa arma): _resolve_recipient guarda su respuesta,
	# así la tirada y el clic nunca resuelven raiders distintos.
	var player := _resolve_recipient()
	if player != null:
		var rolled := UpgradePool.apply(_offer[index], player)
		if not rolled.is_empty():
			# Tomo del Azar: sin esto la apuesta es invisible; las stats cambian
			# pero nada en pantalla dice cuáles.
			_toast_gamble(rolled, player)
	_animate_pick(index)


## Devuelve la opción elegida a quien pidió la elección. El callback se valida
## antes: el altar que abrió este menú puede hundirse y liberarse con la
## elección en pantalla.
func _pick_choice(index: int) -> void:
	var options: Array[Dictionary] = _choice.options
	if index >= options.size():
		return
	_picking = true
	Sfx.play(&"card_pick")
	var callback: Callable = _choice.get("on_pick", Callable())
	var chosen: Dictionary = options[index]
	_choice = {}
	if callback.is_valid():
		callback.call(chosen)
	_animate_pick(index)


## Muestra la tirada del Tomo del Azar en el aviso de botín del HUD.
func _toast_gamble(boons: Array[Dictionary], player: Node) -> void:
	var index: Variant = player.get("player_index")
	get_tree().call_group("hud", "show_loot", gamble_toast_title, Tome.boon_text(boons),
			gamble_toast_color, int(index) if index != null else 0)


## Gesto de la carta elegida; tras él la cola sigue igual (primero niveles,
## después elecciones extra).
func _animate_pick(index: int) -> void:
	_motion.pick(_cards, index, _after_pick)


func _after_pick() -> void:
	_picking = false
	# Una elección encolada que no puede abrirse ahora (nadie en pie) vuelve a la
	# cola y el selector se cierra, en vez de quedarse con una oferta vieja sobre
	# un árbol pausado.
	if _pending_levels > 0:
		_pending_levels -= 1
		if _open_level_pick(RunState.level):
			return
		_pending_levels += 1
	if not _pending_bonus.is_empty():
		var request: Dictionary = _pending_bonus.pop_front()
		if _open_request(request):
			return
		_pending_bonus.push_front(request)
	_close()


func _pick_recipient() -> Node:
	return _recipients.next(get_tree())


## El raider dueño de esta elección, resuelto una vez y reutilizado: _roll() y
## _on_card_pressed() nunca pueden contestar distinto (la oferta se arma con las
## armas de un cuerpo y debe caer en ese mismo cuerpo).
func _resolve_recipient() -> Node:
	if _recipient != null and is_instance_valid(_recipient) and _recipient.is_inside_tree():
		return _recipient
	_recipient = PartySlots.lowest_standing(get_tree())
	return _recipient


## Mata los brillos en bucle de las cartas legendarias (ver UpgradeCard.stop_shine).
func _kill_shines() -> void:
	for card: UpgradeCard in _cards:
		card.stop_shine()


## Pliega el selector sin tocar la pausa ni el mouse: para cuando la partida
## terminó debajo y otra capa ya es dueña de ambos.
func _cancel_pick() -> void:
	_opening = false
	_picking = false
	_pending_levels = 0
	_pending_bonus.clear()
	_choice = {}
	_kill_shines()
	visible = false


func _close() -> void:
	visible = false
	_kill_shines()
	# No deja movimiento viejo para la próxima apertura (el reparto reinicia todo).
	for card: Button in _cards:
		card.scale = Vector2.ONE
		card.modulate = Color.WHITE
		card.self_modulate = Color.WHITE
	# Solo suelta la pausa que tomó ESTA capa (contrato de pause_menu.gd). Si la
	# partida terminó debajo del selector, u otra capa que bloquea está arriba,
	# quitar la pausa aquí reanudaría el mundo detrás de la pantalla de fin y le
	# quitaría el mouse a sus botones.
	if not RunState.run_active or BlockingUi.other_open(get_tree(), self):
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
