extends WeaponBase
## Dagas gemelas: cuerpo a cuerpo de un solo blanco muy rápido, estocadas
## veloces al enemigo más cercano a corta distancia. Cada estocada da
## exactamente un golpe por el embudo de daño (el Tomo de Multitud agrega
## estocadas escalonadas, nunca un segundo corte en el mismo frame). Sin
## modelo en la mano: cada estocada destella una medialuna SlashArc pequeña
## del pool sobre el blanco, alternando izquierda y derecha para que se lea
## el ritmo de dos dagas.

@export_group("Corte")
## Segundos que dura el destello de un corte.
@export var slash_time: float = 0.2
## Radio de la medialuna de un corte, en metros.
@export var slash_radius: float = 1.51
## Color de la medialuna del corte.
@export var slash_color: Color = Color(0.991721, 0.64353454, 0.27002934, 1)
## Giro de la medialuna durante el corte, en grados.
@export var slash_sweep_deg: float = 100.0
## Altura sobre el origen del blanco a la que se dibuja el corte, en metros.
@export var slash_lift: float = 0.3

@export_group("Multitud")
## Segundos entre las estocadas extra (projectile_count y Tomo de Multitud); con el enfriamiento corto, VOLLEY_WINDOW las comprime.
@export var extra_stagger: float = 0.2

## True cuando la PRÓXIMA estocada es el corte de la mano izquierda (alterna por golpe).
var _stab_left: bool = true


func fire(target: Node3D) -> void:
	fire_volley_retarget(maxi(effective_projectile_count(), 1), _stab.bind(target),
			_restab, extra_stagger)


## Una estocada extra. Elige su PROPIO blanco en vez de usar el de la ráfaga:
## el primer corte pudo haberlo matado, y una cadena larga dura más que el
## cadáver (que se libera un tercio de segundo después de morir).
func _restab() -> void:
	var target := acquire_target()
	if target != null:
		_stab(target)


## Una estocada por el embudo de daño, más su medialuna.
func _stab(target: Node3D) -> void:
	var health := Health.find_in(target)
	if health != null:
		deal_damage(health)
	_play_slash(target)
	# Izquierda y derecha alternan por estocada, así los extras de una ráfaga
	# se reflejan entre sí en vez de apilar la misma medialuna en el mismo cuerpo.
	_stab_left = not _stab_left


## Medialuna pequeña sobre el enemigo golpeado, barriendo en sentido opuesto
## en golpes alternos (sensación de daga izquierda y derecha).
func _play_slash(target: Node3D) -> void:
	var slash := Pools.acquire_scene(Pools.SLASH_ARC_SCENE) as SlashArc
	if slash == null:
		return
	var aim := flat_dir_or(target.global_position - global_position,
			-global_transform.basis.z)
	slash.play(target.global_position + Vector3.UP * slash_lift, aim, slash_radius,
			slash_color, slash_sweep_deg, slash_time, _stab_left)
