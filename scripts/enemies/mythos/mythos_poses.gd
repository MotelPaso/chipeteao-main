class_name MythosPoses
extends RefCounted
## Las poses del fénix: qué le pide cada una al rig (MythosRig). Los valores
## son exports del rig (grupos «Vuelo», «Cuerpo», «En tierra», «Amanecer»,
## «Alas» y «Cenizas»); aquí solo está cómo se combinan en cada pose.
## Las dos poses con que va hacia el raider llevan sus números aquí abajo.

# --- Edita aquí: cómo se ve cuando va hacia el raider ----------------------------
## CAZA (en vuelo, se le viene encima): metros que baja de su altura de vuelo.
const HUNT_DROP: float = 1.1
## Inclinación del cuerpo en grados (bajo = tendido, con la cabeza por delante).
const HUNT_PITCH: float = 4.0
## Grados que lleva las alas levantadas y echadas hacia atrás.
const HUNT_WING: float = 16.0
const HUNT_SWEEP: float = 22.0
## Su aleteo: cuántas veces más amplio y más lento que en vuelo normal.
const HUNT_FLAP: float = 1.35
const HUNT_PERIOD: float = 0.8
## Grados que adelanta las patas, con las garras abiertas hacia el raider.
const HUNT_LEGS: float = 48.0
## Cuánto se agranda (1 = igual).
const HUNT_SCALE: float = 1.06
## Grados que lleva el pico abierto y metros que se lanza hacia adelante con cada golpe de alas.
const HUNT_JAW: float = 14.0
const HUNT_LUNGE: float = 0.7
## ACECHO (en tierra, camina hacia el raider): parte de su altura de posado a la
## que queda al tenderse hacia adelante (0-1). Lo que baja al dar cada paso lo pone Motion.
const PROWL_CROUCH: float = 0.93
## Inclinación del cuerpo en grados (bajo = cabeza gacha, por delante).
const PROWL_PITCH: float = 3.0
## Grados que abre las alas a los costados, como un manto, y cuánto las pliega.
const PROWL_WING: float = 12.0
const PROWL_SWEEP: float = 30.0
const PROWL_FOLD: float = 26.0
## Grados que lleva el pico abierto mientras acecha.
const PROWL_JAW: float = 9.0


## Rellena `want` con lo que pide `pose`. `fly_height` es la altura de vuelo
## de ahora, `size` el tamaño del modelo y `nova_charge` la carga del
## Amanecer (0-1).
static func fill(want: MythosPoseTarget, rig: MythosRig, pose: MythosRig.Pose,
		fly_height: float, size: float, nova_charge: float) -> void:
	want.reset(fly_height, rig.fly_pitch_degrees, rig.flap_degrees, rig.hand_flap_degrees,
			rig.flap_period)
	match pose:
		MythosRig.Pose.WINDUP, MythosRig.Pose.CAST, MythosRig.Pose.GLIDE, MythosRig.Pose.NOVA, \
				MythosRig.Pose.HUNT:
			_in_air(want, rig, pose, nova_charge)
		MythosRig.Pose.DIVE, MythosRig.Pose.PERCH, MythosRig.Pose.REAR, MythosRig.Pose.SLASH, \
				MythosRig.Pose.PROWL:
			_on_ground(want, rig, pose, size)
		MythosRig.Pose.ASHES:
			want.height = rig.ashes_height
			want.pitch = 0.0
			want.scale = rig.ashes_scale
			want.sweep = rig.swept_degrees
			want.fold = rig.folded_degrees
			want.flap = 0.0
			want.hand_flap = 0.0
			want.legs = 0.0


## Las poses de vuelo que no son el vuelo normal.
static func _in_air(want: MythosPoseTarget, rig: MythosRig, pose: MythosRig.Pose,
		nova_charge: float) -> void:
	match pose:
		MythosRig.Pose.WINDUP:
			# Se alza con las alas en alto, casi quietas: el aviso del golpe.
			want.height += rig.windup_rise
			want.pitch = rig.windup_pitch_degrees
			want.wing = rig.raised_degrees
			want.hand = 14.0
			want.flap = rig.flap_degrees * 0.18
			want.hand_flap = rig.hand_flap_degrees * 0.25
			want.legs = -rig.windup_pitch_degrees * 0.3
			want.period = rig.flap_period * 0.5
		MythosRig.Pose.CAST:
			# Erguido y con las alas bien abiertas, aleteando lento.
			want.height += rig.windup_rise * 0.5
			want.pitch = rig.cast_pitch_degrees
			want.wing = rig.cast_degrees
			want.hand = 8.0
			want.flap = rig.flap_degrees * 0.4
			want.hand_flap = rig.hand_flap_degrees * 0.5
			want.legs = -rig.cast_pitch_degrees * 0.4
			want.period = rig.flap_period * 1.5
		MythosRig.Pose.GLIDE:
			# Vuelo rasante: cuerpo tendido y alas abiertas, sin aletear.
			want.height -= rig.glide_drop
			want.pitch = rig.glide_pitch_degrees
			want.wing = 5.0
			want.hand = -4.0
			want.sweep = rig.swept_degrees * 0.25
			want.flap = rig.flap_degrees * 0.08
			want.hand_flap = rig.hand_flap_degrees * 0.08
			want.legs = -rig.dive_legs_degrees
		MythosRig.Pose.HUNT:
			# Se le viene encima: tendido, la cabeza por delante, las alas en
			# alto batiendo hondo y las garras abiertas hacia el raider.
			want.height -= HUNT_DROP
			want.pitch = HUNT_PITCH
			want.wing = HUNT_WING
			want.hand = 6.0
			want.sweep = HUNT_SWEEP
			want.flap = rig.flap_degrees * HUNT_FLAP
			want.hand_flap = rig.hand_flap_degrees * HUNT_FLAP
			want.legs = HUNT_LEGS
			want.scale = HUNT_SCALE
			want.period = rig.flap_period * HUNT_PERIOD
			want.jaw = HUNT_JAW
			want.lunge = HUNT_LUNGE
		MythosRig.Pose.NOVA:
			# Carga el Amanecer: arriba, erguido, alas abiertas que baten lento.
			want.height += rig.nova_rise
			want.pitch = rig.nova_pitch_degrees
			want.wing = rig.raised_degrees * 0.6
			want.hand = 12.0
			want.flap = rig.flap_degrees * 0.5
			want.hand_flap = rig.hand_flap_degrees * 0.5
			want.legs = -rig.nova_pitch_degrees * 0.4
			want.scale = lerpf(1.0, rig.nova_scale, clampf(nova_charge, 0.0, 1.0))
			want.period = rig.flap_period * 1.8


## La picada y las poses de tierra: la altura sigue al tamaño del modelo,
## para que las patas lleguen al suelo.
static func _on_ground(want: MythosPoseTarget, rig: MythosRig, pose: MythosRig.Pose,
		size: float) -> void:
	want.height = rig.perch_height * size
	match pose:
		MythosRig.Pose.DIVE:
			# Pico abajo, alas echadas atrás y garras por delante.
			want.pitch = rig.dive_pitch_degrees
			want.wing = 10.0
			want.sweep = rig.swept_degrees
			want.fold = rig.folded_degrees
			want.flap = 0.0
			want.hand_flap = 0.0
			want.legs = rig.dive_legs_degrees
		MythosRig.Pose.PERCH:
			# Posado: alas medio plegadas que respiran despacio.
			want.pitch = rig.perch_pitch_degrees
			want.wing = -8.0
			want.hand = -22.0
			want.sweep = rig.swept_degrees * 0.35
			want.fold = rig.folded_degrees * 0.8
			want.flap = rig.perch_flap_degrees
			want.hand_flap = rig.perch_flap_degrees * 0.6
			want.legs = -rig.perch_pitch_degrees
			want.period = rig.flap_period * 2.4
		MythosRig.Pose.PROWL:
			# Lo acecha a pie: agazapado, la cabeza gacha por delante y las
			# alas abiertas a los costados como un manto.
			want.height *= PROWL_CROUCH
			want.pitch = PROWL_PITCH
			want.wing = PROWL_WING
			want.hand = -34.0
			want.sweep = PROWL_SWEEP
			want.fold = PROWL_FOLD
			want.flap = rig.perch_flap_degrees * 1.6
			want.hand_flap = rig.perch_flap_degrees
			want.legs = -PROWL_PITCH
			want.period = rig.flap_period * 1.6
			want.jaw = PROWL_JAW
		MythosRig.Pose.REAR:
			# Erguido y con las alas en alto: el aviso de un golpe en tierra.
			want.height += rig.rear_rise
			want.pitch = rig.rear_pitch_degrees
			want.wing = rig.raised_degrees
			want.hand = 18.0
			want.flap = rig.flap_degrees * 0.15
			want.hand_flap = rig.hand_flap_degrees * 0.2
			want.legs = -rig.rear_pitch_degrees * 0.5
			want.period = rig.flap_period * 0.45
		MythosRig.Pose.SLASH:
			# El zarpazo: se echa adelante y las alas golpean hacia abajo.
			want.pitch = rig.slash_pitch_degrees
			want.wing = rig.slash_wing_degrees
			want.hand = -28.0
			want.fold = rig.folded_degrees * 0.25
			want.flap = 0.0
			want.hand_flap = 0.0
			want.legs = rig.dive_legs_degrees
