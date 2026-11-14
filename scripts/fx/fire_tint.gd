class_name FireTint
extends RefCounted
## El color del fuego de Mythos, para todo lo que arde a la vez: 0 es su
## fuego de siempre y 1 el de su segunda fase. Los shaders de fuego lo leen
## del uniform global `fire_ascend` (Ajustes del proyecto > Shader Globals) y
## mezclan hacia sus colores del grupo «Renacido»; lo que se pinta desde un
## script (el aviso de un jefe, el brillo del suelo de un tornado) lo lee
## con amount(). Lo escribe HellTransformation, que es quien cambia el mapa
## de color, y lo deja en 0 cuando empieza otra llegada o la arena se va.

const GLOBAL_NAME := &"fire_ascend"

static var _amount: float = 0.0


## Deja el fuego a `value` (0-1) del camino hacia el de la segunda fase.
static func set_amount(value: float) -> void:
	_amount = clampf(value, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set(GLOBAL_NAME, _amount)


static func amount() -> float:
	return _amount
