class_name Chest
extends Interactable
## Cofre del tesoro: paga UN objeto de ItemCatalog (nunca cartas ni armas).
##
## Todos los cofres son iguales: no tienen rareza a la vista. La rareza del
## objeto se tira AL ABRIRSE, con los pesos de rareza de las cartas,
## inclinados por la suerte de quien abre más luck_bonus y con piso en
## min_rarity.
##
## Los de pago cuestan RunState.chest_price() (un precio base × un
## multiplicador global que crece con cada cofre de pago que se abre). Los
## GRATIS (jefes, shinies, parte de los cofres de inicio, el pacto del
## cofre) no cuestan nada, NO encarecen los de pago y llevan su propio tinte.
##
## Un solo uso: al pagar se hunde y se libera.

## Escena que instancia spawn_free. Se carga al llamarla: un script no puede
## precargar la escena que lo usa.
const SCENE_PATH: String = "res://scenes/world/chests/Chest.tscn"

@export_group("Cofre")
## Cofre gratis: sin precio y no encarece los de pago (no se llama `free`: es Object.free()).
@export var free_open: bool = false
## Suerte extra que inclina la tirada de rareza del objeto al abrir.
@export var luck_bonus: float = 0.0
## Piso de rareza del objeto, como id en inglés ("" = sin piso).
@export var min_rarity: String = ""
@export_group("Apertura")
## Segundos que dura el salto de apertura; el objeto se entrega al terminar.
@export var open_duration: float = 0.45
## Altura del salto al abrir, en metros.
@export var open_hop_height: float = 0.3
## Fracción de open_duration que dura la subida (0-1); el resto es el rebote de bajada.
@export_range(0.0, 1.0) var open_hop_up_share: float = 0.4
## Segundos que sigue vivo el cofre tras pagar; el hundimiento (sink_duration) empieza de inmediato.
@export var reward_linger: float = 1.4
@export_group("Cofre perdido")
## Segundos que tarda en encogerse si nadie lo abre antes de que se apague su baliza (cofre de suministros).
@export var lost_sink_duration: float = 0.4
## Metros que baja al perderse (0 = solo se encoge).
@export var lost_sink_depth: float = 0.0
@export_group("Brillo")
## Tinte de los cofres de pago.
@export var paid_tint: Color = Color(0.85, 0.65, 0.35)
## Energía de emisión de un cofre de pago.
@export var paid_glow_energy: float = 0.3
## Tinte de los cofres gratis (enciende además la luz GlowLight de la escena).
@export var free_tint: Color = Color(1.0, 0.93, 0.72)
## Energía de emisión de un cofre gratis.
@export var free_glow_energy: float = 0.85
## Textura del modelo que usa el material con brillo; se carga al aparecer.
@export_file("*.png") var model_texture_path: String = "res://assets/models/chest/Textures/colormap.png"
@export_group("Textos")
## Aviso del cofre de pago cuando alcanza: %d es el precio (el cofre no usa prompt_text).
@export var paid_prompt: String = "[E] Abrir cofre — %d pts"
## Aviso cuando no alcanza: %d son los puntos que faltan.
@export var short_prompt: String = "Te faltan %d puntos para abrir el cofre"
## Aviso del cofre gratis (no hay precio, así que no tiene variante "te faltan").
@export var free_prompt: String = "[E] Abrir cofre — gratis"
## Cartel al abrir (grupo "boss_ui"): rareza, nombre y descripción del objeto (%s cada uno).
@export var opened_announce: String = "Cofre %s: %s — %s"

## Quien abrió el cofre (en co-op, el objeto le llega a ÉL).
var _opener: Node = null
## Rareza del objeto que salió, tirada al abrir.
var _rarity: String = ""

@onready var _glow_light: OmniLight3D = $Visual/GlowLight


func _ready() -> void:
	super()
	_apply_tint()
	_refresh_price_prompt()


func _physics_process(_delta: float) -> void:
	# El precio cambia con cada cofre abierto y los puntos con cada muerte:
	# el aviso se recalcula mientras alguien está en rango.
	if available and player_in_range:
		_refresh_price_prompt()


## Deja un cofre GRATIS en `at`, colgado de la arena (RunRoot.stage_parent)
## y no de quien lo suelta, para que siga ahí aunque ese nodo se libere.
## `bonus_luck` va a luck_bonus y `floor_rarity` (si no está vacío) a
## min_rarity antes de que entre al árbol. Sin arena cuelga de la escena
## actual; devuelve null solo sin árbol o si la escena no es un Chest.
## Lo usan los altares, el bloque de la suerte y EnemyLoot (cofre shiny y
## anillo del jefe).
static func spawn_free(tree: SceneTree, at: Vector3, bonus_luck: float = 0.0,
		floor_rarity: String = "") -> Chest:
	var parent := RunRoot.stage_parent(tree)
	if parent == null:
		return null
	var node := (load(SCENE_PATH) as PackedScene).instantiate()
	var chest := node as Chest
	if chest == null:
		node.free()
		push_warning("Chest: %s root is not a Chest." % SCENE_PATH)
		return null
	if not floor_rarity.is_empty():
		chest.min_rarity = floor_rarity
	chest.free_open = true
	chest.luck_bonus = bonus_luck
	parent.add_child(chest)
	chest.global_position = at
	return chest


## Vuelve gratis un cofre que YA pasó por _ready (el WorldDirector regala una
## parte de los cofres de inicio) y repinta la caja.
func make_free() -> void:
	if free_open:
		return
	free_open = true
	_apply_tint()
	_refresh_price_prompt()


## Hunde el cofre de suministros que nadie abrió antes de que se apagara su
## baliza (lo llama el WorldDirector), con los valores de «Cofre perdido».
func sink_lost() -> void:
	sink_away(0.0, lost_sink_duration, lost_sink_depth)


func price() -> int:
	return 0 if free_open else RunState.chest_price()


## El cofre gratis tiene su propio marcador: en un mapa de 240 m, "vale la
## pena aunque no tengas puntos" es lo más útil que puede decir el ícono.
func map_marker_kind() -> StringName:
	return &"chest_free" if free_open else marker_kind


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
	var ap := get_node_or_null("Visual/ChestModel/AnimationPlayer") as AnimationPlayer
	if ap != null and ap.has_animation("open"):
		ap.play("open")
	tween.tween_property(self, "position:y", rest_y + open_hop_height,
			open_duration * open_hop_up_share) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", rest_y,
			open_duration * (1.0 - open_hop_up_share)) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_pop_reward)


func _pop_reward() -> void:
	# Durante el salto quien abrió puede haberse ido (un slot co-op que se
	# suelta, un respawn): ItemBag.find_in solo descarta null y un Object
	# liberado no es null.
	if _opener == null or not is_instance_valid(_opener):
		_emit_completed()
		sink_away(reward_linger)
		return
	# Decide la suerte de quien abre más luck_bonus, con piso en min_rarity.
	var stats := PlayerStats.find_in(_opener)
	var luck := (stats.luck if stats != null else 0.0) + luck_bonus
	_rarity = String(UpgradePool.roll_rarity(luck, UpgradePool.rarity_index(min_rarity)).name)
	var item_id := ItemCatalog.roll_id(_rarity)
	var bag := ItemBag.find_in(_opener)
	if item_id.is_empty() or bag == null:
		push_warning("Chest: no item to grant (rarity %s)" % _rarity)
		_emit_completed()
		sink_away(reward_linger)
		return
	bag.add_item(item_id)
	var row := ItemCatalog.by_id(item_id)
	get_tree().call_group("boss_ui", "announce", opened_announce % [
			UpgradePool.rarity_display(_rarity), String(row.display_name),
			String(row.description)])
	# Línea de log para los soaks (verificar.sh cuenta "Chest opened:").
	print("Chest opened: %s -> %s (next prices x%.2f)%s" % [
			_rarity, item_id, RunState.chest_price_multiplier,
			" (free)" if free_open else ""])
	_emit_completed()
	# consume() ya apagó `available`, que es lo que lee la baliza del
	# WorldDirector: nadie retira este cofre por segunda vez.
	sink_away(reward_linger)


func _refresh_price_prompt() -> void:
	if free_open:
		set_prompt(free_prompt)
		return
	var cost := price()
	var purse := _points_of_nearest()
	if purse >= cost:
		set_prompt(paid_prompt % cost)
	else:
		set_prompt(short_prompt % (cost - purse))


## Puntos del raider en pie MÁS CERCANO (el que va a apretar). _interact
## cobra a quien aprieta, así que el aviso cotiza su bolsa y no la del más
## rico del anillo.
func _points_of_nearest() -> int:
	var body := nearest_live_player()
	if body == null:
		return 0
	var purse: Variant = body.get("points")
	return int(purse) if purse != null else 0


## Pinta el modelo con paid_tint o free_tint, con emisión para que se lea de
## noche, y enciende GlowLight en los cofres gratis.
func _apply_tint() -> void:
	var color := free_tint if free_open else paid_tint
	var model := get_node_or_null("Visual/ChestModel")
	if model != null:
		var chest_mat := StandardMaterial3D.new()
		var texture := load(model_texture_path) as Texture2D
		if texture != null:
			chest_mat.albedo_texture = texture
		chest_mat.emission_enabled = true
		chest_mat.emission = color
		chest_mat.emission_energy_multiplier = free_glow_energy if free_open else paid_glow_energy
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			mi.material_override = chest_mat
	_glow_light.visible = free_open
	if free_open:
		_glow_light.light_color = color
