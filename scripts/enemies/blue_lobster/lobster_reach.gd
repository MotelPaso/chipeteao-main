class_name LobsterReach
extends Node
## Ataques a la medida del raider (nodo Reach de BlueLobster.tscn). Al empezar
## cada ataque la langosta mide la velocidad del raider al que apunta, y con
## ella crecen las distancias y velocidades del ataque (discos, carriles,
## alcance, saltos, túneles y ondas). Los tiempos no cambian: un raider más
## rápido tiene que recorrer más en el mismo aviso, y esquivar le cuesta lo
## mismo que a uno sin mejoras. Los valores de cada ataque en BlueLobster.tscn
## son los de ese raider sin mejoras; los lleva a su medida
## LobsterMove.scaled().
## Los saltos extra no cuentan: el golpe llega antes de que un segundo salto
## suba más que el primero, y esquivar saltando ya cuesta lo mismo con ellos.

@export_group("Velocidad")
## Parte (0-1) de la velocidad extra del raider que siguen los ataques. Con 1, contra un raider un 30 % más rápido los discos, carriles y ondas son un 30 % más grandes y más rápidos; con 0 no cambian.
@export_range(0.0, 1.0) var speed_follow: float = 1.0
## Tope de ese crecimiento, en veces el tamaño base (2 = el doble como mucho).
@export var max_growth: float = 2.0


## Veces que crecen las distancias y velocidades de un ataque contra
## `target`: 1 sin mejoras de velocidad (o si no es un raider). Cuenta todo
## lo que sube su velocidad, también los poderes que duran un rato.
func mobility_of(target: Node3D) -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	var stats := PlayerStats.find_in(target)
	if stats == null:
		return 1.0
	var extra := maxf(stats.move_speed_multiplier - 1.0, 0.0) * speed_follow
	return clampf(1.0 + extra, 1.0, maxf(max_growth, 1.0))
