class_name DamagePopup
extends Label3D
## Texto de combate flotante del pool (números de daño, "!" de esquiva): sube
## mientras se desvanece y vuelve solo a Pools. Todo su aspecto (colores,
## tamaños de letra, texto de esquiva y movimiento) vive aquí y se edita en
## DamagePopup.tscn; Health solo dice qué pasó con show_hit().

## Qué le pasó al cuerpo: un golpe normal, un crítico o una esquiva.
enum Kind { DAMAGE, CRIT, DODGE }

@export_group("Colores")
## Color del número de un golpe normal.
@export var damage_color: Color = Color(1.0, 0.85, 0.25)
## Color del número de un golpe crítico.
@export var crit_color: Color = Color(1.0, 0.3, 0.15)
## Color del texto de esquiva.
@export var dodge_color: Color = Color(0.5, 0.88, 1.0)
## Color del contorno (su grosor es outline_size); se desvanece junto con el relleno.
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)

@export_group("Tamaños de letra")
## Tamaño de letra del número de un golpe normal, en píxeles.
@export var damage_font_size: int = 64
## Tamaño de letra del número de un golpe crítico, en píxeles.
@export var crit_font_size: int = 88
## Tamaño de letra del texto de esquiva, en píxeles.
@export var dodge_font_size: int = 64

@export_group("Textos")
## Texto que aparece cuando el jugador esquiva un golpe entero.
@export var dodge_text: String = "!"

@export_group("Movimiento")
## Altura sobre el origen del cuerpo donde aparece el número, en metros.
@export var spawn_lift: float = 2.0
## Desvío horizontal al azar, en metros, para que los números seguidos no se tapen.
@export var spawn_jitter: float = 0.3
## Metros que sube el número.
@export var rise_height: float = 1.2
## Segundos que tarda en subir.
@export var rise_time: float = 0.6
## Segundos que espera antes de empezar a desvanecerse.
@export var fade_delay: float = 0.25
## Segundos que tarda en desvanecerse.
@export var fade_time: float = 0.35

var _tween: Tween = null


## Contrato del pool: nada del vuelo anterior. show_hit() fija texto, tamaño
## y color; aquí vuelve lo que tocó el desvanecido. Los exports no se tocan:
## vienen de DamagePopup.tscn.
func pool_reset() -> void:
	_kill_tween()
	modulate = Color.WHITE
	outline_modulate = outline_color
	scale = Vector3.ONE
	rotation = Vector3.ZERO


## Muestra lo que le pasó al cuerpo que está en `body_position`: el número de
## `amount` (golpe normal o crítico) o el texto de esquiva. El nodo vuelve
## solo al pool al terminar.
func show_hit(kind: Kind, body_position: Vector3, amount: float = 0.0) -> void:
	# Dos tiradas del RNG global, primero X y después Z: los soaks con semilla
	# dependen de este orden.
	var at := body_position + Vector3(randf_range(-spawn_jitter, spawn_jitter),
			spawn_lift, randf_range(-spawn_jitter, spawn_jitter))
	match kind:
		Kind.DODGE:
			_play(dodge_text, dodge_font_size, dodge_color, at)
		Kind.CRIT:
			_play(str(roundi(amount)), crit_font_size, crit_color, at)
		_:
			_play(str(roundi(amount)), damage_font_size, damage_color, at)


func _play(popup_text: String, popup_font_size: int, color: Color, at: Vector3) -> void:
	text = popup_text
	font_size = popup_font_size
	modulate = color
	outline_modulate = outline_color
	global_position = at
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "position:y", position.y + rise_height, rise_time)
	_tween.tween_property(self, "modulate:a", 0.0, fade_time).set_delay(fade_delay)
	# El contorno se desvanece con el relleno; si no, su silueta negra queda
	# flotando hasta el final del tween.
	_tween.tween_property(self, "outline_modulate:a", 0.0, fade_time).set_delay(fade_delay)
	_tween.chain().tween_callback(_on_popup_done)


func _on_popup_done() -> void:
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
