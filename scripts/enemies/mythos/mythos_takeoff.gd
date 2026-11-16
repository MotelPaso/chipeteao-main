class_name MythosTakeoff
extends MythosMove
## Aletazo: el despegue. Posado en tierra se alza con las alas en alto (el
## aviso), las bate y levanta vuelo: el golpe quema a quien siga a su lado y
## manda una onda de fuego que hay que saltar. No entra en la rotación: Mythos lo
## usa solo, cuando se le acaba el tiempo en tierra (MythosFlight).

@export_group("Aletazo")
## Segundos de aviso antes del golpe.
@export var windup: float = 0.7
## Radio del golpe y de su disco de aviso, en metros.
@export var radius: float = 6.0
## Daño del golpe a cada raider dentro del disco (valor base).
@export var damage: float = 35.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza.
@export var height_window: float = 1.8
## Segundos quieto en el aire después de despegar.
@export var recover: float = 0.5
## Sonido del golpe (fila de Sfx.SOUND_LIBRARY).
@export var blast_sfx: StringName = &"fire_whoosh"

@export_group("Columna de fuego")
## Escena de la columna que levanta el golpe (FireBurst, sale de Pools). Vacío = sin columna.
@export var burst_scene: PackedScene = preload("res://scenes/fx/FireBurst.tscn")
## Alto de la columna, en metros.
@export var burst_height: float = 9.0
## Radio de la columna, en veces el radio del golpe.
@export var burst_radius_factor: float = 0.6

@export_group("Onda de fuego")
## Escena de la onda que sale del golpe (FireWave, sale de Pools). Vacío = sin onda.
@export var wave_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Radio en metros hasta el que llega la onda.
@export var wave_radius: float = 22.0
## Metros por segundo a los que se abre.
@export var wave_speed: float = 15.0
## Daño de la onda a cada raider que alcance en el suelo (valor base).
@export var wave_damage: float = 28.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquiva saltando).
@export var wave_height_window: float = 1.0
## Ancho del anillo que golpea, en metros.
@export var wave_band: float = 1.4

var _timer: float = 0.0
var _blasted: bool = false


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	wave_damage *= multiplier


func begin(_target: Node3D) -> void:
	_timer = windup
	_blasted = false
	boss.warn_disc(boss.floor_point(boss.global_position), radius, windup)
	boss.rig.set_pose(MythosRig.Pose.REAR)


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _blasted:
		return true
	_blasted = true
	var at := boss.global_position
	boss.strike_ground([at], radius, height_window, damage)
	if wave_scene != null:
		FireWave.spawn(wave_scene, at, radius, wave_radius, wave_speed, wave_damage,
				wave_height_window, wave_band, boss)
	FireBurst.spawn(burst_scene, at, radius * burst_radius_factor, burst_height)
	boss.blast(boss.floor_point(at), radius)
	boss.feel.shock(MythosFeel.Shock.HEAVY, at)
	boss.rig.gesture(&"flap")
	boss.rig.burst()
	Sfx.play(blast_sfx)
	boss.take_off()
	_timer = recover
	return false
