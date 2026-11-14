class_name MythosPoses
extends RefCounted
## Las poses del fénix: qué le pide cada una al rig (MythosRig). Los valores
## son exports del rig (grupos «Vuelo», «Cuerpo», «En tierra», «Amanecer»,
## «Alas» y «Cenizas»); aquí solo está cómo se combinan en cada pose.


## Rellena `want` con lo que pide `pose`. `fly_height` es la altura de vuelo
## de ahora, `size` el tamaño del modelo y `nova_charge` la carga del
## Amanecer (0-1).
static func fill(want: MythosPoseTarget, rig: MythosRig, pose: MythosRig.Pose,
		fly_height: float, size: float, nova_charge: float) -> void:
	want.reset(fly_height, rig.fly_pitch_degrees, rig.flap_degrees, rig.hand_flap_degrees,
			rig.flap_period)
	match pose:
		MythosRig.Pose.WINDUP, MythosRig.Pose.CAST, MythosRig.Pose.GLIDE, MythosRig.Pose.NOVA:
			_in_air(want, rig, pose, nova_charge)
		MythosRig.Pose.DIVE, MythosRig.Pose.PERCH, MythosRig.Pose.REAR, MythosRig.Pose.SLASH:
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
