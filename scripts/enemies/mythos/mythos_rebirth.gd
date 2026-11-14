class_name MythosRebirth
extends Node
## El renacer de Mythos (nodo Rebirth de Mythos.tscn): lo que pasa entre su
## primera forma y la renacida. Mythos lleva la cuenta de vidas y avisa aquí
## cuándo cae y cuándo renace; este nodo tiene los valores y la puesta en
## escena. Segundos desde que cae en cenizas:
##   0                disco de aviso del estallido y orbes de vida
##   pillar_at        una columna de fuego sube de las cenizas y la brasa
##                    empieza a brillar cada vez más
##   rebirth_seconds  estalla: golpe, ondas de fuego que hay que saltar,
##                    destello, un instante de cámara lenta y el cartel

@export_group("Renacer")
## Segundos que pasa en cenizas, invulnerable, antes de renacer.
@export var rebirth_seconds: float = 6.5
## Radio del estallido al renacer y de su disco de aviso, en metros.
@export var rebirth_radius: float = 10.0
## Daño del estallido al renacer (valor base).
@export var rebirth_damage: float = 45.0
## Metros sobre el suelo por encima de los cuales el estallido no alcanza (alto: un salto no lo esquiva).
@export var rebirth_height_window: float = 2.6
## Segundos sin atacar justo después de renacer.
@export var post_rebirth_pause: float = 1.4

@export_group("Columna de fuego")
## Escena de la columna que sube de las cenizas (un FireTornado que no daña). Vacío = sin columna.
@export var pillar_scene: PackedScene = preload("res://scenes/fx/FireTornado.tscn")
## Segundos en cenizas tras los cuales sube la columna.
@export var pillar_at: float = 2.0
## Radio de la columna, en metros.
@export var pillar_radius: float = 3.2

@export_group("Ondas de fuego")
## Escena de las ondas que salen del estallido (FireWave, sale de Pools). Vacío = sin ondas.
@export var wave_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Ondas que salen, una tras otra.
@export var waves: int = 2
## Segundos entre una onda y la siguiente.
@export var wave_interval: float = 0.55
## Metros por segundo a los que se abre cada onda.
@export var wave_speed: float = 16.0
## Radio en metros hasta el que llega cada onda.
@export var wave_radius: float = 36.0
## Daño de cada onda a cada raider que alcance en el suelo (valor base).
@export var wave_damage: float = 30.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquivan saltando).
@export var wave_height_window: float = 1.0
## Ancho del anillo que golpea, en metros.
@export var wave_band: float = 1.6

@export_group("Puesta en escena")
## Cartel del HUD al renacer (vacío = sin cartel).
@export var banner_text: String = "¡Mythos renace!"
## Velocidad del juego durante el instante de cámara lenta (1 = sin cámara lenta).
@export_range(0.05, 1.0) var slow_scale: float = 0.3
## Segundos reales que dura ese instante.
@export var slow_seconds: float = 0.45
## Fuerza del temblor de cámara del estallido.
@export var shake_strength: float = 0.7
## Segundos que dura ese temblor.
@export var shake_seconds: float = 1.1
## Radio del estallido de luz, en unidades del modelo.
@export var flash_radius: float = 12.0
## Segundos que dura ese estallido de luz.
@export var flash_seconds: float = 0.7
## Grito mientras sube la columna (fila de Sfx.SOUND_LIBRARY).
@export var charge_sfx: StringName = &"phoenix_ascend"
## Sonido del estallido (fila de Sfx.SOUND_LIBRARY).
@export var rebirth_sfx: StringName = &"phoenix_rebirth"

@export_group("Orbes de vida")
## Orbes de vida que suelta al caer en cenizas.
@export var ash_orbs: int = 2
## Orbes extra por cada raider de la party además del primero.
@export var ash_orbs_per_extra_player: int = 1
## Radio en metros del anillo donde caen (dentro del estallido: hay que ir por ellos a tiempo).
@export var ash_orb_radius: float = 3.5

var _boss: Mythos = null
var _origin: Vector3 = Vector3.ZERO
var _clock: float = 0.0
var _pillar_up: bool = false
var _waves_left: int = 0
var _wave_timer: float = 0.0


func _ready() -> void:
	set_physics_process(false)


func scale_damage(multiplier: float) -> void:
	rebirth_damage *= multiplier
	wave_damage *= multiplier


## Mythos cayó en cenizas: avisa el estallido, suelta los orbes y arranca la
## cuenta de la puesta en escena.
func enter_ashes(boss: Mythos) -> void:
	_boss = boss
	_origin = boss.global_position
	_clock = 0.0
	_pillar_up = false
	_waves_left = 0
	Telegraph.spawn_disc(boss, _origin, rebirth_radius, rebirth_seconds, boss.telegraph_color)
	var count := ash_orbs + ash_orbs_per_extra_player * maxi(Coop.player_count - 1, 0)
	var start := randf() * TAU
	for i: int in count:
		var angle := start + TAU * float(i) / float(maxi(count, 1))
		var at := boss.floor_point(_origin
				+ Vector3(cos(angle), 0.0, sin(angle)) * ash_orb_radius)
		EnemyLoot.spawn_health_orb(get_tree(), at + Vector3.UP * 0.6)
	set_physics_process(true)


## Mythos renace: el estallido avisado, la primera onda y todo el espectáculo.
func burst(boss: Mythos) -> void:
	boss.strike_ground([_origin], rebirth_radius, rebirth_height_window, rebirth_damage)
	_waves_left = waves
	_send_wave()
	boss.rig.pop_nova(flash_radius, flash_seconds)
	boss.rig.burst()
	boss.screen_flash()
	Juice.hit_stop(slow_scale, slow_seconds)
	Juice.shake(shake_strength, shake_seconds)
	Sfx.play(rebirth_sfx)
	if not banner_text.is_empty():
		get_tree().call_group("boss_ui", "announce_major", banner_text)
	set_physics_process(true)


## Corta la puesta en escena (Mythos murió o se fue con la arena).
func cancel() -> void:
	_waves_left = 0
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	_clock += delta
	if not is_instance_valid(_boss):
		cancel()
		return
	if not _pillar_up and _clock >= pillar_at and _clock < rebirth_seconds:
		_raise_pillar()
	if _pillar_up and _clock < rebirth_seconds:
		# La brasa brilla cada vez más hasta el estallido.
		_boss.rig.set_nova((_clock - pillar_at) / maxf(rebirth_seconds - pillar_at, 0.01))
	if _waves_left > 0:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_send_wave()
	elif _clock > rebirth_seconds:
		set_physics_process(false)


## La columna de fuego: se forma rápido y dura hasta el estallido.
func _raise_pillar() -> void:
	_pillar_up = true
	Sfx.play(charge_sfx)
	Juice.shake(shake_strength * 0.3, rebirth_seconds - _clock)
	if pillar_scene == null:
		return
	var pillar := Pools.acquire_scene(pillar_scene) as FireTornado
	if pillar != null:
		pillar.start(_origin, pillar_radius, 0.5, rebirth_seconds - _clock - 0.3, 0.0, 0.0,
				false)


func _send_wave() -> void:
	_waves_left -= 1
	_wave_timer = wave_interval
	if wave_scene != null:
		FireWave.spawn(wave_scene, _origin, rebirth_radius, wave_radius, wave_speed,
				wave_damage, wave_height_window, wave_band, _boss)
