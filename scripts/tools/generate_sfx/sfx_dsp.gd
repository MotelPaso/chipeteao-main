class_name SfxDsp
extends RefCounted
## Bloques de DSP del sintetizador de efectos (scripts/tools/generate_sfx.gd):
## osciladores, ruido, filtros, envolventes y una reverberación chica. Todo
## trabaja sobre buffers mono de RATE muestras por segundo. Los que dicen «en
## el lugar» cambian el buffer que reciben; el resto devuelve uno nuevo.
## Es determinista: el ruido sale de un RandomNumberGenerator con semilla fija.

enum Wave { SINE, SQUARE, SAW, TRIANGLE }

const RATE := 44100.0
## Frecuencia más alta que aguanta el filtro de banda sin volverse inestable.
const BAND_MAX_HZ := 7000.0
## Retardos (en segundos) de los cuatro peines y los dos pasa-todo de la reverberación.
const REVERB_COMBS: Array[float] = [0.0297, 0.0371, 0.0411, 0.0437]
const REVERB_ALLPASSES: Array[float] = [0.005, 0.0017]


static func rng(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


static func silence(duration: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	return out


static func osc(wave: Wave, phase: float) -> float:
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


## Oscilador con barrido de tono f0 -> f1. `curve` da forma al barrido
## (t^curve): <1 se mueve temprano, >1 tarde. Acumula fase, así ningún
## barrido hace clic.
static func tone(duration: float, f0: float, f1: float, wave: Wave,
		curve: float = 1.0) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var freq := lerpf(f0, f1, pow(t, curve))
		out[i] = osc(wave, phase)
		phase = fmod(phase + freq / RATE, 1.0)
	return out


## Curva de tono de tres puntos: f0 al inicio, f_mid a la mitad y f1 al
## final, lineal entre ellos (el gruñido que sube y baja del jefe).
static func tone3(duration: float, f0: float, f_mid: float, f1: float,
		wave: Wave) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var freq := lerpf(f0, f_mid, t * 2.0) if t < 0.5 \
				else lerpf(f_mid, f1, t * 2.0 - 1.0)
		out[i] = osc(wave, phase)
		phase = fmod(phase + freq / RATE, 1.0)
	return out


static func noise(duration: float, generator: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = generator.randf_range(-1.0, 1.0)
	return out


## Seno que decae con un armónico de octava: la voz de campana compartida.
static func chime(duration: float, freq: float, half_life: float) -> PackedFloat32Array:
	var out := tone(duration, freq, freq, Wave.SINE)
	mix_at(out, tone(duration, freq * 2.0, freq * 2.0, Wave.SINE), 0.0, 0.22)
	exp_decay(out, half_life)
	fade_in(out, 0.002)
	fade_out(out, 0.02)
	return out


## Chisporroteo: `per_second` chasquidos de ruido repartidos al azar, cada uno
## decayendo a la mitad en `half_life` segundos.
static func crackle(duration: float, generator: RandomNumberGenerator, per_second: float,
		half_life: float) -> PackedFloat32Array:
	var out := silence(duration)
	var length := int(half_life * 7.0 * RATE)
	for _click in int(duration * per_second):
		var start := int(generator.randf() * duration * RATE)
		var gain := generator.randf_range(0.3, 1.0)
		for j in length:
			if start + j >= out.size():
				break
			out[start + j] += generator.randf_range(-1.0, 1.0) * gain \
					* pow(0.5, (float(j) / RATE) / half_life)
	return out


## Pasa-bajos de un polo con el corte barriendo de start a end en el buffer.
static func lowpass(samples: PackedFloat32Array, cutoff_start: float,
		cutoff_end: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var y := 0.0
	var last := float(maxi(samples.size() - 1, 1))
	for i in samples.size():
		var cutoff := lerpf(cutoff_start, cutoff_end, float(i) / last)
		# Coeficiente de un polo: alpha = 1 - e^(-2*pi*fc/fs).
		var alpha := 1.0 - exp(-TAU * cutoff / RATE)
		y += alpha * (samples[i] - y)
		out[i] = y
	return out


## Pasa-bajos de un polo cuyo corte respira en seno alrededor de `base`.
static func lowpass_lfo(samples: PackedFloat32Array, base: float, depth: float,
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


## Pasa-altos: lo que el pasa-bajos de un polo deja afuera.
static func highpass(samples: PackedFloat32Array, cutoff_start: float,
		cutoff_end: float) -> PackedFloat32Array:
	var out := lowpass(samples, cutoff_start, cutoff_end)
	for i in samples.size():
		out[i] = samples[i] - out[i]
	return out


## Pasa-banda resonante cuyo centro pasa de f0 a f_mid (a la mitad) y a f1,
## barriendo en octavas: el alma de un silbido, un soplo o algo que pasa
## volando. `q` más alto = banda más angosta y más silbido.
static func bandpass(samples: PackedFloat32Array, f0: float, f_mid: float, f1: float,
		q: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var low := 0.0
	var band := 0.0
	var damp := 1.0 / maxf(q, 0.5)
	var last := float(maxi(samples.size() - 1, 1))
	for i in samples.size():
		var t := float(i) / last
		var center := f0 * pow(f_mid / f0, t * 2.0) if t < 0.5 \
				else f_mid * pow(f1 / f_mid, t * 2.0 - 1.0)
		# Filtro de estado variable de Chamberlin.
		var c := 2.0 * sin(PI * minf(center, BAND_MAX_HZ) / RATE)
		low += c * band
		band += c * (samples[i] - low - damp * band)
		out[i] = band
	return out


## LFO de amplitud en el lugar; la ganancia baja a (1 - depth) en el valle.
static func tremolo(samples: PackedFloat32Array, hz: float, depth: float) -> void:
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] *= 1.0 - depth * (0.5 + 0.5 * sin(TAU * hz * t))


## Aleteo de llama en el lugar: la ganancia va saltando al azar `hz` veces
## por segundo entre (1 - depth) y 1, sin escalones.
static func flutter(samples: PackedFloat32Array, generator: RandomNumberGenerator, hz: float,
		depth: float) -> void:
	var step := maxi(int(RATE / maxf(hz, 0.1)), 1)
	var from := 1.0
	var to := 1.0 - depth * generator.randf()
	for i in samples.size():
		var at := i % step
		if at == 0 and i > 0:
			from = to
			to = 1.0 - depth * generator.randf()
		samples[i] *= lerpf(from, to, float(at) / float(step))


## Decaimiento exponencial en el lugar desde t=0: la ganancia se reduce a
## la mitad cada half_life segundos.
static func exp_decay(samples: PackedFloat32Array, half_life: float) -> void:
	for i in samples.size():
		samples[i] *= pow(0.5, (float(i) / RATE) / half_life)


## ADSR lineal en el lugar: ataque y caída desde el inicio, sostén en el
## medio y los últimos `release` segundos bajan a silencio.
static func adsr(samples: PackedFloat32Array, attack: float, decay: float,
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


static func fade_in(samples: PackedFloat32Array, seconds: float) -> void:
	var n := mini(int(seconds * RATE), samples.size())
	for i in n:
		samples[i] *= float(i) / float(n)


static func fade_out(samples: PackedFloat32Array, seconds: float) -> void:
	var n := mini(int(seconds * RATE), samples.size())
	var total := samples.size()
	for i in n:
		samples[total - 1 - i] *= float(i) / float(n)


## Crecida en el lugar sobre todo el buffer: la ganancia sube de 0 a 1 como
## t^curve (más alto = llega de golpe al final).
static func swell(samples: PackedFloat32Array, curve: float) -> void:
	var last := float(maxi(samples.size() - 1, 1))
	for i in samples.size():
		samples[i] *= pow(float(i) / last, curve)


## Saturación suave en el lugar: con `drive` > 1 engorda y ensucia el sonido.
static func saturate(samples: PackedFloat32Array, drive: float) -> void:
	for i in samples.size():
		samples[i] = tanh(samples[i] * drive)


## El mismo buffer al revés (un golpe al revés es algo que se carga).
static func reversed(samples: PackedFloat32Array) -> PackedFloat32Array:
	var out := samples.duplicate()
	out.reverse()
	return out


## Suma `src * gain` en `dst` desde `at_seconds` (recortado a dst).
static func mix_at(dst: PackedFloat32Array, src: PackedFloat32Array,
		at_seconds: float, gain: float) -> void:
	var start := int(at_seconds * RATE)
	for i in src.size():
		var j := start + i
		if j >= dst.size():
			break
		dst[j] += src[i] * gain


## Normalización de pico en el lugar a `peak` (también evita la saturación).
static func normalize(samples: PackedFloat32Array, peak: float) -> void:
	var max_abs := 0.0
	for i in samples.size():
		max_abs = maxf(max_abs, absf(samples[i]))
	if max_abs < 0.0001:
		return
	var factor := peak / max_abs
	for i in samples.size():
		samples[i] *= factor


## Reverberación chica (cuatro peines y dos pasa-todo): le da tamaño a un
## golpe. Devuelve el buffer con `seconds` de cola de más; `mix` es cuánto del
## eco se suma al sonido seco y `damping` (0-1) cuánto se apagan sus agudos.
static func reverb(samples: PackedFloat32Array, seconds: float, mix: float,
		damping: float = 0.45) -> PackedFloat32Array:
	var total := samples.size() + int(seconds * RATE)
	var wet := PackedFloat32Array()
	wet.resize(total)
	for delay: float in REVERB_COMBS:
		var size := int(delay * RATE)
		var line := PackedFloat32Array()
		line.resize(size)
		# Ganancia de vuelta para que el eco caiga 60 dB en `seconds`.
		var feedback := pow(10.0, -3.0 * delay / maxf(seconds, 0.05))
		var held := 0.0
		for i in total:
			var at := i % size
			var echoed := line[at]
			held += (1.0 - damping) * (echoed - held)
			line[at] = (samples[i] if i < samples.size() else 0.0) + held * feedback
			wet[i] += echoed * 0.25
	for delay: float in REVERB_ALLPASSES:
		var size := int(delay * RATE)
		var line := PackedFloat32Array()
		line.resize(size)
		for i in total:
			var at := i % size
			var echoed := line[at]
			var entering := wet[i] + echoed * 0.5
			line[at] = entering
			wet[i] = echoed - entering * 0.5
	for i in total:
		wet[i] = wet[i] * mix + (samples[i] if i < samples.size() else 0.0)
	return wet


## Convierte un buffer generado de más en un bucle sin costura: la cola
## sobrante (blend_seconds) se funde con el inicio, así la muestra 0 sigue
## exactamente a la última y la señal directa manda al terminar la mezcla.
static func loop_blend(samples: PackedFloat32Array, blend_seconds: float) -> PackedFloat32Array:
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
