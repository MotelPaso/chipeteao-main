class_name RouletteShrine
extends Interactable
## Altar de la ruleta: una ruleta de la fortuna que cobra puntos de partida por
## giro y abre un menú (RouletteUi) donde el raider gira por uno de los
## resultados de abajo, desde un objeto legendario hasta una maldición temporal.
## La ruleta se puede reusar, pero cada giro DUPLICA el precio para el resto de
## la partida (RunState.roulette_price_multiplier, de toda la partida como los
## precios de cofre), así que `price` es la base, nunca lo que se paga.

## Precio base de un giro, en puntos, antes del multiplicador de la partida.
@export var price: int = 60

## Resultados: {id, label, weight, color}. El id es la llave LÓGICA
## (apply_outcome decide por él, y las cuatro filas de objeto llevan un id de
## rareza en su sufijo); label es lo único que lee el jugador.
const OUTCOMES: Array[Dictionary] = [
	{"id": "item_legendary", "label": "Objeto legendario", "weight": 3.0, "color": Color(1.0, 0.78, 0.2)},
	{"id": "item_epic", "label": "Objeto épico", "weight": 7.0, "color": Color(0.68, 0.32, 0.95)},
	{"id": "item_rare", "label": "Objeto raro", "weight": 14.0, "color": Color(0.3, 0.55, 1.0)},
	{"id": "item_common", "label": "Objeto común", "weight": 18.0, "color": Color(0.62, 0.65, 0.68)},
	{"id": "all_stats", "label": "Todas las stats +10%", "weight": 9.0, "color": Color(0.3, 0.82, 0.76)},
	{"id": "all_weapons", "label": "Todas las armas +1 nivel", "weight": 9.0, "color": Color(0.3, 0.82, 0.76)},
	{"id": "jackpot", "label": "Premio mayor: +120 pts", "weight": 6.0, "color": Color(1.0, 0.78, 0.2)},
	{"id": "heal", "label": "Curación total", "weight": 8.0, "color": Color(0.36, 0.8, 0.42)},
	{"id": "debuff", "label": "Maldición: lento y débil 20 s", "weight": 12.0, "color": Color(0.92, 0.28, 0.24)},
	{"id": "difficulty", "label": "Dificultad +15%", "weight": 8.0, "color": Color(0.92, 0.28, 0.24)},
	{"id": "enemy_frenzy", "label": "Enemigos más fuertes 30 s", "weight": 6.0, "color": Color(0.92, 0.28, 0.24)},
]

const RouletteUiScript := preload("res://scripts/ui/game/roulette_ui.gd")

var _wheel: MeshInstance3D = null
var _time: float = 0.0
var _ui: CanvasLayer = null


## Giro de la rueda del altar en reposo, en radianes por segundo.
const WHEEL_SPIN: float = 0.6


func _init() -> void:
	meta_stat_id = ""
	prompt_text = "[E] Girar la ruleta"
	marker_kind = &"roulette"


func _ready() -> void:
	super()
	_wheel = get_node_or_null("Visual/Wheel") as MeshInstance3D
	_refresh_prompt_text()


## El precio sube con cada giro de la partida, así que el prompt se vuelve a
## leer en vez de fijarse una vez al iniciar.
func current_price() -> int:
	return RunState.roulette_price(price)


func _refresh_prompt_text() -> void:
	set_prompt("[E] Girar la ruleta — %d pts" % current_price())


func _physics_process(delta: float) -> void:
	_time += delta
	if _wheel != null:
		_wheel.rotate_y(delta * WHEEL_SPIN)


func _interact(player: Node) -> void:
	var cost := current_price()
	if int(player.get("points")) < cost:
		Sfx.play(&"dodge")
		set_prompt("Girar cuesta %d pts (tienes %d)" % [cost, int(player.get("points"))])
		return
	if _ui != null and is_instance_valid(_ui):
		return
	# Nunca sobre otra capa que pausa el árbol: el panel de la ruleta suelta la
	# pausa al cerrarse, y esa pausa podría ser del selector de cartas o del
	# menú de Esc.
	if BlockingUi.any_open(get_tree()):
		return
	_ui = RouletteUiScript.new()
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


## Aplica un resultado a `player` (y a la partida, en los compartidos).
func apply_outcome(outcome_id: String, player: Node) -> void:
	var stats := PlayerStats.find_in(player)
	var bag := ItemBag.find_in(player)
	match outcome_id:
		"item_legendary", "item_epic", "item_rare", "item_common":
			# La mitad del id es la LLAVE de rareza (ItemCatalog.roll_id y los
			# precios de cofre se indexan por ella, por eso queda en inglés);
			# solo el aviso pasa por rarity_display.
			var rarity := outcome_id.trim_prefix("item_").capitalize()
			var item_id := ItemCatalog.roll_id(rarity)
			if bag != null and not item_id.is_empty():
				bag.add_item(item_id)
				get_tree().call_group("hud", "announce", "%s: %s" % [
						UpgradePool.rarity_display(rarity),
						String(ItemCatalog.by_id(item_id).display_name)])
		"all_stats":
			if stats != null:
				for stat: String in ["damage", "cooldown", "area", "move_speed", "max_hp"]:
					stats.add_altar_boon(stat, 10.0)
		"all_weapons":
			var mount := player.get_node_or_null("Weapons")
			if mount != null:
				for child: Node in mount.get_children():
					var weapon := child as WeaponBase
					if weapon != null:
						weapon.damage *= 1.15
						weapon.upgrade_level += 1
						EvolutionCatalog.try_advance_by_level(weapon, player)
		"jackpot":
			player.call("add_points", 120)
		"heal":
			var health := Health.find_in(player)
			if health != null:
				health.heal_full()
		"debuff":
			if stats != null:
				stats.add_timed_boon("move_speed", -30.0, 20.0)
				stats.add_timed_boon("damage", -25.0, 20.0)
		"difficulty":
			RunState.add_difficulty(0.15, "roulette")
		"enemy_frenzy":
			get_tree().call_group("enemy_spawner", "apply_temp_enemy_buff", 1.5, 30.0)
		_:
			push_warning("RouletteShrine: unknown outcome '%s'" % outcome_id)
