class_name RouletteShrine
extends Interactable
## Altar de la ruleta: una ruleta de la fortuna que cobra puntos de partida y
## abre un menú (RouletteUi) donde el raider gira por uno de los resultados de
## OUTCOMES. Se usa UNA vez: al girar se gasta y se hunde cuando se cierra el
## menú (el director puede volver a sacar otra como evento). Cada giro sube
## el precio un porcentaje (RunState.ROULETTE_PRICE_GROWTH) para el resto de
## la partida, así que `price` es la base, nunca lo que se paga.

## Resultados de la ruleta, edita aquí. Campos de cada fila:
##   id      llave LÓGICA: apply_outcome decide por ella; no la cambies.
##   label   texto del jugador. Si lleva %d, el número sale del primer campo de
##           LABEL_NUMBER_FIELDS que tenga la fila, el mismo que usa el efecto;
##           sin esos campos se muestra tal cual.
##   weight  peso relativo en el sorteo.
##   color   color de la fila; las filas de objeto usan el de su `rarity`.
## Los demás campos son los números del efecto (ver apply_outcome).
const OUTCOMES: Array[Dictionary] = [
	{"id": "difficulty", "label": "Dificultad +%d%%", "weight": 0.2,
			"color": Color(0.92, 0.28, 0.24), "amount": 15.0},
	# amount = % de lo que costó ESTE giro (150 = devuelve 1.5 veces lo pagado).
	{"id": "jackpot", "label": "Puntos: %d%% de lo que pagaste", "weight": 0.2,
			"color": Color(1.0, 0.78, 0.2), "amount": 150},
	# amount = gemas; gem_value = XP de cada una; radios en metros alrededor del raider.
	{"id": "xp_rain", "label": "Lluvia de XP: %d gemas", "weight": 0.2,
			"color": Color(0.45, 0.9, 0.6), "amount": 18, "gem_value": 3,
			"min_spread": 1.5, "max_spread": 6.0},
	# La rareza se sortea con la suerte del raider, como en un cofre.
	{"id": "random_item", "label": "Objeto al azar", "weight": 0.2,
			"color": Color(0.68, 0.32, 0.95)},
	{"id": "all_stats", "label": "Todas las stats +%d%%", "weight": 0.2,
			"color": Color(0.3, 0.82, 0.76), "amount": 8.0,
			# Suma plana: +amount% en las stats de porcentaje (la armadura
			# también) y +amount puntos en vida máx., suerte y espinas. Saltos
			# y proyectiles no.
			"stats": ["damage", "cooldown", "area", "move_speed", "crit_chance",
					"crit_damage", "lifesteal", "evasion", "duration", "xp_gain",
					"pickup_radius", "powerup_chance", "max_hp", "luck", "armor",
					"thorns"]},
]

## Campos que pueden llenar el %d de un `label`, en orden de búsqueda.
const LABEL_NUMBER_FIELDS: Array[String] = ["amount", "seconds", "levels"]

## El menú que abre el altar (RouletteUi). Se carga al abrirlo: roulette_ui.gd
## usa RouletteShrine y un preload aquí cerraría un ciclo de carga.
const ROULETTE_PANEL_PATH: String = "res://scenes/ui/modal/RoulettePanel.tscn"

@export_group("Precio")
## Precio base de un giro, en puntos, antes del multiplicador de la partida.
@export var price: int = 40

@export_group("Rueda")
## Giro de la rueda del altar en reposo, en radianes por segundo.
@export var wheel_spin_speed: float = 0.6

@export_group("Textos")
## Prompt del altar; %d es el precio del próximo giro.
@export var prompt_template: String = "[E] Girar la ruleta — %d pts"
## Prompt cuando el raider no alcanza a pagar: el precio y los puntos que tiene.
@export var broke_prompt_template: String = "Girar cuesta %d pts (tienes %d)"

var _wheel: MeshInstance3D = null
var _ui: RouletteUi = null
## Puntos que costó el último giro (el premio «Puntos» paga un % de esto).
var _last_paid: int = 0


func _ready() -> void:
	super()
	# El director limita las ruletas en el mapa por este grupo.
	add_to_group(&"roulettes")
	_wheel = get_node_or_null("Visual/Wheel") as MeshInstance3D
	_refresh_prompt_text()


func _physics_process(delta: float) -> void:
	if _wheel != null:
		_wheel.rotate_y(delta * wheel_spin_speed)


## El precio sube con cada giro de la partida, así que el prompt se vuelve a
## leer en vez de fijarse una vez al iniciar.
func current_price() -> int:
	return RunState.roulette_price(price)


## Elección ponderada pura sobre OUTCOMES para una tirada uniforme en [0, 1).
static func outcome_for(roll: float) -> Dictionary:
	var total := 0.0
	for outcome: Dictionary in OUTCOMES:
		total += float(outcome.weight)
	var pick := roll * total
	for outcome: Dictionary in OUTCOMES:
		pick -= float(outcome.weight)
		if pick <= 0.0:
			return outcome
	return OUTCOMES[OUTCOMES.size() - 1]


## La fila de OUTCOMES con ese id ({} si no existe).
static func outcome_by_id(outcome_id: String) -> Dictionary:
	for outcome: Dictionary in OUTCOMES:
		if String(outcome.id) == outcome_id:
			return outcome
	return {}


## Texto del jugador para un resultado: su `label`, con el %d lleno desde el
## primer campo de LABEL_NUMBER_FIELDS que tenga la fila.
static func outcome_label(outcome: Dictionary) -> String:
	var label := String(outcome.get("label", ""))
	for field: String in LABEL_NUMBER_FIELDS:
		if outcome.has(field):
			return label % int(outcome[field])
	return label


## Color de un resultado: el `color` de su fila.
static func outcome_color(outcome: Dictionary) -> Color:
	return outcome.get("color", Color.WHITE)


## Cobra el precio y tira; devuelve el resultado (vacío si no alcanza).
func spin(player: Node) -> Dictionary:
	var paid := current_price()
	if not player.has_method("spend_points") or not bool(player.call("spend_points", paid)):
		return {}
	_last_paid = paid
	# Primero se cobra y DESPUÉS sube el precio: el siguiente giro (en este altar
	# o en cualquier otro) cuesta más, y el prompt lo vuelve a leer al
	# refrescarse.
	RunState.register_roulette_spin()
	# Un solo uso: se gasta ya y se hunde cuando el menú suelta la pausa.
	consume()
	sink_away()
	SaveData.bump("shrines_used")
	SaveData.bump("roulette_spins")
	var outcome := outcome_for(randf())
	apply_outcome(String(outcome.id), player)
	print("Roulette spun: %s" % String(outcome.id))
	return outcome


## Aplica un resultado a `player` (y a la partida, en los compartidos). Los
## números salen de la fila de OUTCOMES, los mismos que muestra su texto.
func apply_outcome(outcome_id: String, player: Node) -> void:
	var outcome := outcome_by_id(outcome_id)
	var stats := PlayerStats.find_in(player)
	var bag := ItemBag.find_in(player)
	match outcome_id:
		"random_item":
			# La rareza es un id (ItemCatalog.roll_id y los precios de cofre se
			# indexan por ella, por eso queda en inglés); solo el aviso pasa por
			# rarity_display.
			var luck := stats.luck if stats != null else 0.0
			var rarity := String(UpgradePool.roll_rarity(luck).name)
			var item_id := ItemCatalog.roll_id(rarity)
			if bag != null and not item_id.is_empty():
				bag.add_item(item_id)
				get_tree().call_group("hud", "announce", "%s: %s" % [
						UpgradePool.rarity_display(rarity),
						String(ItemCatalog.by_id(item_id).display_name)])
		"all_stats":
			if stats != null:
				for stat: String in outcome.stats:
					stats.add_altar_boon(stat, float(outcome.amount))
		"jackpot":
			player.call("add_points", roundi(float(_last_paid) * float(outcome.amount) / 100.0))
		"xp_rain":
			_rain_xp(outcome, player as Node3D)
		"difficulty":
			# `amount` está en por ciento, como en su texto.
			RunState.add_difficulty(float(outcome.amount) / 100.0, "roulette")
		_:
			push_warning("RouletteShrine: unknown outcome '%s'" % outcome_id)


## Un anillo de gemas de XP alrededor del raider.
func _rain_xp(outcome: Dictionary, player: Node3D) -> void:
	if player == null:
		return
	var count := int(outcome.amount)
	for i in count:
		var gem := Pools.acquire_scene(Pools.XP_GEM_SCENE) as XpGem
		if gem == null:
			break
		gem.xp_value = int(outcome.gem_value)
		var angle := TAU * float(i) / float(count)
		gem.global_position = player.global_position + Vector3.UP * 0.6 \
				+ Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(float(outcome.min_spread), float(outcome.max_spread))


func _refresh_prompt_text() -> void:
	set_prompt(prompt_template % current_price())


func _interact(player: Node) -> void:
	var cost := current_price()
	if int(player.get("points")) < cost:
		Sfx.play(&"dodge")
		set_prompt(broke_prompt_template % [cost, int(player.get("points"))])
		return
	if _ui != null and is_instance_valid(_ui):
		return
	# Nunca sobre otra capa que pausa el árbol: el panel de la ruleta suelta la
	# pausa al cerrarse, y esa pausa podría ser del selector de cartas o del
	# menú de Esc.
	if BlockingUi.any_open(get_tree()):
		return
	_ui = (load(ROULETTE_PANEL_PATH) as PackedScene).instantiate() as RouletteUi
	_ui.setup(self, player)
	# Bajo la ESCENA ACTUAL, nunca bajo /root: esta capa tiene todo el árbol
	# pausado, y un CanvasLayer colgado de root sobrevive a
	# change_scene_to_file y deja la siguiente arena congelada detrás de un
	# panel huérfano que nadie puede cerrar.
	var host := RunRoot.stage_parent(get_tree())
	if host == null:
		host = get_tree().root
	host.add_child(_ui)
