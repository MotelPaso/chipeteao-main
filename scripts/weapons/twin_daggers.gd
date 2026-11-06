extends WeaponBase
## Dagas gemelas: cuerpo a cuerpo de un solo blanco muy rápido, estocadas
## veloces al enemigo más cercano a corta distancia. Cada estocada da
## exactamente un golpe por el embudo de daño (el Tomo de Multitud agrega
## estocadas escalonadas, nunca un segundo corte en el mismo frame). Sin
## modelo en la mano: cada estocada destella una medialuna SlashArc pequeña
## del pool sobre el blanco, alternando izquierda y derecha para que se lea
## el ritmo de dos dagas.

## Segundos que dura el destello de un corte.
@export var slash_time: float = 0.1
## Radio de la medialuna de un corte, en metros.
@export var slash_radius: float = 1.0
## Color de la medialuna del corte.
@export var slash_color: Color = Color(0.8, 0.65, 1.0)

## Segundos entre las estocadas que agrega el Tomo de Multitud. Escalonadas,
## no simultáneas: esta arma es un ritmo de cortes sueltos, y dos estocadas en
## el mismo cuerpo y el mismo frame se leen como un golpe con número doble.
const EXTRA_STAB_STAGGER: float = 0.2
## La cadena escalonada termina dentro de esta fracción de un enfriamiento:
## con el enfriamiento cortísimo de las dagas, este recorte evita que una pila
## grande del tomo meta estocadas en la ráfaga siguiente.
const STAB_CHAIN_WINDOW: float = 0.6

## True cuando la PRÓXIMA estocada es el corte de la mano izquierda (alterna por golpe).
var _stab_left: bool = true


func fire(target: Node3D) -> void:
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_STAB_STAGGER,
			effective_cooldown() * STAB_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	_stab(target)
	for i: int in range(1, count):
		# Temporizador pausable y en paso de física: una estocada extra no sale
		# con la pantalla de mejoras abierta, y el daño cae en el mismo tick que
		# el resto del combate.
		get_tree().create_timer(step * float(i), false, true).timeout \
				.connect(_restab)


## Una estocada extra del Tomo de Multitud. Elige su PROPIO blanco en vez de
## usar el de la ráfaga: el primer corte pudo haberlo matado, y una cadena
## larga dura más que el cadáver (que se libera un tercio de segundo después
## de morir). Llega un poco después de fire(), cuando el arma puede haber
## salido del árbol con un raider quitado.
func _restab() -> void:
	if not is_inside_tree():
		return
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
	slash.play(target.global_position + Vector3.UP * 0.3, aim, slash_radius,
			slash_color, 100.0, slash_time, _stab_left)
