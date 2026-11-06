class_name SpringShrine
extends Interactable
## Manantial: un estanque de agua clara que, por un precio FIJO en puntos,
## cura por completo al raider y le da UN POWER-UP AL AZAR (nunca la
## estrella, que solo se encuentra rondando). Desaparece tras un uso.
##
## No caduca, y solo hay UNO vivo a la vez (el WorldDirector baja a cero el
## peso de su evento mientras el grupo `springs` tenga a alguien).

## Precio base en puntos de partida (la lluvia dorada lo rebaja; ver current_price).
@export var price: int = 40

## Ondas del agua: dos frecuencias desafinadas (Hz) y su amplitud, para que
## no lata como un metrónomo.
const RIPPLE_X_HZ: float = 1.7
const RIPPLE_Z_HZ: float = 1.3
const RIPPLE_AMOUNT: float = 0.03

var _time: float = 0.0
var _water: MeshInstance3D = null
## Lo enciende _dry_up para que dos salidas el mismo frame no apilen dos
## tweens ni liberen el nodo dos veces.
var _drying: bool = false


func _init() -> void:
	meta_stat_id = "shrines_used"
	marker_kind = &"spring"
	complete_sound = &"heal"


func _ready() -> void:
	super()
	# El director cuenta los manantiales vivos por este grupo para dejar uno
	# solo; RunRoot los libera con el resto de la etapa.
	add_to_group(&"springs")
	_water = get_node_or_null("Visual/Water") as MeshInstance3D
	_refresh_price_prompt()


func _physics_process(delta: float) -> void:
	_time += delta
	if _water != null:
		_water.scale = Vector3(
				1.0 + sin(_time * RIPPLE_X_HZ) * RIPPLE_AMOUNT, 1.0,
				1.0 + cos(_time * RIPPLE_Z_HZ) * RIPPLE_AMOUNT)
	if available and player_in_range:
		_refresh_price_prompt()


## Precio con el descuento de la lluvia dorada. El aviso se rearma en cada
## frame con un raider en el anillo, así que sigue al clima solo.
func current_price() -> int:
	return ceili(float(price) * RunState.price_discount)


func _refresh_price_prompt() -> void:
	set_prompt("[E] Beber — %d pts (cura + power-up al azar)" % current_price())


func _interact(player: Node) -> void:
	if not player.has_method("spend_points") \
			or not bool(player.call("spend_points", current_price())):
		Sfx.play(&"dodge")
		return
	_emit_started()
	consume()
	var health := Health.find_in(player)
	if health != null:
		health.heal_full()
	# Un power-up al azar, nunca la estrella. PowerUps se encarga del aviso,
	# el anuncio y la línea "Power-up picked:".
	var powerup_id := PowerUpCatalog.roll_id(true)
	var powerups := PowerUps.find_in(player)
	if powerups != null:
		powerups.apply(powerup_id)
	get_tree().call_group("hud", "announce", "El manantial te restaura y te potencia")
	print("Spring used: heal + %s" % powerup_id)
	_emit_completed()
	_dry_up()


## Se encoge y se libera. El guardia evita que dos raiders bebiendo el mismo
## frame apilen dos tweens y liberen el nodo dos veces.
func _dry_up() -> void:
	if _drying:
		return
	_drying = true
	available = false
	_refresh_prompt()
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
