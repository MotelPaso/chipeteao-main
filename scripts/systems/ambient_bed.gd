class_name AmbientBed
extends AudioStreamPlayer
## Ambiente en bucle apenas audible (un viento sintetizado por
## scripts/tools/generate_sfx.gd; cada arena asigna el wav de su bioma) que
## quita el silencio muerto de las arenas.
## Fuerza un bucle continuo sobre SU PROPIA copia del wav importado (los
## archivos generados no traen metadatos de bucle y el recurso cargado es
## compartido), sale por el bus "Ambient" (lo crea el autoload Sfx antes de
## cargar cualquier escena; su volumen lo maneja Settings) y sigue sonando
## mientras la UI de cartas o la pantalla final pausan el árbol.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bus = Sfx.AMBIENT_BUS_NAME
	var wav := stream as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		# Sobre una COPIA: `stream` es la entrada global de ResourceLoader, y
		# ponerla en bucle haría que todo otro uso del mismo wav sonara en
		# bucle para siempre.
		wav = wav.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		stream = wav
	if not playing:
		play()


## Parada explícita, para que la reproducción ya esté liberada cuando corra
## después la limpieza de cierre del autoload Sfx (ver _exit_tree de sfx.gd).
func _exit_tree() -> void:
	stop()
