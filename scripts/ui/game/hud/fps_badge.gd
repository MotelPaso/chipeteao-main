class_name FpsBadge
extends Label
## Indicador de FPS para el jugador, arriba a la derecha. Se activa en
## Ajustes y se guarda en SaveData.show_fps; se consulta en vez de escuchar un
## cambio porque la opción se puede cambiar desde la pausa con este HUD vivo, y
## desde el título antes de que exista. No es la sonda de rendimiento
## (PerfProbe): esta es una opción del juego y solo muestra los FPS.
## El color del texto es el de la escena; el script agrega la pastilla.

@export_group("Insignia")
## Segundos entre lecturas.
@export var refresh_seconds: float = 0.25
## Texto del indicador; %d son los cuadros por segundo.
@export var text_format: String = "%d FPS"
## Color de fondo de la pastilla.
@export var background_color: Color = Color(UiTheme.TILE_BG, 0.85)
## Color del borde de la pastilla.
@export var border_color: Color = Color(0.3, 0.33, 0.4)

var _refresh_left: float = 0.0


func _ready() -> void:
	UiTheme.style_badge(self, get_theme_color(&"font_color"), background_color, border_color)


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	visible = SaveData.show_fps
	if visible:
		text = text_format % roundi(Engine.get_frames_per_second())
