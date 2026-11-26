class_name SoundLibrary
extends RefCounted
## Catálogo de sonidos del autoload Sfx (sfx.gd), que lo publica como
## Sfx.SOUND_LIBRARY: una fila por id.
##
## Edita aquí cada sonido. El id es la llave que pasan Sfx.play(&"id") y
## acquire_loop(&"id") y la que guardan los exports de sonido de escenas y
## scripts: renombrarlo rompe a quien lo llama (el lint de catálogos revisa
## que cada id escrito exista). Campos, todos libres de editar:
##   stream:     el .wav (los genera scripts/tools/generate_sfx.gd).
##   volume_db:  volumen base en dB; el volume_db_offset de play() se suma.
##   rate_limit: OPCIONAL, tope de reproducciones por segundo móvil (sin el
##               campo, sin tope), para que la horda no sature.
##   jitter:     OPCIONAL, true = variación de tono al azar
##               (default_pitch_jitter de Sfx) cuando play() no pide otra.
##   loop:       OPCIONAL, true = id de play_loop(): Sfx hace en su _ready una
##               copia en bucle, porque los wav generados no traen metadatos.

const ROWS: Dictionary[StringName, Dictionary] = {
	&"hit_soft": {
		"stream": preload("res://assets/audio/sfx/hit_soft.wav"), "volume_db": -14.0,
		"rate_limit": 10, "jitter": true,
	},
	&"hit_crit": {
		"stream": preload("res://assets/audio/sfx/hit_crit.wav"), "volume_db": -7.0,
		"rate_limit": 10, "jitter": true,
	},
	&"enemy_die": {
		"stream": preload("res://assets/audio/sfx/enemy_die.wav"), "volume_db": -10.0,
		"rate_limit": 12, "jitter": true,
	},
	&"gem_pickup": {
		"stream": preload("res://assets/audio/sfx/gem_pickup.wav"), "volume_db": -12.0,
		"rate_limit": 10, "jitter": true,
	},
	&"heal": {
		"stream": preload("res://assets/audio/sfx/heal.wav"), "volume_db": -7.0,
		"rate_limit": 4, "jitter": true,
	},
	&"level_up": {
		"stream": preload("res://assets/audio/sfx/level_up.wav"), "volume_db": -4.0,
	},
	&"card_pick": {
		"stream": preload("res://assets/audio/sfx/card_pick.wav"), "volume_db": -6.0,
	},
	&"player_hurt": {
		"stream": preload("res://assets/audio/sfx/player_hurt.wav"), "volume_db": -5.0,
		"rate_limit": 6,
	},
	&"dodge": {
		"stream": preload("res://assets/audio/sfx/dodge.wav"), "volume_db": -8.0,
	},
	&"slide": {
		"stream": preload("res://assets/audio/sfx/slide.wav"), "volume_db": -10.0,
	},
	&"shrine_channel": {
		"stream": preload("res://assets/audio/sfx/shrine_channel.wav"), "volume_db": -10.0,
		"loop": true,
	},
	&"shrine_done": {
		"stream": preload("res://assets/audio/sfx/shrine_done.wav"), "volume_db": -5.0,
	},
	&"chest_open": {
		"stream": preload("res://assets/audio/sfx/chest_open.wav"), "volume_db": -5.0,
	},
	&"boss_roar": {
		"stream": preload("res://assets/audio/sfx/boss_roar.wav"), "volume_db": -3.0,
	},
	&"boss_roar_2": {
		"stream": preload("res://assets/audio/sfx/boss_roar_2.wav"), "volume_db": -3.0,
	},
	&"lobster_roar": {
		"stream": preload("res://assets/audio/sfx/lobster_roar.wav"), "volume_db": -3.0,
	},
	&"lobster_chitter": {
		"stream": preload("res://assets/audio/sfx/lobster_chitter.wav"), "volume_db": -9.0,
		"rate_limit": 2, "jitter": true,
	},
	&"lobster_snap": {
		"stream": preload("res://assets/audio/sfx/lobster_snap.wav"), "volume_db": -6.0,
		"rate_limit": 6, "jitter": true,
	},
	&"lobster_hiss": {
		"stream": preload("res://assets/audio/sfx/lobster_hiss.wav"), "volume_db": -8.0,
		"rate_limit": 2, "jitter": true,
	},
	&"lobster_slam": {
		"stream": preload("res://assets/audio/sfx/lobster_slam.wav"), "volume_db": -3.0,
		"rate_limit": 3,
	},
	&"lobster_dig": {
		"stream": preload("res://assets/audio/sfx/lobster_dig.wav"), "volume_db": -7.0,
		"rate_limit": 2,
	},
	&"lobster_rumble": {
		"stream": preload("res://assets/audio/sfx/lobster_rumble.wav"), "volume_db": -5.0,
		"rate_limit": 2,
	},
	&"lobster_whoosh": {
		"stream": preload("res://assets/audio/sfx/lobster_whoosh.wav"), "volume_db": -7.0,
		"rate_limit": 4, "jitter": true,
	},
	&"lobster_lock": {
		"stream": preload("res://assets/audio/sfx/lobster_lock.wav"), "volume_db": -7.0,
		"rate_limit": 4,
	},
	&"lobster_death": {
		"stream": preload("res://assets/audio/sfx/lobster_death.wav"), "volume_db": -2.0,
	},
	&"lobster_scare": {
		"stream": preload("res://assets/audio/sfx/lobster_scare.wav"), "volume_db": -1.0,
	},
	&"omen_swell": {
		"stream": preload("res://assets/audio/sfx/omen_swell.wav"), "volume_db": -4.0,
	},
	&"abduction_geyser": {
		"stream": preload("res://assets/audio/sfx/abduction_geyser.wav"), "volume_db": -7.0,
		"rate_limit": 8, "jitter": true,
	},
	&"abduction_whirlpool": {
		"stream": preload("res://assets/audio/sfx/abduction_whirlpool.wav"), "volume_db": -3.0,
	},
	&"abduction_flood": {
		"stream": preload("res://assets/audio/sfx/abduction_flood.wav"), "volume_db": -2.0,
	},
	&"seabed_landing": {
		"stream": preload("res://assets/audio/sfx/seabed_landing.wav"), "volume_db": -4.0,
	},
	&"return_portal": {
		"stream": preload("res://assets/audio/sfx/return_portal.wav"), "volume_db": -5.0,
	},
	&"boss_die": {
		"stream": preload("res://assets/audio/sfx/boss_die.wav"), "volume_db": -2.0,
	},
	&"streak": {
		"stream": preload("res://assets/audio/sfx/streak.wav"), "volume_db": -6.0,
	},
	&"laser_hum": {
		"stream": preload("res://assets/audio/sfx/laser_hum.wav"), "volume_db": -16.0,
		"loop": true,
	},
	&"burrow_pop": {
		"stream": preload("res://assets/audio/sfx/burrow_pop.wav"), "volume_db": -8.0,
		"rate_limit": 8, "jitter": true,
	},
	&"secret_fanfare": {
		"stream": preload("res://assets/audio/sfx/secret_fanfare.wav"), "volume_db": -3.0,
	},
	&"phoenix_cry": {
		"stream": preload("res://assets/audio/sfx/phoenix_cry.wav"), "volume_db": -4.0,
	},
	&"phoenix_rebirth": {
		"stream": preload("res://assets/audio/sfx/phoenix_rebirth.wav"), "volume_db": -4.0,
	},
	&"fire_whoosh": {
		"stream": preload("res://assets/audio/sfx/fire_whoosh.wav"), "volume_db": -9.0,
		"rate_limit": 5,
	},
	&"fire_feathers": {
		"stream": preload("res://assets/audio/sfx/fire_feathers.wav"), "volume_db": -8.0,
		"rate_limit": 4,
	},
	&"phoenix_nova": {
		"stream": preload("res://assets/audio/sfx/phoenix_nova.wav"), "volume_db": -3.0,
	},
	&"phoenix_call": {
		"stream": preload("res://assets/audio/sfx/phoenix_call.wav"), "volume_db": -9.0,
		"rate_limit": 2, "jitter": true,
	},
	&"phoenix_screech": {
		"stream": preload("res://assets/audio/sfx/phoenix_screech.wav"), "volume_db": -6.0,
		"rate_limit": 3, "jitter": true,
	},
	&"phoenix_caw": {
		"stream": preload("res://assets/audio/sfx/phoenix_caw.wav"), "volume_db": -6.0,
		"rate_limit": 3, "jitter": true,
	},
	&"phoenix_dive": {
		"stream": preload("res://assets/audio/sfx/phoenix_dive.wav"), "volume_db": -5.0,
		"rate_limit": 2,
	},
	&"phoenix_breath": {
		"stream": preload("res://assets/audio/sfx/phoenix_breath.wav"), "volume_db": -6.0,
	},
	&"phoenix_flap": {
		"stream": preload("res://assets/audio/sfx/phoenix_flap.wav"), "volume_db": -6.0,
		"rate_limit": 4, "jitter": true,
	},
	&"phoenix_step": {
		"stream": preload("res://assets/audio/sfx/phoenix_step.wav"), "volume_db": -7.0,
		"rate_limit": 4, "jitter": true,
	},
	&"phoenix_hurt": {
		"stream": preload("res://assets/audio/sfx/phoenix_hurt.wav"), "volume_db": -8.0,
		"rate_limit": 2, "jitter": true,
	},
	&"phoenix_death": {
		"stream": preload("res://assets/audio/sfx/phoenix_death.wav"), "volume_db": -3.0,
	},
	&"phoenix_ascend": {
		"stream": preload("res://assets/audio/sfx/phoenix_ascend.wav"), "volume_db": -2.0,
	},
	&"fireball_cast": {
		"stream": preload("res://assets/audio/sfx/fireball_cast.wav"), "volume_db": -7.0,
		"rate_limit": 6, "jitter": true,
	},
	&"fireball_blast": {
		"stream": preload("res://assets/audio/sfx/fireball_blast.wav"), "volume_db": -6.0,
		"rate_limit": 5, "jitter": true,
	},
	&"fireball_fall": {
		"stream": preload("res://assets/audio/sfx/fireball_fall.wav"), "volume_db": -10.0,
		"rate_limit": 3, "jitter": true,
	},
	&"fire_tornado": {
		"stream": preload("res://assets/audio/sfx/fire_tornado.wav"), "volume_db": -6.0,
		"rate_limit": 3,
	},
	&"tornado_burst": {
		"stream": preload("res://assets/audio/sfx/tornado_burst.wav"), "volume_db": -4.0,
	},
	&"claw_swipe": {
		"stream": preload("res://assets/audio/sfx/claw_swipe.wav"), "volume_db": -5.0,
		"rate_limit": 4, "jitter": true,
	},
	&"dive_fall": {
		"stream": preload("res://assets/audio/sfx/dive_fall.wav"), "volume_db": -7.0,
		"rate_limit": 2,
	},
	&"dive_impact": {
		"stream": preload("res://assets/audio/sfx/dive_impact.wav"), "volume_db": -3.0,
	},
	&"wing_blast": {
		"stream": preload("res://assets/audio/sfx/wing_blast.wav"), "volume_db": -4.0,
		"rate_limit": 2,
	},
	&"strafe_pass": {
		"stream": preload("res://assets/audio/sfx/strafe_pass.wav"), "volume_db": -5.0,
		"rate_limit": 2,
	},
	&"fire_blink": {
		"stream": preload("res://assets/audio/sfx/fire_blink.wav"), "volume_db": -6.0,
		"rate_limit": 2,
	},
	&"zone_ignite": {
		"stream": preload("res://assets/audio/sfx/zone_ignite.wav"), "volume_db": -9.0,
		"rate_limit": 5, "jitter": true,
	},
	&"fire_wave": {
		"stream": preload("res://assets/audio/sfx/fire_wave.wav"), "volume_db": -6.0,
		"rate_limit": 3, "jitter": true,
	},
	&"ring_blast": {
		"stream": preload("res://assets/audio/sfx/ring_blast.wav"), "volume_db": -4.0,
		"rate_limit": 2,
	},
	&"breath_inhale": {
		"stream": preload("res://assets/audio/sfx/breath_inhale.wav"), "volume_db": -6.0,
	},
	&"dawn_riser": {
		"stream": preload("res://assets/audio/sfx/dawn_riser.wav"), "volume_db": -4.0,
	},
}
