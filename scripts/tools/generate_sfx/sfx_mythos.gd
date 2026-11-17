class_name SfxMythos
extends RefCounted
## Recetas de los sonidos de los ATAQUES de Mythos, para el sintetizador de
## efectos (scripts/tools/generate_sfx.gd, que escribe un wav por cada una).
## Cada ataque tiene su sonido propio, armado por capas con los bloques de
## SfxDsp: un golpe grave, un cuerpo de ruido, un chasquido, brasas y, donde
## hace falta tamaño, una cola de reverberación. Cada capa se lleva a pico 1
## antes de mezclarla, así el número que la acompaña es cuánto pesa en la
## mezcla. Las semillas del ruido son fijas: volver a correrlo da lo mismo.

## Cuánto se aprieta la mezcla de un golpe antes de darle cola (1 = nada; más
## alto = más lleno y más sucio).
const GLUE_DRIVE: float = 1.6


# --- Ataques de tierra y de vuelo ---------------------------------------------------

## Garras: un tajo de aire que cae de agudo a grave, el filo y la llama que deja.
static func claw_swipe() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.5)
	var slash := _whoosh(0.32, 701, 5200.0, 2600.0, 700.0, 2.2)
	SfxDsp.fade_in(slash, 0.012)
	SfxDsp.exp_decay(slash, 0.09)
	_layer(out, slash, 0.0, 1.0)
	_layer(out, _crack(0.12, 702, 0.022), 0.012, 0.5)
	var flame := _roar(0.45, 703, 2400.0, 1400.0, 380.0, 20.0, 0.3)
	SfxDsp.adsr(flame, 0.03, 0.1, 0.6, 0.28)
	_layer(out, flame, 0.04, 0.75)
	_layer(out, _thump(0.22, 150.0, 55.0, 0.055), 0.03, 0.7)
	return _finish(out, 0.4, 0.18, 0.88)


## Golpe de la Picada: el más pesado. Un trueno que baja hasta el subgrave, la
## tierra que cruje, los escombros que caen y el fuego que se abre.
static func dive_impact() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.7)
	_layer(out, _thump(1.1, 95.0, 26.0, 0.22), 0.0, 0.9)
	_layer(out, _boom(1.0, 711, 900.0, 90.0, 0.16, 2.5), 0.0, 1.0)
	_layer(out, _crack(0.09, 712, 0.012), 0.0, 0.6)
	var debris := SfxDsp.lowpass(SfxDsp.crackle(1.3, SfxDsp.rng(713), 40.0, 0.01), 3200.0, 500.0)
	SfxDsp.exp_decay(debris, 0.45)
	_layer(out, debris, 0.08, 0.5)
	var wash := _whoosh(1.5, 714, 300.0, 900.0, 250.0, 0.8)
	SfxDsp.fade_in(wash, 0.1)
	SfxDsp.exp_decay(wash, 0.45)
	_layer(out, wash, 0.05, 0.45)
	return _finish(out, 1.3, 0.3, 0.95)


## Caída de la Picada: el cometa que se viene encima, un silbido de aire que
## sube y crece hasta cortarse en el golpe.
static func dive_fall() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.6)
	_layer(out, _whoosh(0.6, 721, 500.0, 1500.0, 4400.0, 3.0), 0.0, 1.0)
	var scream := SfxDsp.lowpass(SfxDsp.tone(0.6, 180.0, 640.0, SfxDsp.Wave.SAW, 2.0),
			900.0, 3200.0)
	_layer(out, scream, 0.0, 0.3)
	SfxDsp.swell(out, 2.0)
	SfxDsp.fade_out(out, 0.025)
	SfxDsp.normalize(out, 0.8)
	return out


## Aletazo del despegue: un golpe de aire grande que barre hacia afuera.
static func wing_blast() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.1)
	_layer(out, _thump(0.5, 110.0, 38.0, 0.12), 0.0, 0.9)
	var gust := _whoosh(1.0, 741, 350.0, 1500.0, 300.0, 0.9)
	SfxDsp.fade_in(gust, 0.03)
	SfxDsp.exp_decay(gust, 0.22)
	_layer(out, gust, 0.0, 1.0)
	_layer(out, _boom(0.5, 742, 2200.0, 300.0, 0.1, 1.0), 0.0, 0.6)
	return _finish(out, 0.6, 0.22, 0.9)


## Pasada de fuego y Embestida: algo enorme que pasa volando, con su rugido
## que sube al acercarse y baja al irse.
static func strafe_pass() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.5)
	_layer(out, _whoosh(1.5, 751, 600.0, 2400.0, 500.0, 1.6), 0.0, 1.0)
	_layer(out, _roar(1.5, 752, 500.0, 1800.0, 400.0, 18.0, 0.4), 0.0, 0.7)
	var rumble := SfxDsp.lowpass(SfxDsp.tone3(1.5, 70.0, 110.0, 55.0, SfxDsp.Wave.SAW),
			400.0, 400.0)
	_layer(out, rumble, 0.0, 0.4)
	SfxDsp.fade_in(out, 0.55)
	SfxDsp.fade_out(out, 0.8)
	return _finish(out, 0.5, 0.15, 0.85)


## Fogonazo: el zumbido de cruzar la arena de un tirón y el golpe de aparecer.
static func fire_blink() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.5)
	var zip := _whoosh(0.2, 801, 700.0, 5000.0, 1800.0, 3.0)
	SfxDsp.fade_in(zip, 0.1)
	SfxDsp.fade_out(zip, 0.02)
	_layer(out, zip, 0.0, 0.9)
	_layer(out, _thump(0.2, 300.0, 80.0, 0.04), 0.19, 0.7)
	_layer(out, _boom(0.28, 802, 3000.0, 500.0, 0.05, 1.0), 0.19, 0.8)
	SfxDsp.fade_out(out, 0.05)
	SfxDsp.normalize(out, 0.75)
	return out


# --- Fuego que lanza ----------------------------------------------------------------

## Plumas ardientes: cinco soplos filosos y seguidos, cada uno más agudo, con
## un silbido que sube.
static func fire_feathers() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.55)
	for i in 5:
		var puff := _whoosh(0.1, 321 + i, 2200.0 + 450.0 * float(i), 5200.0, 1500.0, 2.5)
		SfxDsp.exp_decay(puff, 0.022)
		_layer(out, puff, 0.045 * float(i), 0.9)
	var whistle := SfxDsp.tone(0.35, 900.0, 2600.0, SfxDsp.Wave.TRIANGLE, 0.6)
	SfxDsp.fade_in(whistle, 0.02)
	SfxDsp.fade_out(whistle, 0.2)
	_layer(out, whistle, 0.02, 0.18)
	_layer(out, _thump(0.12, 180.0, 80.0, 0.04), 0.0, 0.35)
	SfxDsp.fade_out(out, 0.08)
	SfxDsp.normalize(out, 0.65)
	return out


## Lanzamiento de una bola de fuego: un golpe sordo y el soplo que sale
## disparado, con su siseo.
static func fireball_cast() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.6)
	_layer(out, _thump(0.3, 240.0, 60.0, 0.06), 0.0, 0.8)
	var launch := _whoosh(0.5, 411, 400.0, 1800.0, 3000.0, 1.0)
	SfxDsp.fade_in(launch, 0.01)
	SfxDsp.exp_decay(launch, 0.12)
	_layer(out, launch, 0.0, 1.0)
	var sizzle := SfxDsp.highpass(SfxDsp.noise(0.4, SfxDsp.rng(412)), 3000.0, 3000.0)
	SfxDsp.fade_in(sizzle, 0.05)
	SfxDsp.exp_decay(sizzle, 0.1)
	_layer(out, sizzle, 0.03, 0.3)
	SfxDsp.fade_out(out, 0.08)
	SfxDsp.normalize(out, 0.75)
	return out


## Bola que cae del cielo (el Diluvio): un silbido que baja, como algo que
## viene cayendo.
static func fireball_fall() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.0)
	_layer(out, SfxDsp.tone(1.0, 2300.0, 700.0, SfxDsp.Wave.SINE, 0.7), 0.0, 0.4)
	_layer(out, SfxDsp.tone(1.0, 2330.0, 712.0, SfxDsp.Wave.TRIANGLE, 0.7), 0.0, 0.2)
	_layer(out, _whoosh(1.0, 791, 3400.0, 1900.0, 900.0, 3.5), 0.0, 0.8)
	SfxDsp.fade_in(out, 0.15)
	SfxDsp.fade_out(out, 0.12)
	SfxDsp.normalize(out, 0.55)
	return out


## Estallido de una bola de fuego: trueno seco, chasquido y brasas que caen.
static func fireball_blast() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.05)
	_layer(out, _thump(0.9, 120.0, 30.0, 0.2), 0.0, 0.85)
	_layer(out, _boom(1.0, 421, 4500.0, 160.0, 0.13, 1.8), 0.0, 1.0)
	_layer(out, _crack(0.07, 422, 0.01), 0.0, 0.6)
	_layer(out, _embers(0.95, 423, 50.0, 0.3), 0.06, 0.4)
	return _finish(out, 0.5, 0.25, 0.9)


## Una zona de fuego que se enciende: el «fuomp» de la llama que prende y su
## chisporroteo.
static func zone_ignite() -> PackedFloat32Array:
	var out := SfxDsp.silence(0.7)
	_layer(out, _thump(0.3, 160.0, 55.0, 0.07), 0.0, 0.7)
	var flare := _roar(0.6, 761, 500.0, 3200.0, 600.0, 0.0, 0.0)
	SfxDsp.adsr(flare, 0.02, 0.1, 0.5, 0.35)
	_layer(out, flare, 0.0, 1.0)
	_layer(out, _embers(0.6, 762, 45.0, 0.25), 0.05, 0.5)
	SfxDsp.fade_out(out, 0.1)
	SfxDsp.normalize(out, 0.7)
	return out


## Onda de fuego: un golpe y una llamarada que rueda hacia afuera y se aleja.
static func fire_wave() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.4)
	_layer(out, _thump(0.4, 120.0, 42.0, 0.1), 0.0, 0.7)
	var roar := _roar(1.4, 731, 300.0, 2400.0, 450.0, 14.0, 0.35)
	SfxDsp.fade_in(roar, 0.12)
	SfxDsp.fade_out(roar, 0.75)
	_layer(out, roar, 0.0, 1.0)
	var air := _whoosh(1.3, 733, 700.0, 2600.0, 900.0, 1.2)
	SfxDsp.fade_in(air, 0.2)
	SfxDsp.fade_out(air, 0.8)
	_layer(out, air, 0.02, 0.4)
	return _finish(out, 0.7, 0.2, 0.8)


## Estallido del centro del Cerco de brasas: el golpe y las llamas que suben.
static func ring_blast() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.3)
	_layer(out, _thump(0.8, 110.0, 32.0, 0.18), 0.0, 0.85)
	_layer(out, _boom(0.9, 771, 3800.0, 220.0, 0.14, 2.0), 0.0, 1.0)
	_layer(out, _crack(0.06, 772, 0.01), 0.0, 0.5)
	var flames := _whoosh(1.1, 773, 500.0, 2200.0, 700.0, 1.0)
	SfxDsp.flutter(flames, SfxDsp.rng(774), 16.0, 0.4)
	SfxDsp.fade_in(flames, 0.08)
	SfxDsp.fade_out(flames, 0.7)
	_layer(out, flames, 0.04, 0.6)
	_layer(out, _embers(0.9, 775, 45.0, 0.3), 0.06, 0.35)
	return _finish(out, 0.9, 0.25, 0.9)


# --- Tornados -----------------------------------------------------------------------

## Tornado de fuego al formarse: el aullido del remolino, que sube y late,
## sobre el rugido de la llama.
static func fire_tornado() -> PackedFloat32Array:
	var out := SfxDsp.silence(2.0)
	var wind := SfxDsp.noise(2.0, SfxDsp.rng(431))
	var howl := SfxDsp.bandpass(wind, 250.0, 700.0, 450.0, 4.0)
	SfxDsp.tremolo(howl, 6.5, 0.5)
	_layer(out, howl, 0.0, 1.0)
	var whistle := SfxDsp.bandpass(wind, 520.0, 1500.0, 950.0, 5.0)
	SfxDsp.tremolo(whistle, 6.5, 0.5)
	_layer(out, whistle, 0.0, 0.35)
	_layer(out, _roar(2.0, 432, 400.0, 2600.0, 900.0, 12.0, 0.4), 0.0, 0.6)
	var growl := SfxDsp.lowpass(SfxDsp.tone(2.0, 55.0, 120.0, SfxDsp.Wave.SAW, 1.3),
			300.0, 300.0)
	_layer(out, growl, 0.0, 0.35)
	SfxDsp.adsr(out, 0.4, 0.2, 0.8, 0.7)
	return _finish(out, 0.5, 0.15, 0.8)


## La Jaula de tornados al reventar: el trueno y el remolino que se deshace
## aullando hacia abajo.
static func tornado_burst() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.5)
	_layer(out, _thump(0.9, 90.0, 28.0, 0.2), 0.0, 0.85)
	_layer(out, _boom(1.0, 781, 3000.0, 180.0, 0.16, 2.0), 0.0, 1.0)
	var howl := _whoosh(1.3, 782, 1400.0, 600.0, 180.0, 4.0)
	SfxDsp.fade_in(howl, 0.02)
	SfxDsp.exp_decay(howl, 0.35)
	_layer(out, howl, 0.0, 0.7)
	var wind := _whoosh(1.2, 783, 2600.0, 1200.0, 500.0, 0.9)
	SfxDsp.exp_decay(wind, 0.3)
	_layer(out, wind, 0.02, 0.5)
	return _finish(out, 1.1, 0.28, 0.92)


# --- Aliento y Amanecer -------------------------------------------------------------

## Mythos toma aire antes del Aliento: un soplo que se cierra hacia adentro y
## crece, con el gruñido de la garganta.
static func breath_inhale() -> PackedFloat32Array:
	var out := SfxDsp.silence(1.45)
	_layer(out, _whoosh(1.45, 971, 300.0, 900.0, 2600.0, 2.0), 0.0, 1.0)
	var growl := SfxDsp.lowpass(SfxDsp.tone(1.45, 60.0, 98.0, SfxDsp.Wave.SAW), 320.0, 320.0)
	SfxDsp.tremolo(growl, 20.0, 0.5)
	_layer(out, growl, 0.0, 0.5)
	SfxDsp.swell(out, 1.6)
	SfxDsp.fade_out(out, 0.04)
	SfxDsp.normalize(out, 0.7)
	return out


## Aliento de fuego: el chorro que prende de golpe y ruge un par de segundos,
## lleno y tembloroso, con el bramido de la garganta, siseo y brasas.
static func phoenix_breath() -> PackedFloat32Array:
	var out := SfxDsp.silence(2.4)
	_layer(out, _roar(2.4, 977, 600.0, 3800.0, 1200.0, 22.0, 0.45), 0.0, 1.0)
	var throat := SfxDsp.lowpass(SfxDsp.tone(2.4, 85.0, 58.0, SfxDsp.Wave.SAW, 1.3),
			260.0, 260.0)
	SfxDsp.tremolo(throat, 13.0, 0.4)
	_layer(out, throat, 0.0, 0.5)
	_layer(out, SfxDsp.highpass(SfxDsp.noise(2.4, SfxDsp.rng(979)), 3500.0, 3500.0), 0.0, 0.15)
	_layer(out, _embers(2.2, 980, 30.0, 4.0), 0.05, 0.22)
	SfxDsp.adsr(out, 0.06, 0.2, 0.85, 0.6)
	_layer(out, _thump(0.3, 140.0, 50.0, 0.08), 0.0, 0.6)
	_layer(out, _crack(0.08, 981, 0.012), 0.0, 0.4)
	return _finish(out, 0.6, 0.15, 0.88)


## Carga del Amanecer: tres segundos de algo que crece sin parar, aire que se
## afina y un coro grave que sube, hasta cortarse justo antes del estallido.
static func dawn_riser() -> PackedFloat32Array:
	var out := SfxDsp.silence(3.0)
	_layer(out, _whoosh(3.0, 345, 200.0, 800.0, 5000.0, 2.0), 0.0, 1.0)
	var choir := SfxDsp.tone(3.0, 80.0, 320.0, SfxDsp.Wave.SAW, 2.2)
	SfxDsp.mix_at(choir, SfxDsp.tone(3.0, 120.5, 481.0, SfxDsp.Wave.SAW, 2.2), 0.0, 0.7)
	choir = SfxDsp.lowpass(choir, 400.0, 4000.0)
	SfxDsp.tremolo(choir, 9.0, 0.4)
	_layer(out, choir, 0.0, 0.55)
	SfxDsp.swell(out, 2.0)
	SfxDsp.fade_out(out, 0.05)
	SfxDsp.normalize(out, 0.8)
	return out


## Estallido del Amanecer: el golpe más grande de la pelea. Un chasquido, un
## trueno que cae hasta el subgrave, una pared de ruido que se cierra
## despacio y tres campanas, con una cola larga.
static func phoenix_nova() -> PackedFloat32Array:
	var out := SfxDsp.silence(2.4)
	_layer(out, _crack(0.1, 341, 0.015), 0.0, 0.6)
	_layer(out, _thump(1.6, 140.0, 24.0, 0.4), 0.0, 0.9)
	_layer(out, _boom(2.4, 342, 7000.0, 200.0, 0.5, 2.2), 0.0, 1.0)
	_layer(out, SfxDsp.chime(1.6, 1174.7, 0.3), 0.02, 0.3)
	_layer(out, SfxDsp.chime(1.6, 1760.0, 0.25), 0.02, 0.2)
	_layer(out, SfxDsp.chime(1.6, 587.3, 0.35), 0.02, 0.25)
	return _finish(out, 1.8, 0.35, 0.95)


# --- piezas -------------------------------------------------------------------------

## Suma `src` en `dst` desde `at` segundos, llevado antes a pico 1: `weight`
## es cuánto pesa esa capa en la mezcla.
static func _layer(dst: PackedFloat32Array, src: PackedFloat32Array, at: float,
		weight: float) -> void:
	SfxDsp.normalize(src, 1.0)
	SfxDsp.mix_at(dst, src, at, weight)


## Cierra una receta: aprieta la mezcla (así pesa más sin pasarse de pico), le
## da `tail` segundos de cola de reverberación (con `wet` de eco) y la deja a
## pico `peak`.
static func _finish(out: PackedFloat32Array, tail: float, wet: float,
		peak: float) -> PackedFloat32Array:
	SfxDsp.normalize(out, 1.0)
	SfxDsp.saturate(out, GLUE_DRIVE)
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


## Cuerpo de un estallido: ruido que se cierra de `bright` a `dull` Hz y se
## apaga; con `drive` > 1 sale más gordo y sucio.
static func _boom(seconds: float, seed_value: int, bright: float, dull: float,
		half_life: float, drive: float) -> PackedFloat32Array:
	var out := SfxDsp.lowpass(SfxDsp.noise(seconds, SfxDsp.rng(seed_value)), bright, dull)
	SfxDsp.exp_decay(out, half_life)
	SfxDsp.fade_in(out, 0.002)
	SfxDsp.fade_out(out, 0.03)
	if drive > 1.0:
		SfxDsp.normalize(out, 1.0)
		SfxDsp.saturate(out, drive)
	return out


## Chasquido agudo y corto: lo primero que se oye de un golpe.
static func _crack(seconds: float, seed_value: int, half_life: float) -> PackedFloat32Array:
	var out := SfxDsp.highpass(SfxDsp.noise(seconds, SfxDsp.rng(seed_value)), 2500.0, 2500.0)
	SfxDsp.exp_decay(out, half_life)
	return out


## Soplo: ruido por una banda que pasa de f0 a f_mid y a f1.
static func _whoosh(seconds: float, seed_value: int, f0: float, f_mid: float, f1: float,
		q: float) -> PackedFloat32Array:
	return SfxDsp.bandpass(SfxDsp.noise(seconds, SfxDsp.rng(seed_value)), f0, f_mid, f1, q)


## Rugido de llama: ruido grave que se abre de f0 a f_mid y se cierra a f1,
## con un aleteo de `flutter_hz` y hondura `flutter_depth` (0 = parejo).
static func _roar(seconds: float, seed_value: int, f0: float, f_mid: float, f1: float,
		flutter_hz: float, flutter_depth: float) -> PackedFloat32Array:
	var out := SfxDsp.lowpass(SfxDsp.lowpass(SfxDsp.noise(seconds, SfxDsp.rng(seed_value)),
			f0, f_mid), f_mid, f1)
	if flutter_depth > 0.0:
		SfxDsp.flutter(out, SfxDsp.rng(seed_value + 1000), flutter_hz, flutter_depth)
	return out


## Brasas: chisporroteo agudo que se va apagando.
static func _embers(seconds: float, seed_value: int, per_second: float,
		half_life: float) -> PackedFloat32Array:
	var out := SfxDsp.highpass(SfxDsp.crackle(seconds, SfxDsp.rng(seed_value), per_second, 0.006),
			1400.0, 1400.0)
	SfxDsp.exp_decay(out, half_life)
	return out
