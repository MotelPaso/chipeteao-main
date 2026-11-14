class_name HellSound
extends RefCounted
## El sonido del infierno para HellTransformation: los fondos de viento de la
## arena se apagan mientras entra el de fuego (el nodo FireBed de
## HellTransformation.tscn), y ese fondo baja cuando el bosque se enfría. Los
## volúmenes los pone HellTransformation, que es quien los muestra en el
## Inspector.

## Volumen, en dB, que cuenta como silencio.
const SILENT_DB: float = -60.0

var _fire_bed: AudioStreamPlayer = null
## Fondos de viento de la arena con su volumen de bosque: {player, from}.
var _wind: Array[Dictionary] = []


## Toma el fondo de fuego, en silencio hasta que el bosque arda.
func setup(fire_bed: AudioStreamPlayer) -> void:
	_fire_bed = fire_bed
	_fire_bed.volume_db = SILENT_DB


## Anota los fondos de viento de `arena` con el volumen que tienen ahora.
func collect(arena: Node3D) -> void:
	for node: Node in arena.find_children("*", "AudioStreamPlayer", true, false):
		var bed := node as AmbientBed
		if bed != null and bed != _fire_bed:
			_wind.append({"player": bed, "from": bed.volume_db})


## Avance del encendido (0-1): el viento se va y el fuego entra hasta
## `fire_db`. Con `done` el viento se detiene del todo.
func ignite(weight: float, done: bool, fire_db: float) -> void:
	for entry: Dictionary in _wind:
		var player := entry["player"] as AudioStreamPlayer
		if is_instance_valid(player):
			player.volume_db = lerpf(float(entry["from"]), SILENT_DB, weight)
			if done:
				player.stop()
	set_fire(lerpf(SILENT_DB, fire_db, weight))


## Volumen del fondo de fuego, en dB.
func set_fire(db: float) -> void:
	if _fire_bed != null:
		_fire_bed.volume_db = db
