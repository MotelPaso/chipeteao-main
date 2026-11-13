extends WeaponBase
## Guantes de boxeo (Dagas gemelas): cuerpo a cuerpo muy rápido, golpes veloces
## al enemigo más cercano a corta distancia. Cada golpe daña en área: alcanza a
## todos los enemigos dentro de un radio alrededor del blanco, cada uno una vez
## por el embudo de daño (el Tomo de Multitud agrega golpes escalonados, nunca
## un segundo corte en el mismo frame). Sin modelo en la mano: cada golpe
## destella una medialuna SlashArc del pool sobre el blanco, alternando
## izquierda y derecha para que se lea el ritmo de dos manos.

@export_group("Corte")
## Segundos que dura el destello de un corte.
@export var slash_time: float = 0.2
## Radio visual de la medialuna de un corte, en metros (se agranda con el área si scale_slash_with_area).
@export var slash_radius: float = 1.51
## Color de la medialuna del corte.
@export var slash_color: Color = Color(0.991721, 0.64353454, 0.27002934, 1)
## Giro de la medialuna durante el corte, en grados.
@export var slash_sweep_deg: float = 100.0
## Altura sobre el origen del blanco a la que se dibuja el corte, en metros.
@export var slash_lift: float = 0.3

@export_group("Área")
## Radio del daño en área alrededor del blanco, en metros (los tomos de área lo escalan).
@export var hit_radius: float = 1.6
## Si la medialuna dibujada crece junto con el radio de daño, para que lo que se ve coincida con lo que pega.
@export var scale_slash_with_area: bool = true

@export_group("Multitud")
## Segundos entre los golpes extra (projectile_count y Tomo de Multitud); con el enfriamiento corto, VOLLEY_WINDOW los comprime.
@export var extra_stagger: float = 0.2

## True cuando la PRÓXIMA estocada es el corte de la mano izquierda (alterna por golpe).
var _stab_left: bool = true


func fire(target: Node3D) -> void:
	fire_volley_retarget(maxi(effective_projectile_count(), 1), _stab.bind(target),
			_restab, extra_stagger)


## Un golpe extra. Elige su PROPIO blanco en vez de usar el de la ráfaga:
## el primer corte pudo haberlo matado, y una cadena larga dura más que el
## cadáver (que se libera un tercio de segundo después de morir).
func _restab() -> void:
	var target := acquire_target()
	if target != null:
		_stab(target)


## Un golpe en área centrado en el blanco, más su medialuna.
func _stab(target: Node3D) -> void:
	# El blanco puede haber muerto o liberado entre el disparo y el golpe escalonado.
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var radius := hit_radius * area_scale()
	# El centro es el punto de puntería del blanco: así la esfera cubre bien al
	# enemigo golpeado y a los que lo rodean, también los que están algo más altos.
	var victims := enemies_in_sphere(body_aim_point(target), radius)
	# Garantiza que el blanco cuente aunque quede justo en el borde de la esfera.
	if not victims.has(target):
		victims.append(target)
	damage_all(victims)
	_play_slash(target)
	# Izquierda y derecha alternan por golpe, así los extras de una ráfaga
	# se reflejan entre sí en vez de apilar la misma medialuna en el mismo cuerpo.
	_stab_left = not _stab_left


## Medialuna sobre el enemigo golpeado, barriendo en sentido opuesto en golpes
## alternos (sensación de mano izquierda y derecha).
func _play_slash(target: Node3D) -> void:
	var slash := Pools.acquire_scene(Pools.SLASH_ARC_SCENE) as SlashArc
	if slash == null:
		return
	var aim := flat_dir_or(target.global_position - global_position,
			-global_transform.basis.z)
	var visual_radius := slash_radius * (area_scale() if scale_slash_with_area else 1.0)
	slash.play(target.global_position + Vector3.UP * slash_lift, aim, visual_radius,
			slash_color, slash_sweep_deg, slash_time, _stab_left)
