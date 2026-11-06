class_name RevivePrompt
extends Label3D
## Cartel flotante sobre un raider caído en co-op: pide ayuda y muestra el
## progreso del rescate. Tamaño de letra, contorno y altura son propiedades
## de este Label3D en Player.tscn (Revive > RevivePrompt); textos y colores
## son los exports de abajo. PlayerRevive lo abre, lo actualiza y lo cierra.

## Centinela de "el cartel nunca se pintó", distinto de "nadie lo revive" (-1).
const PCT_UNSET: int = -2

@export_group("Textos")
## Texto mientras nadie lo está reviviendo.
@export var down_text: String = "CAÍDO — mantén [Interactuar] cerca"
## Texto mientras un compañero lo revive; el porcentaje se agrega al final ("Reviviendo... 42%").
@export var reviving_text: String = "Reviviendo..."

@export_group("Colores")
## Color del cartel mientras nadie lo revive.
@export var down_color: Color = Color(1.0, 0.42, 0.35)
## Color del cartel mientras un compañero lo revive.
@export var reviving_color: Color = Color(0.5, 0.95, 0.6)

## Último porcentaje entero pintado (-1 = nadie lo revive).
var _last_pct: int = PCT_UNSET


## Muestra el cartel en el estado "caído".
func open() -> void:
	visible = true
	_last_pct = PCT_UNSET
	refresh(false, 0.0)


## Pinta el estado actual; `progress` va de 0 a 1. El texto solo cambia por
## porcentaje entero (~33 pasos en todo el rescate), así los demás ticks no
## arman el String.
func refresh(rescuing: bool, progress: float) -> void:
	var pct := roundi(progress * 100.0) if rescuing else -1
	if pct == _last_pct:
		return
	_last_pct = pct
	if rescuing:
		text = "%s %d%%" % [reviving_text, pct]
		modulate = reviving_color
	else:
		text = down_text
		modulate = down_color


func close() -> void:
	visible = false
