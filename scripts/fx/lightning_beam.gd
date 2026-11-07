class_name LightningBeam
extends MeshInstance3D
## Segmento de rayo de un solo uso entre dos puntos (Pararrayos y Cinturón
## eléctrico): destella, se desvanece y se libera solo. Cada arma pide su
## estilo con play(); la malla, el color y los tiempos de cada estilo se
## editan en LightningBeam.tscn. El largo va en scale.y sobre una malla de
## altura 1, y el desvanecido usa la transparencia del nodo porque el
## material lo comparten todos los rayos del mismo estilo.

## Qué arma dibuja el rayo.
enum Style { STORM_ROD, BELT }

@export_group("Pararrayos")
## Malla y material del rayo del Pararrayos (radio, color, mezcla aditiva); cilindro de altura 1.
@export var storm_mesh: Mesh
## Segundos que tarda el rayo del Pararrayos en desvanecerse.
@export var storm_fade_time: float = 0.22
## Grosor final del rayo del Pararrayos como fracción de su radio (menor que 1 = se adelgaza al apagarse).
@export var storm_fade_scale: float = 0.3

@export_group("Cinturón eléctrico")
## Malla y material del rayo del Cinturón eléctrico (radio y color); cilindro de altura 1.
@export var belt_mesh: Mesh
## Segundos que tarda el rayo del Cinturón en desvanecerse.
@export var belt_fade_time: float = 0.22
## Grosor final del rayo del Cinturón como fracción de su radio (mayor que 1 = se ensancha al apagarse).
@export var belt_fade_scale: float = 3.0


## Dibuja el rayo de `from` a `to` con el aspecto de `style` y se libera al
## terminar. Quien llama ya descartó los tramos demasiado cortos.
func play(from: Vector3, to: Vector3, style: Style) -> void:
	var is_belt := style == Style.BELT
	mesh = belt_mesh if is_belt else storm_mesh
	var fade_time := belt_fade_time if is_belt else storm_fade_time
	var fade_scale := belt_fade_scale if is_belt else storm_fade_scale
	var span := to - from
	var length := span.length()
	global_position = (from + to) * 0.5
	# El eje del cilindro es Y: se apunta -Z al punto lejano y luego se dobla
	# Y sobre él, con la guarda de "arriba" degenerado de WeaponBase.
	var direction := span / length
	look_at(to, WeaponBase.safe_up(direction))
	rotate_object_local(Vector3.RIGHT, PI * 0.5)
	scale = Vector3(1.0, length, 1.0)
	transparency = 0.0
	var tween := create_tween()
	tween.tween_property(self, "transparency", 1.0, fade_time)
	tween.parallel().tween_property(self, "scale",
			Vector3(fade_scale, length, fade_scale), fade_time)
	tween.tween_callback(queue_free)
