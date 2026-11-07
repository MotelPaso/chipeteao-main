class_name SpringShrine
extends Interactable
## Manantial: un estanque de agua clara que, por un precio FIJO en puntos,
## cura por completo al raider y le da UN POWER-UP AL AZAR (nunca la
## estrella, que solo se encuentra rondando). Desaparece tras un uso.
##
## No caduca, y solo hay UNO vivo a la vez (el WorldDirector baja a cero el
## peso de su evento mientras el grupo `springs` tenga a alguien).

@export_group("Manantial")
## Precio base en puntos de partida (la lluvia dorada lo rebaja; ver current_price).
@export var price: int = 40
## Velocidad de las ondas del agua en X, en radianes por segundo (desafinada con la de Z para que no lata como un metrónomo).
@export var ripple_x_speed: float = 1.7
## Velocidad de las ondas del agua en Z, en radianes por segundo.
@export var ripple_z_speed: float = 1.3
## Cuánto se estira el agua en las ondas, como fracción de su tamaño.
@export var ripple_amount: float = 0.03
@export_group("Textos")
## Aviso con el precio; %d son los puntos (el manantial no usa prompt_text).
@export var price_prompt: String = "[E] Beber — %d pts (cura + power-up al azar)"
## Anuncio al beber.
@export var used_announce: String = "El manantial te restaura y te potencia"

var _time: float = 0.0
var _water: MeshInstance3D = null


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
				1.0 + sin(_time * ripple_x_speed) * ripple_amount, 1.0,
				1.0 + cos(_time * ripple_z_speed) * ripple_amount)
	if available and player_in_range:
		_refresh_price_prompt()


## Precio con el descuento de la lluvia dorada. El aviso se rearma en cada
## frame con un raider en el anillo, así que sigue al clima solo.
func current_price() -> int:
	return ceili(float(price) * RunState.price_discount)


func _refresh_price_prompt() -> void:
	set_prompt(price_prompt % current_price())


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
	get_tree().call_group("hud", "announce", used_announce)
	print("Spring used: heal + %s" % powerup_id)
	_emit_completed()
	sink_away()

