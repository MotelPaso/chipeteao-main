class_name LobsterFeel
extends CanvasLayer
## Lo que se SIENTE de los golpes de la Langosta Azul (nodo Feel de
## BlueLobster.tscn): la sacudida de cámara y la pausa de impacto de cada
## golpe según su tamaño, el fogonazo de los más grandes (nodo Flash) y la
## VIÑETA DE PELIGRO que oscurece los bordes de la pantalla mientras carga un
## golpe grande. Los ataques dicen qué pasó (shock con un tamaño y un lugar,
## dread con cuánto falta); cuánto tiembla y cómo se ve vive aquí y en el
## material del nodo Vignette.

## Tamaño de un golpe.
enum Shock { LIGHT, HEAVY, CRUSHING }

@export_group("Golpe liviano")
## Temblor de cámara (0-1) de un golpe liviano: un pinzazo o un Coletazo que no le dio a nadie.
@export var light_shake: float = 0.2
## Segundos que dura ese temblor.
@export var light_shake_seconds: float = 0.25

@export_group("Golpe fuerte")
## Temblor de cámara (0-1) de un golpe fuerte: un golpe que le dio a alguien, cada salida de la Emboscada, la réplica del Salto.
@export var heavy_shake: float = 0.55
## Segundos que dura ese temblor.
@export var heavy_shake_seconds: float = 0.55
## Escala de tiempo (0-1) de la pausa de impacto de un golpe fuerte.
@export_range(0.05, 1.0) var heavy_stop_scale: float = 0.18
## Segundos reales que dura esa pausa (0 = sin pausa).
@export var heavy_stop_seconds: float = 0.06

@export_group("Golpe demoledor")
## Temblor de cámara (0-1) del golpe más grande: la caída del Salto, el remate de las Tenazas, la última salida de la Emboscada.
@export var crushing_shake: float = 0.9
## Segundos que dura ese temblor.
@export var crushing_shake_seconds: float = 0.85
## Escala de tiempo (0-1) de su pausa de impacto.
@export_range(0.05, 1.0) var crushing_stop_scale: float = 0.1
## Segundos reales que dura esa pausa (0 = sin pausa).
@export var crushing_stop_seconds: float = 0.1
## Opacidad (0-1) del fogonazo a pantalla completa de un golpe demoledor (0 = sin fogonazo).
@export_range(0.0, 1.0) var crushing_flash: float = 0.2
## Segundos que tarda ese fogonazo en apagarse.
@export var crushing_flash_seconds: float = 0.22
## Color del fogonazo.
@export var flash_color: Color = Color(0.84, 0.96, 1.0)

@export_group("Distancia")
## Metros al raider más cercano hasta los que el golpe se siente entero.
@export var full_within: float = 8.0
## Metros desde los que se siente lo mínimo.
@export var faint_beyond: float = 36.0
## Parte del temblor (0-1) que queda a esa distancia.
@export_range(0.0, 1.0) var faint_share: float = 0.3

@export_group("Viñeta de peligro")
## Opacidad máxima (0-1) de la viñeta.
@export_range(0.0, 1.0) var dread_opacity: float = 0.72
## Parte de esa opacidad (0-1) que late en vez de quedarse fija.
@export_range(0.0, 1.0) var dread_pulse: float = 0.3
## Segundos de un latido.
@export var dread_pulse_seconds: float = 0.5
## Rapidez con que la viñeta aparece y se va (por segundo).
@export var dread_speed: float = 6.0

## Lo que pidieron los ataques en este frame y lo que se ve ahora (0-1).
var _wanted: float = 0.0
var _level: float = 0.0
var _clock: float = 0.0
var _flash_tween: Tween = null

@onready var _vignette: ColorRect = $Vignette
@onready var _flash: ColorRect = $Flash


func _ready() -> void:
	_vignette.visible = false
	_flash.visible = false


func _notification(what: int) -> void:
	# La cinemática de otro jefe congela la arena con la viñeta puesta: se
	# quedaría fija en pantalla hasta que la descongelen.
	if what == NOTIFICATION_DISABLED and is_node_ready():
		clear()



func _process(delta: float) -> void:
	_clock += delta
	_level = lerpf(_level, _wanted, Juice.damp(dread_speed, delta))
	# Quien quiera la viñeta la pide en cada frame: si deja de pedirla, se va.
	_wanted = 0.0
	var material := _vignette.material as ShaderMaterial
	if _level < 0.01 or material == null:
		_vignette.visible = false
		return
	var beat := 0.5 + 0.5 * sin(_clock * TAU / maxf(dread_pulse_seconds, 0.05))
	_vignette.visible = true
	material.set_shader_parameter(&"amount", _level * dread_opacity * (1.0 - dread_pulse * beat))


## Un golpe de tamaño `size` en `at` (un punto del mundo): tiembla la cámara,
## más cuanto más cerca cae de un raider, y los fuertes y los demoledores
## además frenan el juego un instante.
func shock(size: Shock, at: Vector3) -> void:
	var share := _share_at(at)
	match size:
		Shock.LIGHT:
			Juice.shake(light_shake * share, light_shake_seconds)
		Shock.HEAVY:
			Juice.shake(heavy_shake * share, heavy_shake_seconds)
			Juice.hit_stop(heavy_stop_scale, heavy_stop_seconds)
		Shock.CRUSHING:
			Juice.shake(crushing_shake * share, crushing_shake_seconds)
			Juice.hit_stop(crushing_stop_scale, crushing_stop_seconds)
			_flash_screen(crushing_flash * share)


## Pide la viñeta de peligro a `amount` (0-1) durante este frame. El ataque
## que carga la llama en cada frame; cuando deja de llamarla, se desvanece.
func dread(amount: float) -> void:
	_wanted = maxf(_wanted, clampf(amount, 0.0, 1.0))


## Apaga la viñeta y el fogonazo ya (la langosta murió).
func clear() -> void:
	_wanted = 0.0
	_level = 0.0
	_vignette.visible = false
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.visible = false


## Un fogonazo a pantalla completa de opacidad `alpha` que se apaga solo.
func _flash_screen(alpha: float) -> void:
	if alpha <= 0.01:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.color = Color(flash_color, alpha)
	_flash.visible = true
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, crushing_flash_seconds)
	_flash_tween.tween_callback(_flash.hide)


## Qué parte del temblor llega desde `at` al raider más cercano (faint_share-1).
func _share_at(at: Vector3) -> float:
	var nearest := INF
	for raider: Node3D in Coop.alive_players(get_tree()):
		nearest = minf(nearest, raider.global_position.distance_to(at))
	if nearest == INF:
		return faint_share
	return lerpf(1.0, faint_share, smoothstep(full_within, faint_beyond, nearest))
