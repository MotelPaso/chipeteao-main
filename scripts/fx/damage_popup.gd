class_name DamagePopup
extends Label3D
## Texto de combate flotante del pool (números de daño, "!" de esquiva): sube
## mientras se desvanece y se devuelve solo a Pools. Los colores viven aquí;
## el texto y el tamaño de letra los pasa Health._spawn_popup, su único llamador.

## Movimiento del número: metros que sube, segundos que tarda, y el retraso y
## la duración del desvanecido.
const RISE_HEIGHT: float = 1.2
const RISE_TIME: float = 0.6
const FADE_DELAY: float = 0.25
const FADE_TIME: float = 0.35
## Label3D dibuja el contorno como su propia superficie con su propio color:
## el contorno de 16 px de la escena se desvanece (y se restaura) junto con
## `modulate`.
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)

const damage_text_color: Color = Color(1.0, 0.85, 0.25)
const damage_text_crit: Color = Color(1.0, 0.3, 0.15)
const dodge_popup_color := Color(0.5, 0.88, 1.0)

var _tween: Tween = null


## Contrato del pool: nada del vuelo anterior (ni movimiento ni aspecto).
## show_popup fija texto, tamaño y color; lo que tocó el desvanecido vuelve
## aquí, o el siguiente número hereda un contorno transparente.
func pool_reset() -> void:
	_kill_tween()
	modulate = Color.WHITE
	outline_modulate = OUTLINE_COLOR
	scale = Vector3.ONE
	rotation = Vector3.ZERO


## Configura y reproduce un número; el nodo se libera solo al terminar.
func show_popup(popup_text: String, popup_font_size: int, is_crit: bool, at: Vector3, is_dodge:bool = false) -> void:
	text = popup_text
	font_size = popup_font_size
	modulate = dodge_popup_color if is_dodge else damage_text_crit if is_crit else damage_text_color
	outline_modulate = OUTLINE_COLOR
	global_position = at
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "position:y", position.y + RISE_HEIGHT, RISE_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME).set_delay(FADE_DELAY)
	# El contorno se desvanece con el relleno; si no, su silueta negra queda
	# flotando hasta el final del tween.
	_tween.tween_property(self, "outline_modulate:a", 0.0, FADE_TIME).set_delay(FADE_DELAY)
	_tween.chain().tween_callback(_on_popup_done)


func _on_popup_done() -> void:
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
