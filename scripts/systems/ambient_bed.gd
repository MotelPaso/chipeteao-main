class_name AmbientBed
extends AudioStreamPlayer
## Barely-audible looping ambience (a synthesized wind bed from
## scripts/tools/generate_sfx.gd — each arena assigns its biome's wav)
## that kills the dead silence in the arenas.
## Forces a seamless forward loop on the imported wav — the generated
## files carry no loop metadata — routes into the "Sfx" bus (created by
## the Sfx autoload before any scene loads), and keeps breathing while
## the card UI or run-end screen has the tree paused.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bus = Sfx.BUS_NAME
	var wav := stream as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	if not playing:
		play()


## Explicit stop so the playback is already marked released when the Sfx
## autoload's shutdown flush (see sfx.gd _exit_tree) runs after us.
func _exit_tree() -> void:
	stop()
