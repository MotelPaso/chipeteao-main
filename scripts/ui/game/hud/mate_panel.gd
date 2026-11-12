class_name MatePanel
extends VBoxContainer
## Columna de compañeros (solo co-op), arriba a la izquierda: una fila
## (MateRow.tscn) por cada jugador extra. El HUD agrega las filas al unir el
## grupo y le pasa su rampa de color de vida en hp_color, así la barra
## principal y las de los compañeros usan los mismos colores.

const ROW_SCENE := preload("res://scenes/ui/hud/MateRow.tscn")

@export_group("Compañeros")
## Segundos entre consultas del conteo de power-ups de cada compañero.
@export var refresh_seconds: float = 0.2

## Color de una barra de vida según (vida actual, vida máxima); lo asigna el HUD.
var hp_color: Callable
var _refresh_left: float = 0.0


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	for child: Node in get_children():
		var row := child as MateRow
		if row != null:
			row.refresh_powerups()


## Agrega la fila del compañero en `slot`, unida a su vida y a su billetera.
func add_mate(slot: int, health: Health, body: Node) -> void:
	var row: MateRow = ROW_SCENE.instantiate()
	add_child(row)
	row.bind(slot, health, body, hp_color)
