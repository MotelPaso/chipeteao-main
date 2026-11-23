class_name SfxAbduction
extends RefCounted
## Recetas de los sonidos del VIAJE a la arena de la Langosta Azul, para el
## sintetizador de efectos (scripts/tools/generate_sfx.gd, que escribe un wav
## por cada una): el presagio, el agua que brota y se cierra en el rapto, la
## pantalla que se inunda, el toque de fondo y el portal de regreso. Todo es
## agua: ruido filtrado que se abre y se cierra sobre un grave, con burbujas
## (chasquidos apagados). Cada capa se lleva a pico 1 antes de mezclarla, así
## el número que la acompaña es cuánto pesa en la mezcla. Las semillas del
## ruido son fijas: volver a correrlo da lo mismo.


## Presagio: una marea grave que crece y se va, con un canto lejano encima.
static func omen_swell() -> PackedFloat32Array:
	var out := SfxDsp.silence(2.6)
	var tide := SfxDsp.lowpass(SfxDsp.noise(2.6, SfxDsp.rng(801)), 260.0, 900.0)
	tide = SfxDsp.lowpass(tide, 900.0, 220.0)
	SfxDsp.tremolo(tide, 0.9, 0.5)
	_layer(out, tide, 0.0, 0.8)
	_layer(out, SfxDsp.tone(2.6, 44.0, 62.0, SfxDsp.Wave.SINE), 0.0, 1.0)
	_layer(out, SfxDsp.tone(2.6, 66.0, 93.0, SfxDsp.Wave.TRIANGLE), 0.0, 0.4)
	var call := SfxDsp.tone3(1.6, 250.0, 198.0, 148.0, SfxDsp.Wave.SINE)
	SfxDsp.tremolo(call, 5.0, 0.35)
	SfxDsp.adsr(call, 0.5, 0.3, 0.6, 0.6)
	_layer(out, call, 0.7, 0.3)
	SfxDsp.fade_in(out, 1.1)
	SfxDsp.fade_out(out, 1.0)
	return _finish(out, 0.9, 0.3, 0.8)


## Un chorro que brota del suelo: el golpe grave, el agua que sube y se abre
## y las gotas que caen.
static func geyser() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.95)
	_layer(out, _thump(0.4, 120.0, 42.0, 0.08), 0.0, 0.8)
	var jet := SfxDsp.bandpass(SfxDsp.noise(0.8, SfxDsp.rng(811)), 500.0, 2800.0, 900.0, 1.4)
	SfxDsp.adsr(jet, 0.02, 0.18, 0.5, 0.45)
	_layer(out, jet, 0.0, 1.0)
	var spray := SfxDsp.highpass(SfxDsp.noise(0.7, SfxDsp.rng(812)), 3200.0, 2200.0)
	SfxDsp.adsr(spray, 0.05, 0.2, 0.4, 0.4)
	_layer(out, spray, 0.06, 0.35)
	var drops := SfxDsp.lowpass(SfxDsp.crackle(0.6, SfxDsp.rng(813), 34.0, 0.012), 4200.0, 1800.0)
	_layer(out, drops, 0.3, 0.3)
	return _finish(out, 0.3, 0.14, 0.82)


## El remolino que se cierra: agua que gira cada vez más rápido y más aguda
## sobre un grave que sube.
static func whirlpool() -> PackedFloat32Array:
	var out := SfxDsp.silence(3.4)
	var swirl := SfxDsp.lowpass_lfo(SfxDsp.noise(3.4, SfxDsp.rng(821)), 900.0, 650.0, 2.2)
	swirl = SfxDsp.lowpass(swirl, 700.0, 3600.0)
	SfxDsp.tremolo(swirl, 6.5, 0.4)
	_layer(out, swirl, 0.0, 1.0)
	_layer(out, SfxDsp.tone(3.4, 48.0, 104.0, SfxDsp.Wave.SINE), 0.0, 0.8)
	_layer(out, SfxDsp.tone(3.4, 96.0, 208.0, SfxDsp.Wave.TRIANGLE), 0.0, 0.25)
	var foam := SfxDsp.highpass(SfxDsp.noise(3.4, SfxDsp.rng(822)), 2600.0, 3800.0)
	SfxDsp.tremolo(foam, 9.0, 0.6)
	_layer(out, foam, 0.0, 0.25)
	SfxDsp.swell(out, 1.6)
	SfxDsp.fade_in(out, 0.25)
	SfxDsp.fade_out(out, 0.12)
	return _finish(out, 0.35, 0.16, 0.86)


## La pantalla se inunda: el agua tapa todo, el sonido se apaga hacia lo
## grave y quedan las burbujas.
static func flood() -> PackedFloat32Array:
	var out := SfxDsp.silence(2.1)
	var rush := SfxDsp.lowpass(SfxDsp.noise(1.8, SfxDsp.rng(831)), 5200.0, 170.0)
	SfxDsp.adsr(rush, 0.2, 0.5, 0.6, 0.9)
	_layer(out, rush, 0.0, 1.0)
	_layer(out, _thump(1.5, 150.0, 34.0, 0.45), 0.25, 0.85)
	var bubbles := SfxDsp.lowpass(SfxDsp.crackle(1.6, SfxDsp.rng(832), 26.0, 0.02), 1500.0, 500.0)
	_layer(out, bubbles, 0.5, 0.45)
	return _finish(out, 0.8, 0.3, 0.9)


## El equipo toca fondo: un golpe sordo, apagado por el agua, y la arena que se levanta.
static func seabed_landing() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.9)
	_layer(out, _thump(0.6, 88.0, 30.0, 0.14), 0.0, 1.0)
	var sand := SfxDsp.lowpass(SfxDsp.noise(0.8, SfxDsp.rng(841)), 900.0, 180.0)
	SfxDsp.adsr(sand, 0.02, 0.2, 0.4, 0.5)
	_layer(out, sand, 0.0, 0.6)
	var bubbles := SfxDsp.lowpass(SfxDsp.crackle(0.6, SfxDsp.rng(842), 18.0, 0.02), 1200.0, 500.0)
	_layer(out, bubbles, 0.15, 0.3)
	return _finish(out, 0.5, 0.25, 0.8)


## El portal de regreso se abre: un acorde de agua que sube con burbujas.
static func return_portal() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.5)
	for step: int in 3:
		var freq := 262.0 * pow(1.26, float(step))
		var bell := SfxDsp.chime(1.2, freq, 0.35)
		_layer(out, bell, 0.11 * float(step), 0.5)
	var wash := SfxDsp.bandpass(SfxDsp.noise(1.3, SfxDsp.rng(851)), 700.0, 2400.0, 1500.0, 1.2)
	SfxDsp.adsr(wash, 0.3, 0.3, 0.5, 0.6)
	_layer(out, wash, 0.0, 0.35)
	var bubbles := SfxDsp.lowpass(SfxDsp.crackle(1.2, SfxDsp.rng(852), 22.0, 0.015), 2600.0, 900.0)
	_layer(out, bubbles, 0.2, 0.3)
	return _finish(out, 0.7, 0.3, 0.8)


# --- bloques ------------------------------------------------------------------------

## Suma `src` (llevada a pico 1) a `dst` desde el segundo `at`, con peso `weight`.
static func _layer(dst: PackedFloat32Array, src: PackedFloat32Array, at: float,
		weight: float) -> void:
	SfxDsp.normalize(src, 1.0)
	SfxDsp.mix_at(dst, src, at, weight)


## Cierra una receta: le da `tail` segundos de cola de reverberación (con
## `wet` de eco) y la deja a pico `peak`.
static func _finish(out: PackedFloat32Array, tail: float, wet: float,
		peak: float) -> PackedFloat32Array:
	SfxDsp.normalize(out, 1.0)
	var spaced := SfxDsp.reverb(out, tail, wet)
	SfxDsp.fade_out(spaced, minf(tail, 0.3))
	SfxDsp.normalize(spaced, peak)
	return spaced


## Golpe grave: un seno que cae de f0 a f1 y se apaga a la mitad cada `half_life`.
static func _thump(seconds: float, f0: float, f1: float, half_life: float) -> PackedFloat32Array:
	var out := SfxDsp.tone(seconds, f0, f1, SfxDsp.Wave.SINE, 0.5)
	SfxDsp.exp_decay(out, half_life)
	SfxDsp.fade_in(out, 0.002)
	SfxDsp.fade_out(out, 0.02)
	return out
