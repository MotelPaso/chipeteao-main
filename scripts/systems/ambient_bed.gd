class_name AmbientBed
extends AudioStreamPlayer
## Barely-audible looping ambience (a synthesized wind bed from
## scripts/tools/generate_sfx.gd — each arena assigns its biome's wav)
## that kills the dead silence in the arenas.
## Forces a seamless forward loop on its OWN copy of the imported wav —
## the generated files carry no loop metadata, and the loaded resource is
## shared process-wide — routes into the "Ambient" bus (created
## by the Sfx autoload before any scene loads, volume owned by the
## Settings autoload), and keeps breathing while the card UI or run-end
## screen has the tree paused.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bus = Sfx.AMBIENT_BUS_NAME
	var wav := stream as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		# On a COPY: `stream` is the process-wide ResourceLoader entry, so
		# looping it in place would make every other use of the same wav
		# (a one-shot gust, say) loop forever and hold a voice for good.
		wav = wav.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		stream = wav
	if not playing:
		play()


## Explicit stop so the playback is already marked released when the Sfx
## autoload's shutdown flush (see sfx.gd _exit_tree) runs after us.
func _exit_tree() -> void:
	stop()
