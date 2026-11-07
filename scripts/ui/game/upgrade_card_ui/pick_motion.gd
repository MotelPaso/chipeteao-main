class_name UpgradePickMotion
extends Node
## Tiempos y movimiento del selector de cartas (nodo Motion de
## UpgradeCardUI.tscn): la entrada del fondo, el título y las cartas, el cambio
## rápido entre elecciones seguidas y el golpe de la carta elegida. Hereda el
## process_mode ALWAYS del selector e ignora la escala de tiempo, así que ni la
## pausa ni el hit-stop lo frenan.

@export_group("Apertura")
## Segundos entre pausar el árbol y mostrar las cartas: un respiro para que se
## lea el pulso de subida de nivel. Mantenlo bajo ~0.25.
@export var reveal_delay: float = 0.2
## Segundos que tarda en subir el fondo oscuro.
@export var dim_fade_time: float = 0.15
## Escala desde la que crece el título al abrir.
@export var title_start_scale: float = 0.9
## Segundos que tarda el título en llegar a su tamaño, con un rebote al final.
@export var title_grow_time: float = 0.22

@export_group("Reparto")
## Escala desde la que crece cada carta al repartirse.
@export var deal_start_scale: float = 0.8
## Segundos que tarda cada carta en llegar a su tamaño, con un rebote al final.
@export var deal_time: float = 0.22
## Segundos entre la entrada de una carta y la siguiente.
@export var deal_stagger: float = 0.06
## Parte del tiempo de entrada en la que la carta pasa de invisible a opaca (0-1).
@export var deal_fade_share: float = 0.7

@export_group("Reparto encadenado")
## Escala inicial de cada carta cuando la oferta cambia con el selector ya
## abierto (elecciones seguidas).
@export var quick_deal_start_scale: float = 0.92
## Segundos que tarda cada carta en llegar a su tamaño en ese cambio rápido.
@export var quick_deal_time: float = 0.14
## Segundos entre una carta y la siguiente en ese cambio rápido.
@export var quick_deal_stagger: float = 0.03

@export_group("Elección")
## Segundos del golpe de la carta elegida y la caída de las demás, antes de
## servir la siguiente elección.
@export var pick_time: float = 0.16
## Escala a la que sube la carta elegida.
@export var pick_scale: float = 1.12
## Escala a la que bajan las cartas no elegidas.
@export var loser_scale: float = 0.9
## Opacidad final de las cartas no elegidas (0-1).
@export var loser_alpha: float = 0.2

var _deal_tween: Tween = null
var _pick_tween: Tween = null


## Entrada de las cartas: el fondo oscuro sube y cada carta visible crece desde
## una escala menor, una tras otra y con un rebote al final (quick = el cambio
## en el lugar entre elecciones encadenadas: el fondo ya está arriba).
## Idempotente: al reiniciar mata el reparto anterior.
func deal(dim: CanvasItem, title: Control, cards: Array[UpgradeCard], quick: bool) -> void:
	if _deal_tween != null and _deal_tween.is_valid():
		_deal_tween.kill()
	_deal_tween = create_tween().set_parallel()
	_deal_tween.set_ignore_time_scale(true)
	if not quick:
		dim.modulate.a = 0.0
		_deal_tween.tween_property(dim, "modulate:a", 1.0, dim_fade_time)
		title.pivot_offset = title.size * 0.5
		title.scale = Vector2.ONE * title_start_scale
		_deal_tween.tween_property(title, "scale", Vector2.ONE, title_grow_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		dim.modulate.a = 1.0
	var start_scale := quick_deal_start_scale if quick else deal_start_scale
	var duration := quick_deal_time if quick else deal_time
	var stagger := quick_deal_stagger if quick else deal_stagger
	for i in cards.size():
		var card := cards[i]
		if not card.visible:
			continue
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2.ONE * start_scale
		card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var delay := stagger * i
		_deal_tween.tween_property(card, "modulate:a", 1.0, duration * deal_fade_share) \
				.set_delay(delay)
		_deal_tween.tween_property(card, "scale", Vector2.ONE, duration) \
				.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## La carta `index` da un golpe hacia arriba y las demás caen y se apagan;
## `on_done` corre cuando termina el gesto.
func pick(cards: Array[UpgradeCard], index: int, on_done: Callable) -> void:
	if _pick_tween != null and _pick_tween.is_valid():
		_pick_tween.kill()
	_pick_tween = create_tween().set_parallel()
	_pick_tween.set_ignore_time_scale(true)
	for i in cards.size():
		var card := cards[i]
		if not card.visible:
			continue
		# BaseButton emite button_up antes que pressed, así que el tween de hover
		# de attach_motion sigue escribiendo `scale` cuando empieza el golpe. Se
		# mata, o los dos pelean por la propiedad y el gesto tartamudea.
		UiTheme.kill_meta_tween(card, &"ui_motion_tween")
		card.pivot_offset = card.size * 0.5
		if i == index:
			_pick_tween.tween_property(card, "scale", Vector2.ONE * pick_scale,
					pick_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_pick_tween.tween_property(card, "scale", Vector2.ONE * loser_scale, pick_time)
			_pick_tween.tween_property(card, "modulate:a", loser_alpha, pick_time)
	_pick_tween.chain().tween_callback(on_done)
