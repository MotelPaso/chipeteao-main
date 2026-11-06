class_name Chest
extends Interactable
## Cofre del tesoro: paga UN objeto de ItemCatalog (nunca cartas ni armas).
##
## Los cofres DE PAGO sellan su rareza al aparecer: se tira en _ready con los
## pesos de rareza de las cartas, inclinados por luck_bonus y con piso en
## min_rarity, y el precio sale de RunState (base por rareza × un
## multiplicador global que crece con cada cofre que se abre).
##
## Los cofres GRATIS (jefes, shinies, parte de los cofres de inicio, el
## pacto del cofre) no cuestan nada, NO encarecen los de pago y tiran su
## rareza AL ABRIRSE, con la suerte de quien los abre. Sin rareza sellada,
## llevan su propio tinte blanco dorado.
##
## Un solo uso: al pagar se hunde y se libera.

## Modo gratis: sin precio, sin encarecer y con la rareza tirada al abrir. Se
## llama free_open y no `free`, que es Object.free().
@export var free_open: bool = false
## Rareza fija como id en inglés ("" = se tira al aparecer, o al abrir si es gratis).
@export var rarity: String = ""
## Suerte extra que inclina la tirada de rareza (la ponen los cofres de suministros del WorldDirector).
@export var luck_bonus: float = 0.0
## Piso de rareza de la tirada al aparecer, como id en inglés ("" = sin piso).
@export var min_rarity: String = ""
## Segundos que dura el salto de apertura; el objeto se entrega al terminar.
@export var open_duration: float = 0.45
## Rotación X de la tapa abierta (no hace nada: la escena no tiene LidPivot).
@export var lid_open_angle: float = -1.75
## Segundos que sigue vivo el cofre tras pagar antes de liberarse.
@export var reward_linger: float = 1.4

## Salto al abrir: altura en metros y fracción de open_duration que dura la
## subida (el resto es el rebote de bajada).
const OPEN_HOP_HEIGHT: float = 0.3
const OPEN_HOP_UP_SHARE: float = 0.4
## Hundimiento al pagar: segundos y metros.
const SINK_TIME: float = 0.5
const SINK_DEPTH: float = 1.8
## Tinte de los cofres gratis (fuera de los cuatro colores de rareza).
const FREE_TINT: Color = Color(1.0, 0.93, 0.72)
## Aviso del cofre gratis: no hay precio, así que no hay variante "te faltan".
const FREE_PROMPT: String = "[E] Abrir cofre — gratis"

@onready var _lid_pivot: Node3D = get_node_or_null("Visual/LidPivot")

## Quien abrió el cofre (en co-op, el objeto le llega a ÉL).
var _opener: Node = null
## La luz del brillo, guardada para que make_free la recolore en vez de
## añadir otra.
var _glow_light: OmniLight3D = null


func _init() -> void:
	meta_stat_id = "chests_opened"
	complete_sound = &"chest_open"
	prompt_text = "[E] Abrir el cofre"
	marker_kind = &"chest"


func _ready() -> void:
	super()
	# `rarity` es la única fuente que leen precio, tinte, aviso y botín: la
	# rareza tirada se guarda ahí. Un cofre gratis tira al ABRIR (ver
	# _pop_reward), con la suerte de quien abre.
	if rarity.is_empty() and not free_open:
		var floor_index := UpgradePool.rarity_index(min_rarity)
		# La suerte inclina la rareza como en las cartas. Cuenta la suerte de
		# la party en el momento en que el cofre aparece.
		var row := UpgradePool.roll_rarity(luck_bonus + _party_luck(), floor_index)
		rarity = String(row.name)
	_tint_by_rarity()
	_refresh_price_prompt()


## Mejor suerte de la party al tirar (la party comparte los cofres del mapa,
## así que inclina el raider con más suerte).
func _party_luck() -> float:
	var best := 0.0
	for node: Node in get_tree().get_nodes_in_group("player"):
		var stats := PlayerStats.find_in(node)
		if stats != null:
			best = maxf(best, stats.luck)
	return best


## Vuelve gratis un cofre que YA pasó por _ready (el WorldDirector regala una
## parte de los cofres de inicio). Borra la rareza sellada para que se tire
## al abrir y repinta la caja.
func make_free() -> void:
	if free_open:
		return
	free_open = true
	rarity = ""
	_tint_by_rarity()
	_refresh_price_prompt()


func rarity_name() -> String:
	return rarity


func price() -> int:
	return 0 if free_open else RunState.chest_price(rarity)


func _physics_process(_delta: float) -> void:
	# El precio cambia con cada cofre abierto y los puntos con cada muerte:
	# el aviso se recalcula mientras alguien está en rango.
	if available and player_in_range:
		_refresh_price_prompt()


func _refresh_price_prompt() -> void:
	if free_open:
		set_prompt(FREE_PROMPT)
		return
	var cost := price()
	var purse := _points_of_nearest()
	var shown := UpgradePool.rarity_display(rarity)
	if purse >= cost:
		set_prompt("[E] Abrir cofre %s — %d pts" % [shown, cost])
	else:
		set_prompt("Te faltan %d puntos para abrir cofre %s" % [cost-purse, shown])


## Puntos del raider en pie MÁS CERCANO (el que va a apretar). _interact
## cobra a quien aprieta, así que el aviso cotiza su bolsa y no la del más
## rico del anillo.
func _points_of_nearest() -> int:
	var body := nearest_live_player()
	if body == null:
		return 0
	var purse: Variant = body.get("points")
	return int(purse) if purse != null else 0


func _interact(player: Node) -> void:
	if not free_open:
		var cost := price()
		if not player.has_method("spend_points") or not bool(player.call("spend_points", cost)):
			# No alcanza: un golpe sordo; el aviso ya dice por qué.
			Sfx.play(&"dodge")
			return
		# Solo los de pago encarecen los siguientes: los gratis caen de a
		# montones y sacarían a los de pago de la partida.
		RunState.register_chest_opened()
	_opener = player
	_emit_started()
	consume()
	var rest_y := position.y
	var tween := create_tween()
	tween.set_parallel(true)
	if _lid_pivot != null:
		tween.tween_property(_lid_pivot, "rotation:x", lid_open_angle, open_duration) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ap := get_node_or_null("Visual/ChestModel/AnimationPlayer") as AnimationPlayer
	if ap != null and ap.has_animation("open"):
		ap.play("open")
	tween.tween_property(self, "position:y", rest_y + OPEN_HOP_HEIGHT,
			open_duration * OPEN_HOP_UP_SHARE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "position:y", rest_y,
			open_duration * (1.0 - OPEN_HOP_UP_SHARE)) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_pop_reward)


func _pop_reward() -> void:
	# Durante el salto quien abrió puede haberse ido (un slot co-op que se
	# suelta, un respawn): ItemBag.find_in solo descarta null y un Object
	# liberado no es null.
	if _opener == null or not is_instance_valid(_opener):
		_emit_completed()
		_sink()
		return
	if free_open:
		# Se tira aquí: un cofre gratis no tiene piso ni rareza sellada, así
		# que decide la suerte de quien abre.
		var stats := PlayerStats.find_in(_opener)
		var luck := (stats.luck if stats != null else 0.0) + luck_bonus
		rarity = String(UpgradePool.roll_rarity(luck).name)
	var item_id := ItemCatalog.roll_id(rarity)
	var bag := ItemBag.find_in(_opener)
	if item_id.is_empty() or bag == null:
		push_warning("Chest: no item to grant (rarity %s)" % rarity)
		_emit_completed()
		_sink()
		return
	bag.add_item(item_id)
	var row := ItemCatalog.by_id(item_id)
	get_tree().call_group("boss_ui", "announce", "Cofre %s: %s — %s" % [
			UpgradePool.rarity_display(rarity), String(row.display_name),
			String(row.description)])
	# Línea de log para los soaks (verificar.sh cuenta "Chest opened:").
	print("Chest opened: %s -> %s (next prices x%.2f)%s" % [
			rarity, item_id, RunState.chest_price_multiplier,
			" (free)" if free_open else ""])
	_emit_completed()
	_sink()


## El cofre gastado se va del campo. consume() ya apagó `available`, que es
## lo que lee la baliza del WorldDirector, así que nadie lo retira dos veces.
func _sink() -> void:
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_interval(reward_linger)
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - SINK_DEPTH, SINK_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, SINK_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## Pinta el cofre con el color de su rareza (o el tinte gratis), con
## emisión para que se lea de noche.
func _tint_by_rarity() -> void:
	var color := FREE_TINT if free_open else ItemCatalog.rarity_color(rarity)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.3 if (not free_open and rarity == "Common") else 0.9
	for path: String in ["Visual/Band", "Visual/Lock", "Visual/LidPivot/LidTrim"]:
		var mesh_instance := get_node_or_null(path) as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = material

	var model := get_node_or_null("Visual/ChestModel")
	if model != null:
		var tex = load("res://assets/models/chest/Textures/colormap.png")
		var chest_mat := StandardMaterial3D.new()
		if tex:
			chest_mat.albedo_texture = tex
		chest_mat.emission_enabled = true
		chest_mat.emission = color
		chest_mat.emission_energy_multiplier = 0.2 if (not free_open and rarity == "Common") else (0.5 if rarity == "Rare" else 0.85)
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			mi.material_override = chest_mat
	if free_open or rarity == "Epic" or rarity == "Legendary":
		if _glow_light == null:
			_glow_light = OmniLight3D.new()
			_glow_light.light_energy = 1.6
			_glow_light.omni_range = 5.0
			_glow_light.position = Vector3.UP * 1.2
			add_child(_glow_light)
		_glow_light.light_color = color


## El cofre gratis tiene su propio marcador: en un mapa de 240 m, "vale la
## pena aunque no tengas puntos" es lo más útil que puede decir el ícono.
func map_marker_kind() -> StringName:
	return &"chest_free" if free_open else marker_kind
