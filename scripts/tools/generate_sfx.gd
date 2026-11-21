extends SceneTree
## Sintetizador de efectos fuera de línea: genera cada sonido del juego como
## wav original PCM de 16 bits, mono, 44.1 kHz, desde cero, con bloques de
## DSP básicos (osciladores, ruido blanco, filtros, envolventes, barridos de
## tono). No se samplea audio externo. Determinista: cada capa de ruido usa
## su propia semilla fija, así volver a correrlo escribe bytes idénticos. Los
## bloques viven en SfxDsp y las recetas de los ataques de Mythos en SfxMythos
## (los dos en scripts/tools/generate_sfx/); las demás recetas están aquí.
## Córrelo desde la raíz del proyecto cada vez que cambies una receta:
##
##     godot --headless --path . -s res://scripts/tools/generate_sfx.gd
##
## Salida: assets/audio/sfx/*.wav (sonidos de un disparo y los bucles) y
## assets/audio/ambient/*.wav (los fondos de viento de cada mapa y el de fuego).
## Los sonidos en bucle no traen metadatos de bucle: Sfx y AmbientBed fuerzan
## LOOP_FORWARD sobre su propia COPIA del stream importado.
##
## Pendiente: los wav del repo no son los que escribe esta versión;
## regenerarlos cambia como mucho 1 LSB por muestra.

const RATE := SfxDsp.RATE
const SFX_DIR := "res://assets/audio/sfx"
const AMBIENT_DIR := "res://assets/audio/ambient"

## Las formas de onda de SfxDsp, con el nombre corto que usan las recetas.
const Wave := SfxDsp.Wave

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
	_save_wav(SFX_DIR, "heal", _gen_heal())
	_save_wav(SFX_DIR, "level_up", _gen_level_up())
	_save_wav(SFX_DIR, "card_pick", _gen_card_pick())
	_save_wav(SFX_DIR, "player_hurt", _gen_player_hurt())
	_save_wav(SFX_DIR, "dodge", _gen_dodge())
	_save_wav(SFX_DIR, "slide", _gen_slide())
	_save_wav(SFX_DIR, "shrine_channel", _gen_shrine_channel())
	_save_wav(SFX_DIR, "shrine_done", _gen_shrine_done())
	_save_wav(SFX_DIR, "chest_open", _gen_chest_open())
	_save_wav(SFX_DIR, "boss_roar", _gen_boss_roar())
	_save_wav(SFX_DIR, "boss_roar_2", _gen_boss_roar_2())
	_save_wav(SFX_DIR, "lobster_roar", _gen_lobster_roar())
	_save_wav(SFX_DIR, "lobster_chitter", _gen_lobster_chitter())
	_save_wav(SFX_DIR, "lobster_snap", _gen_lobster_snap())
	_save_wav(SFX_DIR, "lobster_hiss", _gen_lobster_hiss())
	_save_wav(SFX_DIR, "lobster_slam", _gen_lobster_slam())
	_save_wav(SFX_DIR, "lobster_dig", _gen_lobster_dig())
	_save_wav(SFX_DIR, "lobster_rumble", _gen_lobster_rumble())
	_save_wav(SFX_DIR, "lobster_whoosh", _gen_lobster_whoosh())
	_save_wav(SFX_DIR, "lobster_lock", _gen_lobster_lock())
	_save_wav(SFX_DIR, "lobster_death", _gen_lobster_death())
	_save_wav(SFX_DIR, "lobster_scare", _gen_lobster_scare())
	_save_wav(SFX_DIR, "boss_die", _gen_boss_die())
	_save_wav(SFX_DIR, "streak", _gen_streak())
	_save_wav(SFX_DIR, "laser_hum", _gen_laser_hum())
	_save_wav(SFX_DIR, "burrow_pop", _gen_burrow_pop())
	_save_wav(SFX_DIR, "secret_fanfare", _gen_secret_fanfare())
	_save_wav(SFX_DIR, "phoenix_cry", _gen_phoenix_cry())
	_save_wav(SFX_DIR, "phoenix_rebirth", _gen_phoenix_rebirth())
	_save_wav(SFX_DIR, "fire_whoosh", _gen_fire_whoosh())
	_save_wav(SFX_DIR, "fire_feathers", SfxMythos.fire_feathers())
	_save_wav(SFX_DIR, "phoenix_nova", SfxMythos.phoenix_nova())
	_save_wav(SFX_DIR, "phoenix_call", _gen_phoenix_call())
	_save_wav(SFX_DIR, "phoenix_screech", _gen_phoenix_screech())
	_save_wav(SFX_DIR, "phoenix_caw", _gen_phoenix_caw())
	_save_wav(SFX_DIR, "phoenix_dive", _gen_phoenix_dive())
	_save_wav(SFX_DIR, "phoenix_breath", SfxMythos.phoenix_breath())
	_save_wav(SFX_DIR, "phoenix_flap", _gen_phoenix_flap())
	_save_wav(SFX_DIR, "phoenix_step", _gen_phoenix_step())
	_save_wav(SFX_DIR, "phoenix_hurt", _gen_phoenix_hurt())
	_save_wav(SFX_DIR, "phoenix_death", _gen_phoenix_death())
	_save_wav(SFX_DIR, "phoenix_ascend", _gen_phoenix_ascend())
	_save_wav(SFX_DIR, "fireball_cast", SfxMythos.fireball_cast())
	_save_wav(SFX_DIR, "fireball_blast", SfxMythos.fireball_blast())
	_save_wav(SFX_DIR, "fire_tornado", SfxMythos.fire_tornado())
	_save_wav(SFX_DIR, "claw_swipe", SfxMythos.claw_swipe())
	_save_wav(SFX_DIR, "dive_impact", SfxMythos.dive_impact())
	_save_wav(SFX_DIR, "dive_fall", SfxMythos.dive_fall())
	_save_wav(SFX_DIR, "wing_blast", SfxMythos.wing_blast())
	_save_wav(SFX_DIR, "strafe_pass", SfxMythos.strafe_pass())
	_save_wav(SFX_DIR, "fire_blink", SfxMythos.fire_blink())
	_save_wav(SFX_DIR, "fireball_fall", SfxMythos.fireball_fall())
	_save_wav(SFX_DIR, "zone_ignite", SfxMythos.zone_ignite())
	_save_wav(SFX_DIR, "fire_wave", SfxMythos.fire_wave())
	_save_wav(SFX_DIR, "ring_blast", SfxMythos.ring_blast())
	_save_wav(SFX_DIR, "tornado_burst", SfxMythos.tornado_burst())
	_save_wav(SFX_DIR, "breath_inhale", SfxMythos.breath_inhale())
	_save_wav(SFX_DIR, "dawn_riser", SfxMythos.dawn_riser())
	_save_wav(AMBIENT_DIR, "forest_wind", _gen_forest_wind())
	_save_wav(AMBIENT_DIR, "desert_wind", _gen_desert_wind())
	_save_wav(AMBIENT_DIR, "hell_fire", _gen_hell_fire())
	if _failed:
		quit(1)
		return
	print("SFX generation complete.")
	quit(0)


# --- Recetas de sonido -------------------------------------------------------

## Golpe sordo para los golpes normales de arma: suena todo el tiempo, así que
## es bajo, corto y casi todo ruido filtrado sobre una caída de seno chica.
func _gen_hit_soft() -> PackedFloat32Array:
	var out := _tone(0.09, 150.0, 92.0, Wave.SINE)
	_mix_at(out, _lowpass(_noise(0.09, _rng(11)), 750.0, 220.0), 0.0, 0.8)
	_exp_decay(out, 0.03)
	_fade_in(out, 0.003)
	_fade_out(out, 0.02)
	_normalize(out, 0.55)
	return out


## Chasquido de crítico más agudo: barrido rápido de sierra hacia arriba con
## un transitorio de ruido brillante.
func _gen_hit_crit() -> PackedFloat32Array:
	var out := _tone(0.14, 620.0, 1500.0, Wave.SAW, 0.6)
	_mix_at(out, _lowpass(_noise(0.05, _rng(22)), 7000.0, 2500.0), 0.0, 0.5)
	_exp_decay(out, 0.04)
	_fade_in(out, 0.001)
	_fade_out(out, 0.03)
	_normalize(out, 0.9)
	return out


## Blip cuadrado cómico que baja, más un soplo de polvo.
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


## Gorjeo brillante de dos notas que sube (Mi6 -> Si6).
func _gen_gem_pickup() -> PackedFloat32Array:
	var out := _silence(0.13)
	_mix_at(out, _chime(0.07, 1318.5, 0.03), 0.0, 1.0)
	_mix_at(out, _chime(0.08, 1975.5, 0.035), 0.05, 0.9)
	_normalize(out, 0.7)
	return out


## Recoger un orbe de curación: un Sol4-Re5-Sol5 arpegiado y cálido, más
## grave y redondo que el gorjeo de gem_pickup para que la cura se distinga
## de la XP en plena horda (y en otra tonalidad que el arpegio de level_up).
func _gen_heal() -> PackedFloat32Array:
	var out := _silence(0.32)
	_mix_at(out, _chime(0.18, 392.0, 0.06), 0.0, 0.9)
	_mix_at(out, _chime(0.22, 587.33, 0.07), 0.07, 0.85)
	_mix_at(out, _chime(0.24, 783.99, 0.08), 0.14, 0.7)
	_normalize(out, 0.7)
	return out


## Arpegio Do5-Mi5-Sol5 que sube, con un brillo de octava en la nota alta.
func _gen_level_up() -> PackedFloat32Array:
	var out := _silence(0.5)
	_mix_at(out, _chime(0.2, 523.25, 0.07), 0.0, 1.0)
	_mix_at(out, _chime(0.2, 659.26, 0.07), 0.12, 1.0)
	_mix_at(out, _chime(0.26, 783.99, 0.1), 0.24, 1.0)
	_mix_at(out, _chime(0.26, 1046.5, 0.1), 0.24, 0.4)
	_normalize(out, 0.85)
	return out


## Clic-campanita afirmativo y suave: un tic de ruido corto y un La5.
func _gen_card_pick() -> PackedFloat32Array:
	var out := _silence(0.16)
	var click := _lowpass(_noise(0.015, _rng(44)), 4000.0, 2000.0)
	_exp_decay(click, 0.006)
	_fade_in(click, 0.001)
	_mix_at(out, click, 0.0, 0.6)
	_mix_at(out, _chime(0.14, 880.0, 0.045), 0.012, 0.8)
	_normalize(out, 0.7)
	return out


## Golpe grave y apagado que baja, para recibir un golpe.
func _gen_player_hurt() -> PackedFloat32Array:
	var out := _tone(0.26, 150.0, 68.0, Wave.SINE, 1.2)
	_mix_at(out, _lowpass(_noise(0.26, _rng(55)), 400.0, 160.0), 0.0, 0.6)
	_exp_decay(out, 0.08)
	_fade_in(out, 0.002)
	_fade_out(out, 0.05)
	_normalize(out, 0.85)
	return out


## Silbido de aire: ruido bajo un pasa-bajos que se abre, crece y cae.
func _gen_dodge() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.3, _rng(66)), 500.0, 7500.0)
	_adsr(out, 0.1, 0.19, 0.0, 0.0)
	_fade_out(out, 0.03)
	_normalize(out, 0.6)
	return out


## Silbido más grave y algo más largo para el inicio del derrape.
func _gen_slide() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.35, _rng(77)), 320.0, 1700.0)
	_adsr(out, 0.08, 0.24, 0.0, 0.0)
	_fade_out(out, 0.03)
	_normalize(out, 0.5)
	return out


## Zumbido suave de santuario, en bucle: cada parcial completa ciclos
## enteros en el bucle de 1.5 s (f = k / 1.5) y el trémolo hace exactamente
## 3 ciclos, así el empalme es continuo en fase sin mezclar.
func _gen_shrine_channel() -> PackedFloat32Array:
	var out := _tone(1.5, 110.0, 110.0, Wave.SINE)
	_mix_at(out, _tone(1.5, 167.0 / 1.5, 167.0 / 1.5, Wave.SINE), 0.0, 0.55)
	_mix_at(out, _tone(1.5, 220.0, 220.0, Wave.SINE), 0.0, 0.28)
	_mix_at(out, _tone(1.5, 496.0 / 1.5, 496.0 / 1.5, Wave.SINE), 0.0, 0.14)
	_tremolo(out, 2.0, 0.3)
	_normalize(out, 0.5)
	return out


## Campanita cálida y resuelta: Do mayor arpegiado (estado fundamental) con
## una octava arriba.
func _gen_shrine_done() -> PackedFloat32Array:
	var out := _silence(0.7)
	_mix_at(out, _chime(0.5, 523.25, 0.12), 0.0, 1.0)
	_mix_at(out, _chime(0.5, 659.26, 0.12), 0.045, 1.0)
	_mix_at(out, _chime(0.55, 783.99, 0.14), 0.09, 1.0)
	_mix_at(out, _chime(0.55, 1046.5, 0.14), 0.09, 0.35)
	_normalize(out, 0.8)
	return out


## La misma familia de acorde que shrine_done pero en primera inversión,
## para que los dos sonidos de completado suenen hermanos sin ser iguales.
func _gen_chest_open() -> PackedFloat32Array:
	var out := _silence(0.7)
	_mix_at(out, _chime(0.5, 659.26, 0.12), 0.0, 1.0)
	_mix_at(out, _chime(0.5, 783.99, 0.12), 0.045, 1.0)
	_mix_at(out, _chime(0.55, 1046.5, 0.14), 0.09, 1.0)
	_mix_at(out, _chime(0.55, 1318.5, 0.14), 0.09, 0.3)
	_normalize(out, 0.8)
	return out


## Voz de monstruo original: sierras graves desafinadas que suben y bajan
## de tono, un seno sub, ruido de aliento y un gruñido de amplitud a 13 Hz,
## oscurecido con un pasa-bajos.
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


## Voz del Sarcognato: la familia de boss_roar en un registro de piedra más
## hueco — sierras más graves con otros puntos de quiebre, un sub cuadrado
## para el traqueteo del sarcófago, más aliento y un gruñido más lento de
## 9 Hz, para que los dos jefes suenen parientes y no clones.
func _gen_boss_roar_2() -> PackedFloat32Array:
	var out := _tone3(2.0, 48.0, 78.0, 36.0, Wave.SAW)
	_mix_at(out, _tone3(2.0, 49.0, 79.6, 36.8, Wave.SAW), 0.0, 0.7)
	_mix_at(out, _tone3(2.0, 24.0, 39.0, 18.0, Wave.SQUARE), 0.0, 0.3)
	_mix_at(out, _lowpass(_noise(2.0, _rng(155)), 1300.0, 380.0), 0.0, 0.45)
	out = _lowpass(out, 1400.0, 1400.0)
	_tremolo(out, 9.0, 0.45)
	_adsr(out, 0.15, 0.35, 0.8, 0.5)
	_normalize(out, 0.95)
	return out


## Un chasquido de pinza: un clic seco de ruido sobre un golpe hueco que cae
## de tono. Es la base de los sonidos de la Langosta Azul.
func _claw_click(pitch: float, seed_value: int) -> PackedFloat32Array:
	var out := _tone(0.07, pitch, pitch * 0.35, Wave.TRIANGLE, 0.5)
	_mix_at(out, _lowpass(_noise(0.02, _rng(seed_value)), 9000.0, 5000.0), 0.0, 0.9)
	_exp_decay(out, 0.012)
	_fade_in(out, 0.0008)
	_fade_out(out, 0.01)
	return out


## Rugido con que la Langosta Azul empieza la pelea: un gruñido grave y
## áspero que traquetea, con un siseo y un tableteo de pinzas encima.
func _gen_lobster_roar() -> PackedFloat32Array:
	var out := _tone3(1.5, 85.0, 130.0, 60.0, Wave.SAW)
	_mix_at(out, _tone3(1.5, 86.6, 132.5, 61.2, Wave.SAW), 0.0, 0.7)
	_mix_at(out, _tone3(1.5, 42.5, 65.0, 30.0, Wave.SQUARE), 0.0, 0.35)
	_mix_at(out, _lowpass(_noise(1.5, _rng(520)), 5200.0, 1800.0), 0.0, 0.5)
	out = _lowpass(out, 2600.0, 1500.0)
	_tremolo(out, 26.0, 0.6)
	_adsr(out, 0.06, 0.25, 0.85, 0.4)
	for i in 6:
		_mix_at(out, _claw_click(1600.0, 521 + i), 0.12 + 0.11 * float(i), 0.35)
	_normalize(out, 0.95)
	return out


## Llamado suelto de la Langosta Azul: un tableteo de clics que se acelera.
func _gen_lobster_chitter() -> PackedFloat32Array:
	var out := _silence(0.6)
	var at := 0.0
	var gap := 0.085
	for i in 9:
		_mix_at(out, _claw_click(1900.0 - 90.0 * float(i), 510 + i), at, 0.55 + 0.05 * float(i))
		at += gap
		gap *= 0.86
	_normalize(out, 0.7)
	return out


## Pinzazo: dos clics pegados (abre y cierra) y un golpe grave.
func _gen_lobster_snap() -> PackedFloat32Array:
	var out := _silence(0.22)
	_mix_at(out, _claw_click(1500.0, 501), 0.0, 0.7)
	_mix_at(out, _claw_click(900.0, 502), 0.045, 1.0)
	var thud := _tone(0.16, 190.0, 70.0, Wave.SINE, 0.6)
	_exp_decay(thud, 0.04)
	_mix_at(out, thud, 0.045, 0.8)
	_normalize(out, 0.9)
	return out


## Siseo cuando un golpe le duele: ruido que se aclara y se corta.
func _gen_lobster_hiss() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.38, _rng(530)), 2500.0, 7500.0)
	_mix_at(out, _tone(0.38, 700.0, 380.0, Wave.SAW, 0.6), 0.0, 0.18)
	_tremolo(out, 55.0, 0.35)
	_adsr(out, 0.02, 0.1, 0.6, 0.18)
	_normalize(out, 0.7)
	return out


## Golpe del Salto y de la Emboscada: un bombazo grave, tierra que cae y el
## crujido del caparazón.
func _gen_lobster_slam() -> PackedFloat32Array:
	var out := _tone(0.9, 120.0, 34.0, Wave.SINE, 0.5)
	_mix_at(out, _tone(0.9, 62.0, 22.0, Wave.SQUARE, 0.5), 0.0, 0.2)
	_mix_at(out, _lowpass(_noise(0.9, _rng(540)), 4200.0, 220.0), 0.0, 0.8)
	_exp_decay(out, 0.2)
	_mix_at(out, _claw_click(700.0, 541), 0.0, 0.8)
	_fade_in(out, 0.002)
	_fade_out(out, 0.1)
	_normalize(out, 0.95)
	return out


## Se entierra: grava que raspa, cada vez más apagada.
func _gen_lobster_dig() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.8, _rng(550)), 3200.0, 500.0)
	_tremolo(out, 17.0, 0.7)
	_mix_at(out, _tone(0.8, 90.0, 48.0, Wave.SINE), 0.0, 0.35)
	_adsr(out, 0.03, 0.2, 0.7, 0.3)
	_normalize(out, 0.75)
	return out


## Aviso de que va a salir de la tierra: un temblor grave que crece.
func _gen_lobster_rumble() -> PackedFloat32Array:
	var out := _tone(0.6, 38.0, 64.0, Wave.SINE)
	_mix_at(out, _tone(0.6, 57.0, 96.0, Wave.TRIANGLE), 0.0, 0.5)
	_mix_at(out, _lowpass(_noise(0.6, _rng(560)), 300.0, 900.0), 0.0, 0.7)
	_tremolo(out, 22.0, 0.55)
	_fade_in(out, 0.4)
	_fade_out(out, 0.05)
	_normalize(out, 0.85)
	return out


## Embestida y Coletazo: un barrido de aire corto y grave.
func _gen_lobster_whoosh() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.42, _rng(570)), 400.0, 3600.0)
	out = _lowpass(out, 3600.0, 700.0)
	_mix_at(out, _tone(0.42, 150.0, 60.0, Wave.SINE, 0.7), 0.0, 0.3)
	_adsr(out, 0.08, 0.1, 0.8, 0.2)
	_normalize(out, 0.75)
	return out


## Un aviso se clava: dos clics agudos y secos.
func _gen_lobster_lock() -> PackedFloat32Array:
	var out := _silence(0.2)
	_mix_at(out, _claw_click(2600.0, 580), 0.0, 0.9)
	_mix_at(out, _claw_click(3100.0, 581), 0.075, 1.0)
	_normalize(out, 0.7)
	return out


## Muerte de la Langosta Azul: el gruñido se desinfla con un gorgoteo y el
## caparazón cruje cada vez más grave.
func _gen_lobster_death() -> PackedFloat32Array:
	var out := _tone(1.7, 140.0, 30.0, Wave.SAW, 0.6)
	_mix_at(out, _tone(1.7, 71.0, 15.5, Wave.SQUARE, 0.6), 0.0, 0.3)
	_mix_at(out, _lowpass(_noise(1.7, _rng(590)), 3000.0, 200.0), 0.0, 0.5)
	out = _lowpass(out, 2400.0, 500.0)
	_tremolo(out, 14.0, 0.65)
	_exp_decay(out, 0.55)
	for i in 5:
		_mix_at(out, _claw_click(1100.0 - 150.0 * float(i), 591 + i), 0.25 + 0.22 * float(i), 0.5)
	_fade_in(out, 0.004)
	_fade_out(out, 0.15)
	_normalize(out, 0.95)
	return out


## El susto del corte de su entrada cuando no hay canción: un chillido
## disonante que arranca de golpe sobre un golpe grave.
func _gen_lobster_scare() -> PackedFloat32Array:
	var out := _tone3(1.0, 1900.0, 2300.0, 700.0, Wave.SAW)
	_mix_at(out, _tone3(1.0, 2011.0, 2437.0, 742.0, Wave.SAW), 0.0, 0.8)
	_mix_at(out, _tone3(1.0, 950.0, 1150.0, 350.0, Wave.SQUARE), 0.0, 0.4)
	_mix_at(out, _lowpass(_noise(1.0, _rng(600)), 8000.0, 1500.0), 0.0, 0.6)
	_mix_at(out, _tone(1.0, 95.0, 40.0, Wave.SINE, 0.5), 0.0, 0.8)
	_tremolo(out, 31.0, 0.45)
	_adsr(out, 0.003, 0.25, 0.55, 0.5)
	_normalize(out, 0.95)
	return out


## Zumbido de rayo eléctrico, en bucle: cada parcial completa ciclos
## enteros en el bucle de 0.6 s (f = k / 0.6) y el aleteo hace exactamente 6
## ciclos, así el empalme es continuo en fase (el mismo truco que
## shrine_channel). La única parcial de sierra pone el zumbido "energizado".
func _gen_laser_hum() -> PackedFloat32Array:
	var out := _tone(0.6, 120.0, 120.0, Wave.SINE)
	_mix_at(out, _tone(0.6, 200.0, 200.0, Wave.SAW), 0.0, 0.22)
	_mix_at(out, _tone(0.6, 320.0, 320.0, Wave.SINE), 0.0, 0.3)
	_mix_at(out, _tone(0.6, 440.0, 440.0, Wave.SINE), 0.0, 0.12)
	_tremolo(out, 10.0, 0.2)
	_normalize(out, 0.45)
	return out


## Golpe apagado de erupción de arena: una caída rápida de seno grave bajo
## una ráfaga de ruido muy filtrado (la lluvia de tierra que se asienta).
func _gen_burrow_pop() -> PackedFloat32Array:
	var out := _tone(0.32, 130.0, 46.0, Wave.SINE, 0.7)
	_mix_at(out, _lowpass(_noise(0.28, _rng(144)), 1400.0, 260.0), 0.0, 0.75)
	_exp_decay(out, 0.07)
	_fade_in(out, 0.002)
	_fade_out(out, 0.05)
	_normalize(out, 0.85)
	return out


## Estruendo grande que baja, con una cola de ruido filtrado.
func _gen_boss_die() -> PackedFloat32Array:
	var out := _tone(1.5, 170.0, 34.0, Wave.SINE, 0.55)
	_mix_at(out, _tone(1.5, 90.0, 18.0, Wave.SQUARE, 0.55), 0.0, 0.25)
	_mix_at(out, _lowpass(_noise(1.5, _rng(99)), 3800.0, 130.0), 0.0, 0.55)
	_exp_decay(out, 0.45)
	_fade_in(out, 0.004)
	_fade_out(out, 0.12)
	_normalize(out, 0.95)
	return out


## Aviso de dos notas con golpe (cuadradas Sol4 -> Re5) y un chasquido.
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


## Fanfarria del jefe secreto: un "ta-da" en Sol mayor arpegiado que sube
## dos octavas, con un brillo tenue arriba y una fundamental cálida bajo la
## nota alta; en otra tonalidad y más abierto que el arpegio de level_up, así
## encontrar un secreto se celebra distinto.
func _gen_secret_fanfare() -> PackedFloat32Array:
	var out := _silence(1.1)
	_mix_at(out, _chime(0.3, 587.33, 0.1), 0.0, 0.9)
	_mix_at(out, _chime(0.3, 783.99, 0.1), 0.09, 0.95)
	_mix_at(out, _chime(0.34, 987.77, 0.12), 0.18, 1.0)
	_mix_at(out, _chime(0.55, 1174.66, 0.16), 0.27, 1.0)
	_mix_at(out, _chime(0.5, 2349.32, 0.14), 0.29, 0.28)
	_mix_at(out, _chime(0.5, 392.0, 0.15), 0.27, 0.5)
	_normalize(out, 0.85)
	return out


## Grito del fénix: dos sierras agudas desafinadas que suben y caen de tono
## con un trino rápido, sobre un soplo de ruido brillante. Agudo donde los
## rugidos de los otros jefes son graves.
func _gen_phoenix_cry() -> PackedFloat32Array:
	var out := _tone3(1.3, 1500.0, 2300.0, 950.0, Wave.SAW)
	_mix_at(out, _tone3(1.3, 1522.0, 2334.0, 964.0, Wave.SAW), 0.0, 0.7)
	_mix_at(out, _tone3(1.3, 750.0, 1150.0, 475.0, Wave.TRIANGLE), 0.0, 0.5)
	_mix_at(out, _lowpass(_noise(1.3, _rng(301)), 5200.0, 1800.0), 0.0, 0.35)
	out = _lowpass(out, 6500.0, 2600.0)
	_tremolo(out, 26.0, 0.45)
	_adsr(out, 0.04, 0.25, 0.75, 0.5)
	_normalize(out, 0.9)
	return out


## Renacer del fénix: un soplo que crece (ruido que se abre con una sierra
## que sube dos octavas) y estalla en una campana brillante con golpe grave.
func _gen_phoenix_rebirth() -> PackedFloat32Array:
	var out := _lowpass(_noise(1.5, _rng(331)), 300.0, 4200.0)
	_mix_at(out, _tone(0.9, 180.0, 720.0, Wave.SAW, 1.6), 0.0, 0.5)
	_adsr(out, 0.7, 0.1, 0.9, 0.5)
	_mix_at(out, _chime(0.7, 880.0, 0.16), 0.72, 1.0)
	_mix_at(out, _chime(0.7, 1318.5, 0.16), 0.72, 0.7)
	_mix_at(out, _tone(0.35, 140.0, 55.0, Wave.SINE), 0.72, 0.9)
	_normalize(out, 0.9)
	return out


## Llamarada: ruido que se abre y se cierra sobre un golpe grave. Suena
## cuando la ola de fuego barre a la horda al empezar la pelea de Mythos.
func _gen_fire_whoosh() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.55, _rng(311)), 350.0, 2600.0)
	out = _lowpass(out, 2600.0, 500.0)
	_mix_at(out, _tone(0.3, 110.0, 48.0, Wave.SINE), 0.0, 0.7)
	_adsr(out, 0.03, 0.12, 0.7, 0.3)
	_normalize(out, 0.7)
	return out


## Una voz de pájaro: dos sierras desafinadas y una triangular una octava
## abajo, de `f0` a `f1` pasando por `f_mid`, con el trino de la garganta.
## Es la base de todos los gritos cortos de Mythos.
func _bird_voice(duration: float, f0: float, f_mid: float, f1: float, trill_hz: float,
		trill_depth: float) -> PackedFloat32Array:
	var out := _tone3(duration, f0, f_mid, f1, Wave.SAW)
	_mix_at(out, _tone3(duration, f0 * 1.015, f_mid * 1.015, f1 * 1.015, Wave.SAW), 0.0, 0.7)
	_mix_at(out, _tone3(duration, f0 * 0.5, f_mid * 0.5, f1 * 0.5, Wave.TRIANGLE), 0.0, 0.45)
	out = _lowpass(out, 7000.0, 3000.0)
	_tremolo(out, trill_hz, trill_depth)
	return out


## Llamado suelto de Mythos: dos notas cortas, la segunda más alta.
func _gen_phoenix_call() -> PackedFloat32Array:
	var out := _silence(0.62)
	var first := _bird_voice(0.22, 1300.0, 1750.0, 1500.0, 30.0, 0.35)
	_adsr(first, 0.02, 0.06, 0.7, 0.1)
	var second := _bird_voice(0.3, 1650.0, 2300.0, 1800.0, 30.0, 0.35)
	_adsr(second, 0.02, 0.08, 0.7, 0.14)
	_mix_at(out, first, 0.0, 0.9)
	_mix_at(out, second, 0.28, 1.0)
	_normalize(out, 0.75)
	return out


## Chillido de ataque: sube de golpe y se sostiene áspero, con un soplo.
func _gen_phoenix_screech() -> PackedFloat32Array:
	var out := _bird_voice(0.62, 1400.0, 2700.0, 2200.0, 42.0, 0.55)
	_mix_at(out, _lowpass(_noise(0.62, _rng(351)), 6000.0, 2500.0), 0.0, 0.3)
	_adsr(out, 0.03, 0.12, 0.8, 0.22)
	_normalize(out, 0.85)
	return out


## Graznido de tierra: dos golpes roncos y graves, para las Garras.
func _gen_phoenix_caw() -> PackedFloat32Array:
	var out := _silence(0.5)
	for i in 2:
		var bark := _bird_voice(0.2, 900.0 - 80.0 * float(i), 1150.0, 700.0, 55.0, 0.7)
		_mix_at(bark, _lowpass(_noise(0.2, _rng(361 + i)), 3500.0, 1200.0), 0.0, 0.4)
		_adsr(bark, 0.01, 0.05, 0.6, 0.1)
		_mix_at(out, bark, 0.24 * float(i), 1.0)
	_normalize(out, 0.8)
	return out


## Grito de la Picada: un chillido largo que cae de tono mientras baja.
func _gen_phoenix_dive() -> PackedFloat32Array:
	var out := _bird_voice(0.85, 2600.0, 1900.0, 800.0, 36.0, 0.4)
	_mix_at(out, _lowpass(_noise(0.85, _rng(371)), 900.0, 5000.0), 0.0, 0.35)
	_adsr(out, 0.04, 0.2, 0.8, 0.25)
	_normalize(out, 0.85)
	return out


## Aletazo: un golpe de aire grave que se abre y se cierra rápido.
func _gen_phoenix_flap() -> PackedFloat32Array:
	var out := _lowpass(_noise(0.5, _rng(381)), 250.0, 2200.0)
	out = _lowpass(out, 2200.0, 300.0)
	_mix_at(out, _tone(0.3, 95.0, 45.0, Wave.SINE), 0.02, 0.8)
	_adsr(out, 0.05, 0.12, 0.5, 0.25)
	_normalize(out, 0.8)
	return out


## Pisada de Mythos en tierra: un golpe sordo y grave, con algo de grava.
func _gen_phoenix_step() -> PackedFloat32Array:
	var out := _tone(0.45, 84.0, 34.0, Wave.SINE, 0.6)
	_mix_at(out, _lowpass(_noise(0.3, _rng(613)), 1500.0, 160.0), 0.0, 0.5)
	_exp_decay(out, 0.1)
	_adsr(out, 0.004, 0.08, 0.7, 0.2)
	_normalize(out, 0.9)
	return out


## Chillido de dolor: corto, agudo y quebrado.
func _gen_phoenix_hurt() -> PackedFloat32Array:
	var out := _bird_voice(0.28, 2400.0, 2900.0, 1700.0, 60.0, 0.6)
	_adsr(out, 0.01, 0.06, 0.6, 0.12)
	_normalize(out, 0.7)
	return out


## Grito de su última muerte: largo, cae dos octavas y se deshace en soplo.
func _gen_phoenix_death() -> PackedFloat32Array:
	var out := _bird_voice(2.2, 2300.0, 1500.0, 420.0, 22.0, 0.5)
	_mix_at(out, _lowpass(_noise(2.2, _rng(391)), 5000.0, 400.0), 0.0, 0.4)
	_mix_at(out, _tone(1.4, 160.0, 50.0, Wave.SINE), 0.6, 0.5)
	_adsr(out, 0.05, 0.4, 0.75, 1.1)
	_normalize(out, 0.9)
	return out


## Renacer de la segunda fase: un rugido de fuego que crece dos segundos y
## medio, con la voz del fénix subiendo encima hasta el estallido.
func _gen_phoenix_ascend() -> PackedFloat32Array:
	var out := _lowpass(_noise(4.4, _rng(401)), 200.0, 5200.0)
	_mix_at(out, _tone(4.2, 60.0, 240.0, Wave.SAW, 1.8), 0.0, 0.45)
	_fade_in(out, 2.6)
	var voice := _bird_voice(2.4, 700.0, 1500.0, 2900.0, 26.0, 0.45)
	_fade_in(voice, 1.2)
	_mix_at(out, voice, 1.9, 0.8)
	_fade_out(out, 0.25)
	_normalize(out, 0.9)
	return out


## Fondo de viento de bosque muy suave, bucle de 4 s. Se genera 0.35 s más
## largo y la cola sobrante se funde con el inicio (_loop_blend) para
## esconder el salto del filtro en el empalme. Los dos LFO completan ciclos
## enteros en los 4 s, así su fase coincide en la costura.
func _gen_forest_wind() -> PackedFloat32Array:
	var out := _lowpass_lfo(_noise(4.35, _rng(123)), 520.0, 320.0, 0.5)
	_tremolo(out, 0.25, 0.25)
	var looped := _loop_blend(out, 0.35)
	_normalize(looped, 0.35)
	return looped


## Fondo de viento de las Dunas de Ceniza, más seco, con el mismo bucle de
## 4 s que el del bosque pero un siseo más agudo y ancho con aleteo más
## rápido: se lee como arena y no como follaje. El LFO de 0.75 Hz y el
## trémolo de 0.5 Hz hacen ciclos enteros en los 4 s.
func _gen_desert_wind() -> PackedFloat32Array:
	var out := _lowpass_lfo(_noise(4.35, _rng(137)), 950.0, 550.0, 0.75)
	_tremolo(out, 0.5, 0.35)
	var looped := _loop_blend(out, 0.35)
	_normalize(looped, 0.3)
	return looped


## Fondo de fuego del bosque en llamas, bucle de 4 s como los vientos: un
## rugido de ruido grave que respira y chasquidos de brasas repartidos con
## su propia semilla. El LFO de 0.75 Hz y el trémolo de 0.5 Hz hacen ciclos
## enteros en los 4 s, y la cola sobrante se funde con el inicio.
func _gen_hell_fire() -> PackedFloat32Array:
	var out := _lowpass_lfo(_noise(4.35, _rng(341)), 420.0, 260.0, 0.75)
	var crackle_rng := _rng(342)
	for i in 70:
		var click := _noise(0.02, crackle_rng)
		_exp_decay(click, 0.004)
		_mix_at(out, click, crackle_rng.randf_range(0.0, 4.3),
				crackle_rng.randf_range(0.15, 0.5))
	_tremolo(out, 0.5, 0.25)
	var looped := _loop_blend(out, 0.35)
	_normalize(looped, 0.4)
	return looped


# --- Bloques de DSP -----------------------------------------------------------
# Viven en SfxDsp (scripts/tools/generate_sfx/sfx_dsp.gd), que los explica uno
# por uno; estos son los nombres cortos con que los llaman las recetas de
# este archivo.

func _rng(seed_value: int) -> RandomNumberGenerator:
	return SfxDsp.rng(seed_value)


func _silence(duration: float) -> PackedFloat32Array:
	return SfxDsp.silence(duration)


func _osc(wave: SfxDsp.Wave, phase: float) -> float:
	return SfxDsp.osc(wave, phase)


func _tone(duration: float, f0: float, f1: float, wave: SfxDsp.Wave,
		curve: float = 1.0) -> PackedFloat32Array:
	return SfxDsp.tone(duration, f0, f1, wave, curve)


func _tone3(duration: float, f0: float, f_mid: float, f1: float,
		wave: SfxDsp.Wave) -> PackedFloat32Array:
	return SfxDsp.tone3(duration, f0, f_mid, f1, wave)


func _noise(duration: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	return SfxDsp.noise(duration, rng)


func _chime(duration: float, freq: float, half_life: float) -> PackedFloat32Array:
	return SfxDsp.chime(duration, freq, half_life)


func _lowpass(samples: PackedFloat32Array, cutoff_start: float,
		cutoff_end: float) -> PackedFloat32Array:
	return SfxDsp.lowpass(samples, cutoff_start, cutoff_end)


func _lowpass_lfo(samples: PackedFloat32Array, base: float, depth: float,
		lfo_hz: float) -> PackedFloat32Array:
	return SfxDsp.lowpass_lfo(samples, base, depth, lfo_hz)


func _tremolo(samples: PackedFloat32Array, hz: float, depth: float) -> void:
	SfxDsp.tremolo(samples, hz, depth)


func _exp_decay(samples: PackedFloat32Array, half_life: float) -> void:
	SfxDsp.exp_decay(samples, half_life)


func _adsr(samples: PackedFloat32Array, attack: float, decay: float,
		sustain: float, release: float) -> void:
	SfxDsp.adsr(samples, attack, decay, sustain, release)


func _fade_in(samples: PackedFloat32Array, seconds: float) -> void:
	SfxDsp.fade_in(samples, seconds)


func _fade_out(samples: PackedFloat32Array, seconds: float) -> void:
	SfxDsp.fade_out(samples, seconds)


func _mix_at(dst: PackedFloat32Array, src: PackedFloat32Array,
		at_seconds: float, gain: float) -> void:
	SfxDsp.mix_at(dst, src, at_seconds, gain)


func _normalize(samples: PackedFloat32Array, peak: float) -> void:
	SfxDsp.normalize(samples, peak)


func _loop_blend(samples: PackedFloat32Array, blend_seconds: float) -> PackedFloat32Array:
	return SfxDsp.loop_blend(samples, blend_seconds)


# --- Salida -------------------------------------------------------------------

func _save_wav(dir: String, sound_name: String, samples: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		# roundi y no int(): truncar tira cada muestra hacia cero hasta 1 LSB,
		# un error de cuantización asimétrico que se nota más justo donde
		# estos archivos son más suaves (los bucles largos y graves).
		bytes.encode_s16(i * 2, roundi(clampf(samples[i], -1.0, 1.0) * 32767.0))
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
