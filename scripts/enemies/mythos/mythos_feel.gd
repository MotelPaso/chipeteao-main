class_name MythosFeel
extends CanvasLayer
## Lo que se SIENTE de los golpes de Mythos (nodo Feel de Mythos.tscn): la
## sacudida de cámara, la pausa de impacto y el destello de cada golpe según
## su tamaño, y la VIÑETA DE PELIGRO que oscurece los bordes de la pantalla
## mientras carga sus ataques más fuertes. Los ataques dicen qué pasó (shock
## con un tamaño y un lugar, dread con cuánto falta); cuánto tiembla y cómo
## se ve vive aquí. La viñeta toma el color de la segunda fase junto con el
## fuego (FireTint).

## Tamaño de un golpe.
enum Shock { LIGHT, HEAVY, CATACLYSM }

@export_group("Golpe liviano")
## Temblor de cámara (0-1) de un golpe liviano: una pasada, una bola que cae.
@export var light_shake: float = 0.16
## Segundos que dura ese temblor.
@export var light_shake_seconds: float = 0.25

@export_group("Golpe fuerte")
## Temblor de cámara (0-1) de un golpe fuerte: la Picada, un estallido.
@export var heavy_shake: float = 0.42
## Segundos que dura ese temblor.
@export var heavy_shake_seconds: float = 0.5
## Escala de tiempo (0-1) de la pausa de impacto de un golpe fuerte.
@export_range(0.05, 1.0) var heavy_stop_scale: float = 0.2
## Segundos reales que dura esa pausa (0 = sin pausa).
@export var heavy_stop_seconds: float = 0.05

@export_group("Cataclismo")
## Temblor de cámara (0-1) de sus golpes más grandes.
@export var cataclysm_shake: float = 0.75
## Segundos que dura ese temblor.
@export var cataclysm_shake_seconds: float = 0.9
## Escala de tiempo (0-1) de la pausa de impacto de un cataclismo.
@export_range(0.05, 1.0) var cataclysm_stop_scale: float = 0.12
## Segundos reales que dura esa pausa (0 = sin pausa).
@export var cataclysm_stop_seconds: float = 0.09

@export_group("Distancia")
## Metros al raider más cercano hasta los que el golpe se siente entero.
@export var full_within: float = 9.0
## Metros desde los que se siente lo mínimo.
@export var faint_beyond: float = 42.0
## Parte del temblor (0-1) que queda a esa distancia.
@export_range(0.0, 1.0) var faint_share: float = 0.35

@export_group("Viñeta de peligro")
## Color de los bordes de la pantalla mientras carga un ataque grande.
@export var dread_color: Color = Color(0.55, 0.04, 0.0)
## Ese color en su segunda fase.
@export var reborn_dread_color: Color = Color(0.02, 0.1, 0.5)
## Opacidad máxima (0-1) de la viñeta.
@export_range(0.0, 1.0) var dread_opacity: float = 0.7
## Parte de esa opacidad (0-1) que late en vez de quedarse fija.
@export_range(0.0, 1.0) var dread_pulse: float = 0.35
## Segundos de un latido.
@export var dread_pulse_seconds: float = 0.55
## Rapidez con que la viñeta aparece y se va (por segundo).
@export var dread_speed: float = 5.0

## Lo que pidieron los ataques en este frame y lo que se ve ahora (0-1).
var _wanted: float = 0.0
var _level: float = 0.0
var _clock: float = 0.0

@onready var _vignette: ColorRect = $Vignette
@onready var _boss: Mythos = get_parent() as Mythos


func _ready() -> void:
	_vignette.visible = false


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
	material.set_shader_parameter(&"tint", dread_color.lerp(reborn_dread_color, FireTint.amount()))


## Un golpe de tamaño `size` en `at` (un punto del mundo): tiembla la cámara,
## más cuanto más cerca cae de un raider, y los golpes grandes además frenan
## el juego un instante. El cataclismo suma un destello a pantalla completa.
func shock(size: Shock, at: Vector3) -> void:
	var share := _share_at(at)
	match size:
		Shock.LIGHT:
			Juice.shake(light_shake * share, light_shake_seconds)
		Shock.HEAVY:
			Juice.shake(heavy_shake * share, heavy_shake_seconds)
			Juice.hit_stop(heavy_stop_scale, heavy_stop_seconds)
		Shock.CATACLYSM:
			Juice.shake(cataclysm_shake, cataclysm_shake_seconds)
			Juice.hit_stop(cataclysm_stop_scale, cataclysm_stop_seconds)
			if _boss != null:
				_boss.screen_flash()


## Pide la viñeta de peligro a `amount` (0-1) durante este frame. El ataque
## que carga la llama en cada frame; cuando deja de llamarla, se desvanece.
func dread(amount: float) -> void:
	_wanted = maxf(_wanted, clampf(amount, 0.0, 1.0))


# --- privados ---------------------------------------------------------------------

## Qué parte del temblor llega desde `at` al raider más cercano (faint_share-1).
func _share_at(at: Vector3) -> float:
	var nearest := INF
	for raider: Node3D in Coop.alive_players(get_tree()):
		nearest = minf(nearest, raider.global_position.distance_to(at))
	if nearest == INF:
		return faint_share
	return lerpf(1.0, faint_share, smoothstep(full_within, faint_beyond, nearest))
