extends SceneTree
## Offline SFX synthesizer: renders every sound the game ships with as
## original 16-bit PCM mono 44.1kHz wavs, from scratch, out of basic DSP
## blocks (oscillators, white noise, one-pole lowpass, envelopes, pitch
## sweeps). No external audio is ever sampled. Deterministic: every noise
## layer uses its own fixed seed, so re-running overwrites the files with
## identical bytes. Run once from the project root whenever a recipe is
## tweaked:
##
##     godot --headless --path . -s res://scripts/tools/generate_sfx.gd
##
## Output: assets/audio/sfx/*.wav (one-shots + the shrine channel loop)
## and assets/audio/ambient/forest_wind.wav (the Main ambient bed).
## Loopable sounds carry no wav loop metadata — Sfx/AmbientBed force
## LOOP_FORWARD on the imported streams at runtime.

const RATE := 44100.0
const SFX_DIR := "res://assets/audio/sfx"
const AMBIENT_DIR := "res://assets/audio/ambient"

enum Wave { SINE, SQUARE, SAW, TRIANGLE }

var _failed := false


func _init() -> void:
	if DirAccess.make_dir_recursive_absolute(SFX_DIR) != OK \
			or DirAccess.make_dir_recursive_absolute(AMBIENT_DIR) != OK:
		push_error("generate_sfx: cannot create output directories")
		quit(1)
		return
	_save_wav(SFX_DIR, "hit_soft", _gen_hit_soft())
	_save_wav(SFX_DIR, "hit_crit", _gen_hit_crit())
	_save_wav(SFX_DIR, "enemy_die", _gen_enemy_die())
	_save_wav(SFX_DIR, "gem_pickup", _gen_gem_pickup())
	_save_wav(SFX_DIR, "level_up", _gen_level_up())
	_save_wav(SFX_DIR, "card_pick", _gen_card_pick())
	_save_wav(SFX_DIR, "player_hurt", _gen_player_hurt())
	_save_wav(SFX_DIR, "dodge", _gen_dodge())
	_save_wav(SFX_DIR, "slide", _gen_slide())
	_save_wav(SFX_DIR, "shrine_channel", _gen_shrine_channel())
	_save_wav(SFX_DIR, "shrine_done", _gen_shrine_done())
	_save_wav(SFX_DIR, "chest_open", _gen_chest_open())
	_save_wav(SFX_DIR, "boss_roar", _gen_boss_roar())
	_save_wav(SFX_DIR, "boss_die", _gen_boss_die())
	_save_wav(SFX_DIR, "streak", _gen_streak())
	_save_wav(AMBIENT_DIR, "forest_wind", _gen_forest_wind())
	if _failed:
		quit(1)
		return
	print("SFX generation complete.")
	quit(0)


# --- sound recipes -----------------------------------------------------------

## Dull thump for regular weapon hits: plays constantly, so it stays low,
## short, and mostly lowpassed noise over a small sine drop.
func _gen_hit_soft() -> PackedFloat32Array:
	var out := _tone(0.09, 150.0, 92.0, Wave.SINE)
	_mix_at(out, _lowpass(_noise(0.09, _rng(11)), 750.0, 220.0), 0.0, 0.8)
	_exp_decay(out, 0.03)
	_fade_in(out, 0.003)
	_fade_out(out, 0.02)
	_normalize(out, 0.55)
	return out


## Sharper crit snap: fast upward saw sweep with a bright noise transient.
func _gen_hit_crit() -> PackedFloat32Array:
	var out := _tone(0.14, 620.0, 1500.0, Wave.SAW, 0.6)
	_mix_at(out, _lowpass(_noise(0.05, _rng(22)), 7000.0, 2500.0), 0.0, 0.5)
	_exp_decay(out, 0.04)
	_fade_in(out, 0.001)
	_fade_out(out, 0.03)
	_normalize(out, 0.9)
	return out


## Comical descending square blip plus a little dust puff.
func _gen_enemy_die() -> PackedFloat32Array:
	var out := _tone(0.24, 520.0, 150.0, Wave.SQUARE, 1.3)
	var puff := _lowpass(_noise(0.1, _rng(33)), 2200.0, 600.0)
	_exp_decay(puff, 0.035)
	_mix_at(out, puff, 0.0, 0.55)
	_exp_decay(out, 0.09)
	_fade_in(out, 0.002)
	_fade_out(out, 0.04)
	_normalize(out, 0.8)
	return out


## Tiny bright two-note ascending chirp (E6 -> B6).
func _gen_gem_pickup() -> PackedFloat32Array:
	var out := _silence(0.13)
	_mix_at(out, _chime(0.07, 1318.5, 0.03), 0.0, 1.0)
	_mix_at(out, _chime(0.08, 1975.5, 0.035), 0.05, 0.9)
	_normalize(out, 0.7)
	return out


## Rising C5-E5-G5 arpeggio with an octave shimmer on the top note.
func _gen_level_up() -> PackedFloat32Array:
	var out := _silence(0.5)
	_mix_at(out, _chime(0.2, 523.25, 0.07), 0.0, 1.0)
	_mix_at(out, _chime(0.2, 659.26, 0.07), 0.12, 1.0)
	_mix_at(out, _chime(0.26, 783.99, 0.1), 0.24, 1.0)
	_mix_at(out, _chime(0.26, 1046.5, 0.1), 0.24, 0.4)
	_normalize(out, 0.85)
	return out


## Soft affirmative click-chime: a short noise tick into an A5 ring.
func _gen_card_pick() -> PackedFloat32Array:
	var out := _silence(0.16)
	var click := _lowpass(_noise(0.015, _rng(44)), 4000.0, 2000.0)
	_exp_decay(click, 0.006)
	_fade_in(click, 0.001)
	_mix_at(out, click, 0.0, 0.6)
	_mix_at(out, _chime(0.14, 880.0, 0.045), 0.012, 0.8)
	_normalize(out, 0.7)
	return out


## Low muffled thud with a downward bend for taking a hit.
func _gen_player_hurt() -> PackedFloat32Array:
	var out := _tone(0.26, 150.0, 68.0, Wave.SINE, 1.2)
	_mix_at(out, _lowpass(_noise(0.26, _rng(55)), 400.0, 160.0), 0.0, 0.6)
	_exp_decay(out, 0.08)
	_fade_in(out, 0.002)
	_fade_out(out, 0.05)
	_normalize(out, 0.85)
	return out


## Airy whoosh: noise under an opening lowpass, swelling then falling.
func _gen_dodge() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.3, _rng(66)), 500.0, 7500.0)
	_adsr(out, 0.1, 0.19, 0.0, 0.0)
	_fade_out(out, 0.03)
	_normalize(out, 0.6)
	return out


## Lower, slightly longer whoosh for the slide start.
func _gen_slide() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.35, _rng(77)), 320.0, 1700.0)
	_adsr(out, 0.08, 0.24, 0.0, 0.0)
	_fade_out(out, 0.03)
	_normalize(out, 0.5)
	return out


## Soft shrine hum, loopable: every partial completes integer cycles over
## the 1.5s loop (f = k / 1.5) and the tremolo runs exactly 3 cycles, so
## the wrap point is phase-continuous with no blend needed.
func _gen_shrine_channel() -> PackedFloat32Array:
	var out := _tone(1.5, 110.0, 110.0, Wave.SINE)
	_mix_at(out, _tone(1.5, 167.0 / 1.5, 167.0 / 1.5, Wave.SINE), 0.0, 0.55)
	_mix_at(out, _tone(1.5, 220.0, 220.0, Wave.SINE), 0.0, 0.28)
	_mix_at(out, _tone(1.5, 496.0 / 1.5, 496.0 / 1.5, Wave.SINE), 0.0, 0.14)
	_tremolo(out, 2.0, 0.3)
	_normalize(out, 0.5)
	return out


## Warm resolved chime: rolled C major (root position) with an octave cap.
func _gen_shrine_done() -> PackedFloat32Array:
	var out := _silence(0.7)
	_mix_at(out, _chime(0.5, 523.25, 0.12), 0.0, 1.0)
	_mix_at(out, _chime(0.5, 659.26, 0.12), 0.045, 1.0)
	_mix_at(out, _chime(0.55, 783.99, 0.14), 0.09, 1.0)
	_mix_at(out, _chime(0.55, 1046.5, 0.14), 0.09, 0.35)
	_normalize(out, 0.8)
	return out


## Same chord family as shrine_done but first inversion, so the two
## completion chimes read as siblings without being identical.
func _gen_chest_open() -> PackedFloat32Array:
	var out := _silence(0.7)
	_mix_at(out, _chime(0.5, 659.26, 0.12), 0.0, 1.0)
	_mix_at(out, _chime(0.5, 783.99, 0.12), 0.045, 1.0)
	_mix_at(out, _chime(0.55, 1046.5, 0.14), 0.09, 1.0)
	_mix_at(out, _chime(0.55, 1318.5, 0.14), 0.09, 0.3)
	_normalize(out, 0.8)
	return out


## Original monster voice: detuned low saws pitch-bent up then down, a sub
## sine, breath noise, and a 13Hz amplitude growl, darkened by a lowpass.
func _gen_boss_roar() -> PackedFloat32Array:
	var out := _tone3(1.8, 60.0, 95.0, 45.0, Wave.SAW)
	_mix_at(out, _tone3(1.8, 61.1, 96.7, 45.9, Wave.SAW), 0.0, 0.7)
	_mix_at(out, _tone3(1.8, 30.0, 47.5, 22.5, Wave.SINE), 0.0, 0.6)
	_mix_at(out, _lowpass(_noise(1.8, _rng(88)), 1000.0, 450.0), 0.0, 0.4)
	out = _lowpass(out, 1600.0, 1600.0)
	_tremolo(out, 13.0, 0.4)
	_adsr(out, 0.12, 0.3, 0.85, 0.45)
	_normalize(out, 0.95)
	return out


## Big descending boom with a filtered noise tail.
func _gen_boss_die() -> PackedFloat32Array:
	var out := _tone(1.5, 170.0, 34.0, Wave.SINE, 0.55)
	_mix_at(out, _tone(1.5, 90.0, 18.0, Wave.SQUARE, 0.55), 0.0, 0.25)
	_mix_at(out, _lowpass(_noise(1.5, _rng(99)), 3800.0, 130.0), 0.0, 0.55)
	_exp_decay(out, 0.45)
	_fade_in(out, 0.004)
	_fade_out(out, 0.12)
	_normalize(out, 0.95)
	return out


## Punchy two-note stinger (G4 -> D5 squares) with a snap transient.
func _gen_streak() -> PackedFloat32Array:
	var out := _silence(0.3)
	var snap := _lowpass(_noise(0.02, _rng(111)), 5000.0, 3000.0)
	_exp_decay(snap, 0.008)
	var low := _tone(0.1, 392.0, 392.0, Wave.SQUARE)
	_exp_decay(low, 0.04)
	var high := _tone(0.2, 587.33, 587.33, Wave.SQUARE)
	_exp_decay(high, 0.07)
	_mix_at(out, snap, 0.0, 0.5)
	_mix_at(out, low, 0.0, 0.8)
	_mix_at(out, high, 0.08, 0.9)
	out = _lowpass(out, 3000.0, 3000.0)
	_fade_out(out, 0.03)
	_normalize(out, 0.85)
	return out


## Very quiet forest-wind bed, 4s loopable. Rendered 0.35s long, then the
## surplus tail is crossfaded into the head (_loop_blend) to hide the
## lowpass filter state mismatch at the wrap. Both LFOs complete integer
## cycles over the 4s loop, so their phase matches across the seam.
func _gen_forest_wind() -> PackedFloat32Array:
	var out := _lowpass_lfo(_noise(4.35, _rng(123)), 520.0, 320.0, 0.5)
	_tremolo(out, 0.25, 0.25)
	var looped := _loop_blend(out, 0.35)
	_normalize(looped, 0.35)
	return looped


# --- DSP building blocks ----------------------------------------------------

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _silence(duration: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	return out


func _osc(wave: Wave, phase: float) -> float:
	match wave:
		Wave.SINE:
			return sin(phase * TAU)
		Wave.SQUARE:
			return 1.0 if phase < 0.5 else -1.0
		Wave.SAW:
			return 2.0 * phase - 1.0
		Wave.TRIANGLE:
			return 1.0 - 4.0 * absf(phase - 0.5)
	return 0.0


## Oscillator with a pitch sweep f0 -> f1. `curve` shapes the sweep
## (t^curve): <1 moves early, >1 moves late. Phase-accumulated, so any
## sweep stays click-free.
func _tone(duration: float, f0: float, f1: float, wave: Wave,
		curve: float = 1.0) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var freq := lerpf(f0, f1, pow(t, curve))
		out[i] = _osc(wave, phase)
		phase = fmod(phase + freq / RATE, 1.0)
	return out


## Three-point pitch bend: f0 at the start, f_mid at the middle, f1 at the
## end, linear between (the boss roar's up-then-down growl).
func _tone3(duration: float, f0: float, f_mid: float, f1: float,
		wave: Wave) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var freq := lerpf(f0, f_mid, t * 2.0) if t < 0.5 \
				else lerpf(f_mid, f1, t * 2.0 - 1.0)
		out[i] = _osc(wave, phase)
		phase = fmod(phase + freq / RATE, 1.0)
	return out


func _noise(duration: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## Decaying sine with one octave harmonic — the shared bell/chime voice.
func _chime(duration: float, freq: float, half_life: float) -> PackedFloat32Array:
	var out := _tone(duration, freq, freq, Wave.SINE)
	_mix_at(out, _tone(duration, freq * 2.0, freq * 2.0, Wave.SINE), 0.0, 0.22)
	_exp_decay(out, half_life)
	_fade_in(out, 0.002)
	_fade_out(out, 0.02)
	return out


## One-pole lowpass with the cutoff sweeping start -> end over the buffer.
func _lowpass(samples: PackedFloat32Array, cutoff_start: float,
		cutoff_end: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var y := 0.0
	var last := float(maxi(samples.size() - 1, 1))
	for i in samples.size():
		var cutoff := lerpf(cutoff_start, cutoff_end, float(i) / last)
		# One-pole coefficient: alpha = 1 - e^(-2*pi*fc/fs).
		var alpha := 1.0 - exp(-TAU * cutoff / RATE)
		y += alpha * (samples[i] - y)
		out[i] = y
	return out


## One-pole lowpass whose cutoff breathes sinusoidally around `base`.
func _lowpass_lfo(samples: PackedFloat32Array, base: float, depth: float,
		lfo_hz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var y := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		var cutoff := maxf(base + sin(TAU * lfo_hz * t) * depth, 30.0)
		var alpha := 1.0 - exp(-TAU * cutoff / RATE)
		y += alpha * (samples[i] - y)
		out[i] = y
	return out


## In-place amplitude LFO; gain dips to (1 - depth) at the trough.
func _tremolo(samples: PackedFloat32Array, hz: float, depth: float) -> void:
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] *= 1.0 - depth * (0.5 + 0.5 * sin(TAU * hz * t))


## In-place exponential decay from t=0: gain halves every half_life seconds.
func _exp_decay(samples: PackedFloat32Array, half_life: float) -> void:
	for i in samples.size():
		samples[i] *= pow(0.5, (float(i) / RATE) / half_life)


## In-place linear ADSR: attack then decay from the start, sustain in the
## middle, and the last `release` seconds ramp down to silence.
func _adsr(samples: PackedFloat32Array, attack: float, decay: float,
		sustain: float, release: float) -> void:
	var n := samples.size()
	var a := int(attack * RATE)
	var d := int(decay * RATE)
	var r := int(release * RATE)
	for i in n:
		var gain := sustain
		if i < a:
			gain = float(i) / float(maxi(a, 1))
		elif i < a + d:
			gain = lerpf(1.0, sustain, float(i - a) / float(maxi(d, 1)))
		if i >= n - r:
			gain = minf(gain, sustain * float(n - i) / float(maxi(r, 1)))
		samples[i] *= gain


func _fade_in(samples: PackedFloat32Array, seconds: float) -> void:
	var n := mini(int(seconds * RATE), samples.size())
	for i in n:
		samples[i] *= float(i) / float(n)


func _fade_out(samples: PackedFloat32Array, seconds: float) -> void:
	var n := mini(int(seconds * RATE), samples.size())
	var total := samples.size()
	for i in n:
		samples[total - 1 - i] *= float(i) / float(n)


## Adds `src * gain` into `dst` starting at `at_seconds` (clipped to dst).
func _mix_at(dst: PackedFloat32Array, src: PackedFloat32Array,
		at_seconds: float, gain: float) -> void:
	var start := int(at_seconds * RATE)
	for i in src.size():
		var j := start + i
		if j >= dst.size():
			break
		dst[j] += src[i] * gain


## In-place peak normalization to `peak` (also the anti-clip stage).
func _normalize(samples: PackedFloat32Array, peak: float) -> void:
	var max_abs := 0.0
	for i in samples.size():
		max_abs = maxf(max_abs, absf(samples[i]))
	if max_abs < 0.0001:
		return
	var factor := peak / max_abs
	for i in samples.size():
		samples[i] *= factor


## Turns an over-rendered buffer into a seamless loop: the surplus tail
## (blend_seconds) is crossfaded into the head, so sample 0 continues the
## last sample exactly and the straight signal takes over by blend's end.
func _loop_blend(samples: PackedFloat32Array, blend_seconds: float) -> PackedFloat32Array:
	var b := int(blend_seconds * RATE)
	var length := samples.size() - b
	var out := PackedFloat32Array()
	out.resize(length)
	for i in length:
		out[i] = samples[i]
	for i in b:
		var w := float(i) / float(maxi(b, 1))
		out[i] = lerpf(samples[length + i], samples[i], w)
	return out


# --- output -----------------------------------------------------------------

func _save_wav(dir: String, sound_name: String, samples: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(RATE)
	wav.stereo = false
	wav.data = bytes
	var path := dir.path_join(sound_name + ".wav")
	if wav.save_to_wav(path) != OK:
		push_error("generate_sfx: failed to write %s" % path)
		_failed = true
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var size := file.get_length() if file != null else 0
	if size == 0:
		push_error("generate_sfx: %s is empty" % path)
		_failed = true
		return
	print("wrote %s (%d bytes, %.2fs)" % [path, size, float(samples.size()) / RATE])
