class_name GreedShrine
extends Interactable
## Altar de codicia: un altar con calaveras que cobra una apuesta de HP. Al
## interactuar paga hp_cost_fraction de la vida MÁXIMA (por Health.pay: sin
## armadura, nunca letal, deja al menos min_hp_left) y tira el premio:
## gem_chance -> un anillo de gemas de XP valiosas, card_chance -> una carta
## gratis con piso de rareza, el resto -> solo una frase. El precio se cobra
## sobre el máximo, no sobre lo que queda: una fracción de la vida ACTUAL
## tiende a cero con la barra vacía y haría gratis entrar herido.
## Un solo uso, luego se apaga. outcome_for() es un clasificador puro para
## que un harness pueda probar la distribución.

@export_group("Peaje")
## Fracción de la vida máxima que cobra (0-1).
@export_range(0.0, 1.0) var hp_cost_fraction: float = 0.25
## Vida mínima que deja el pago, en HP.
@export var min_hp_left: float = 1.0
## Aviso cuando el raider no puede pagar el peaje completo.
@export var too_hurt_text: String = "No te alcanza la vida."
@export_group("Premio")
## Probabilidad (0-1) de pagar gemas.
@export_range(0.0, 1.0) var gem_chance: float = 0.6
## Probabilidad (0-1) de pagar una carta (el resto no paga nada).
@export_range(0.0, 1.0) var card_chance: float = 0.3
## Gemas que suelta el premio de gemas.
@export var gem_count: int = 12
## XP de cada gema.
@export var gem_value: int = 4
## Escena de gema (pasa por Pools).
@export var xp_gem_scene: PackedScene = preload("res://scenes/systems/XpGem.tscn")
## Título de la carta gratis.
@export var card_title: String = "El altar entrega un premio"
## Piso de rareza de la carta, como id en inglés (Rare = Raro o mejor).
@export var card_min_rarity: String = "Rare"
## Anuncio cuando no paga nada.
@export var flavor_text: String = "El altar queda complacido."


## La línea de oferta, guardada para volver a mostrarla tras un peaje
## rechazado (como el aviso de cancelar del Cráneo zumbante).
var _idle_prompt: String


func _ready() -> void:
	super()
	_idle_prompt = prompt_text


## Clasificador puro para una tirada uniforme en [0,1): "gems" | "card" |
## "nothing", repartido gem_chance / card_chance / resto.
func outcome_for(roll: float) -> String:
	if roll < gem_chance:
		return "gems"
	if roll < gem_chance + card_chance:
		return "card"
	return "nothing"


## Tras un peaje rechazado el altar sigue sin gastar: volver con más vida
## tiene que mostrar la oferta otra vez.
func _on_range_entered() -> void:
	if available:
		set_prompt(_idle_prompt)


func _interact(player: Node) -> void:
	var health := Health.find_in(player)
	if health == null:
		return
	var toll := health.max_hp * hp_cost_fraction
	# Health.pay recorta en min_hp_left en vez de matar, así que un pago corto
	# es el caso "demasiado herido": se rechaza y el altar queda sin gastar.
	if health.current_hp - min_hp_left < toll:
		Sfx.play(&"dodge")
		set_prompt(too_hurt_text)
		return
	_emit_started()
	health.pay(toll, min_hp_left)
	consume()
	dim_visuals()
	var outcome := outcome_for(randf())
	_grant(outcome, player)
	# Línea de log para los soaks.
	print("Greed shrine: paid %.0f HP -> %s" % [toll, outcome])
	_emit_completed()


func _grant(outcome: String, player: Node) -> void:
	match outcome:
		"gems":
			_burst_gems()
		"card":
			# La carta es para quien sangró: sin destinatario el selector rota
			# por la party.
			get_tree().call_group(
					"upgrade_ui", "open_bonus_pick", card_title, 0.0, card_min_rarity, player)
		_:
			get_tree().call_group("hud", "announce", flavor_text)


## Anillo de gemas valiosas alrededor del altar; el imán hace el resto.
func _burst_gems() -> void:
	if xp_gem_scene == null:
		return
	var placed := 0
	for i in gem_count:
		var gem := Pools.acquire_scene(xp_gem_scene) as XpGem
		# Una gema que el pool no entregó no anula las demás.
		if gem == null:
			continue
		gem.xp_value = gem_value
		var angle := TAU * float(i) / float(gem_count)
		gem.global_position = global_position + Vector3.UP * 0.8 \
				+ Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.1, 1.9)
		placed += 1
	if placed == 0:
		push_warning("GreedShrine: gem pool gave nothing; paying the flavor line instead")
		get_tree().call_group("hud", "announce", flavor_text)
