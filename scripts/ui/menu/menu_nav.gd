class_name MenuNav
extends RefCounted
## Navegación entre las pantallas de menú (menú principal, selector de
## personaje, Misiones, Colección, Armería). El mapa de fondo sigue vivo entre
## ellas (autoload MenuBackdrop), así que el cambio no funde a negro: el
## contenido de la pantalla que se va se desliza y se apaga rápido, cambia la
## escena y el contenido nuevo entra desde el lado contrario.
##
## La dirección cuenta dónde estás: entrar a una sección empuja hacia la
## izquierda (FORWARD) y volver empuja hacia la derecha (BACK), como pasar y
## devolver una página.
##
## Uso, en la pantalla que se va:   MenuNav.go(%Layout, ScenePaths.QUEST_LOG)
##      en el _ready de la que llega: MenuNav.arrive(%Layout)
## Es estático y nunca va en una escena: edita los valores aquí.

enum Direction { FORWARD = 1, BACK = -1 }

## Salida del contenido: duración (segundos) y píxeles que se desliza. Más
## corta y más simple que la entrada: quien sale ya decidió irse.
const EXIT_TIME := 0.11
const EXIT_SHIFT := 40.0
## Entrada del contenido: duración (segundos) y píxeles desde los que llega.
const ENTER_TIME := 0.24
const ENTER_SHIFT := 64.0
## Si la pantalla de destino nunca avisa que llegó, la navegación se
## desbloquea sola tras este tiempo (milisegundos).
const BUSY_TIMEOUT_MSEC := 1500

## Dirección del cambio en curso: la pantalla que llega entra según ella.
static var _direction: Direction = Direction.FORWARD
static var _busy_since: int = -1


## Saca `content` de pantalla y cambia a `scene_path`. Devuelve false si ya
## hay un cambio en curso (la petición se descarta: gana la primera).
static func go(content: Control, scene_path: String,
		direction: Direction = Direction.FORWARD) -> bool:
	if is_busy() or ScreenFade.is_busy():
		return false
	_busy_since = Time.get_ticks_msec()
	_direction = direction
	var tree := content.get_tree()
	var tween := content.create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	# Ease-out también al salir: el movimiento empieza en el mismo frame del
	# botón, así el juego se siente atento (un ease-in parte lento).
	tween.tween_property(content, "modulate:a", 0.0, EXIT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(shift.bind(content), Vector2.ZERO,
			Vector2(-EXIT_SHIFT * float(direction), 0.0), EXIT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(tree.change_scene_to_file.bind(scene_path))
	return true


## La pantalla nueva avisa que llegó: desbloquea la navegación y hace entrar
## `content` desde el lado que corresponde. Devuelve true si la pantalla llegó
## desde otro menú. Regla: UNA entrada por pantalla. Quien recibe true y
## deslizó su contenido no escalona además a sus hijos; una pantalla que
## prefiere su propia entrada (el selector, con sus cartas) pasa slide = false.
## La primera pantalla del juego (sin cambio previo) devuelve false.
static func arrive(content: Control, slide: bool = true) -> bool:
	var came_from_menu := _busy_since >= 0
	_busy_since = -1
	if not came_from_menu or not slide:
		return came_from_menu
	var from := Vector2(ENTER_SHIFT * float(_direction), 0.0)
	content.modulate.a = 0.0
	shift(from, content)
	var tween := content.create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	# Entrada: ease-out fuerte. Llega rápido y frena suave.
	tween.tween_property(content, "modulate:a", 1.0, ENTER_TIME * 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(shift.bind(content), from, Vector2.ZERO, ENTER_TIME) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	return true


## Desplaza un Control anclado `offset` píxeles desde su lugar de reposo
## moviendo sus cuatro offsets a la vez. Asignar `position` antes del primer
## layout rompería sus anclas (el control quedaría con su tamaño mínimo); esto
## funciona en cualquier momento. El valor va primero para usarlo con
## tween_method(MenuNav.shift.bind(control), desde, hasta, tiempo).
static func shift(offset: Vector2, control: Control) -> void:
	if not is_instance_valid(control):
		return
	if not control.has_meta(&"nav_rest"):
		control.set_meta(&"nav_rest", Rect2(control.offset_left, control.offset_top,
				control.offset_right, control.offset_bottom))
	var rest: Rect2 = control.get_meta(&"nav_rest")
	control.offset_left = rest.position.x + offset.x
	control.offset_right = rest.size.x + offset.x
	control.offset_top = rest.position.y + offset.y
	control.offset_bottom = rest.size.y + offset.y


static func is_busy() -> bool:
	return _busy_since >= 0 \
			and Time.get_ticks_msec() - _busy_since < BUSY_TIMEOUT_MSEC
