class_name RouletteShrine
extends Interactable
## Altar de la ruleta: una ruleta de la fortuna que cobra puntos de partida por
## giro y abre un menú (RouletteUi) donde el raider gira por uno de los
## resultados de OUTCOMES, desde un objeto legendario hasta una maldición
## temporal. La ruleta se puede reusar, pero cada giro DUPLICA el precio para el
## resto de la partida (RunState.roulette_price_multiplier, de toda la partida
## como los precios de cofre), así que `price` es la base, nunca lo que se paga.

## Resultados de la ruleta, edita aquí. Campos de cada fila:
##   id      llave LÓGICA: apply_outcome decide por ella; no la cambies.
##   label   texto del jugador. Si lleva %d, el número sale del primer campo de
##           LABEL_NUMBER_FIELDS que tenga la fila, el mismo que usa el efecto;
##           sin esos campos se muestra tal cual.
##   weight  peso relativo en el sorteo.
##   color   color de la fila; las filas de objeto usan el de su `rarity`.
##   rarity  (objetos) id de rareza de UpgradePool.RARITIES que se sortea.
## Los demás campos son los números del efecto (ver apply_outcome).
const OUTCOMES: Array[Dictionary] = [
	{"id": "item_legendary", "label": "Objeto legendario", "weight": 3.0, "rarity": "Legendary"},
	{"id": "item_epic", "label": "Objeto épico", "weight": 7.0, "rarity": "Epic"},
	{"id": "item_rare", "label": "Objeto raro", "weight": 14.0, "rarity": "Rare"},
	{"id": "item_common", "label": "Objeto común", "weight": 18.0, "rarity": "Common"},
	{"id": "all_stats", "label": "Todas las stats +%d%%", "weight": 9.0,
			"color": Color(0.3, 0.82, 0.76), "amount": 10.0,
			"stats": ["damage", "cooldown", "area", "move_speed", "max_hp"]},
	{"id": "all_weapons", "label": "Todas las armas +%d nivel", "weight": 9.0,
			"color": Color(0.3, 0.82, 0.76), "levels": 1, "damage_multiplier": 1.15},
	{"id": "jackpot", "label": "Premio mayor: +%d pts", "weight": 6.0,
			"color": Color(1.0, 0.78, 0.2), "amount": 120},
	{"id": "heal", "label": "Curación total", "weight": 8.0, "color": Color(0.36, 0.8, 0.42)},
	{"id": "debuff", "label": "Maldición: lento y débil %d s", "weight": 12.0,
			"color": Color(0.92, 0.28, 0.24), "seconds": 20.0,
			"move_speed": -30.0, "damage": -25.0},
	{"id": "difficulty", "label": "Dificultad +%d%%", "weight": 8.0,
			"color": Color(0.92, 0.28, 0.24), "amount": 15.0},
	{"id": "enemy_frenzy", "label": "Enemigos más fuertes %d s", "weight": 6.0,
			"color": Color(0.92, 0.28, 0.24), "seconds": 30.0, "multiplier": 1.5},
]

## Campos que pueden llenar el %d de un `label`, en orden de búsqueda.
const LABEL_NUMBER_FIELDS: Array[String] = ["amount", "seconds", "levels"]

## El menú que abre el altar (RouletteUi). Se carga al abrirlo: roulette_ui.gd
## usa RouletteShrine y un preload aquí cerraría un ciclo de carga.
const ROULETTE_PANEL_PATH: String = "res://scenes/ui/modal/RoulettePanel.tscn"

@export_group("Precio")
## Precio base de un giro, en puntos, antes del multiplicador de la partida.
@export var price: int = 60

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


func _ready() -> void:
	super()
	_wheel = get_node_or_null("Visual/Wheel") as MeshInstance3D
	_refresh_prompt_text()


## El precio sube con cada giro de la partida, así que el prompt se vuelve a
## leer en vez de fijarse una vez al iniciar.
func current_price() -> int:
	return RunState.roulette_price(price)


func _refresh_prompt_text() -> void:
	set_prompt(prompt_template % current_price())


func _physics_process(delta: float) -> void:
	if _wheel != null:
		_wheel.rotate_y(delta * wheel_spin_speed)


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


## Color de un resultado: el de su rareza en las filas de objeto (el mismo de
## las cartas y los cofres), si no el `color` de la fila.
static func outcome_color(outcome: Dictionary) -> Color:
	if outcome.has("rarity"):
		return ItemCatalog.rarity_color(String(outcome.rarity))
	return outcome.get("color", Color.WHITE)


## Cobra el precio y tira; devuelve el resultado (vacío si no alcanza).
func spin(player: Node) -> Dictionary:
	if not player.has_method("spend_points") or not bool(player.call("spend_points", current_price())):
		return {}
	# Primero se cobra y DESPUÉS sube el precio: el siguiente giro (en este altar
	# o en cualquier otro) cuesta el doble, y el prompt lo vuelve a leer al
	# refrescarse.
	RunState.register_roulette_spin()
	_refresh_prompt_text()
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
		"item_legendary", "item_epic", "item_rare", "item_common":
			# La rareza es un id (ItemCatalog.roll_id y los precios de cofre se
			# indexan por ella, por eso queda en inglés); solo el aviso pasa por
			# rarity_display.
			var rarity := String(outcome.rarity)
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
		"all_weapons":
			var mount := player.get_node_or_null("Weapons")
			if mount != null:
				for child: Node in mount.get_children():
					var weapon := child as WeaponBase
					if weapon != null:
						weapon.damage *= float(outcome.damage_multiplier)
						weapon.upgrade_level += int(outcome.levels)
						EvolutionCatalog.try_advance_by_level(weapon, player)
		"jackpot":
			player.call("add_points", int(outcome.amount))
		"heal":
			var health := Health.find_in(player)
			if health != null:
				health.heal_full()
		"debuff":
			if stats != null:
				stats.add_timed_boon("move_speed", float(outcome.move_speed),
						float(outcome.seconds))
				stats.add_timed_boon("damage", float(outcome.damage), float(outcome.seconds))
		"difficulty":
			# `amount` está en por ciento, como en su texto.
			RunState.add_difficulty(float(outcome.amount) / 100.0, "roulette")
		"enemy_frenzy":
			get_tree().call_group("enemy_spawner", "apply_temp_enemy_buff",
					float(outcome.multiplier), float(outcome.seconds))
		_:
			push_warning("RouletteShrine: unknown outcome '%s'" % outcome_id)
