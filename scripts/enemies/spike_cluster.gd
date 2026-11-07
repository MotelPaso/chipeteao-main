class_name SpikeCluster
extends Node3D
## Grupo de púas que revienta el suelo y se vuelve a hundir: las raíces del
## Rotking (BarkSpikes.tscn) y las losas del Sarcognath (SandSpikes.tscn),
## misma silueta con otra piel. Cada hijo MeshInstance3D es una púa; la
## malla y el material están en la escena. BossBase._spawn_spike_cluster la
## instancia y llama a erupt(); el grupo se libera solo al terminar.

@export_group("Forma")
## Metros bajo el punto de impacto donde empieza enterrado el grupo.
@export var sink_depth: float = 1.2
## Inclinación máxima al azar de cada púa, en radianes por eje.
@export var max_tilt: float = 0.2

@export_group("Tiempos")
## Segundos que tarda en salir del suelo.
@export var rise_time: float = 0.12
## Segundos que se queda afuera.
@export var hold_time: float = 0.35
## Segundos que tarda en volver a hundirse.
@export var sink_time: float = 0.25
## Metros extra que se hunde bajo donde empezó.
@export var extra_sink: float = 0.1
## Metros sobre el punto de impacto donde queda la base al salir.
@export var rise_lift: float = 0.05


## Reparte las púas en anillo a `spread_radius` de `center`, les da una
## inclinación al azar y anima la salida. Llamar con el grupo ya en el árbol.
## Orden de RNG: dos randf_range por púa (x, después z), en orden de hijos.
func erupt(center: Vector3, spread_radius: float) -> void:
	var spikes: Array[Node] = get_children()
	var count := spikes.size()
	for i in count:
		var spike := spikes[i] as Node3D
		var spike_angle := TAU * float(i) / float(count)
		spike.position = Vector3(cos(spike_angle), 0.0, sin(spike_angle)) * spread_radius
		spike.rotation = Vector3(randf_range(-max_tilt, max_tilt), 0.0,
				randf_range(-max_tilt, max_tilt))
	global_position = center - Vector3.UP * sink_depth
	var tween := create_tween()
	tween.tween_property(self, "global_position:y", center.y + rise_lift, rise_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_time)
	tween.tween_property(self, "global_position:y",
			center.y - sink_depth - extra_sink, sink_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
