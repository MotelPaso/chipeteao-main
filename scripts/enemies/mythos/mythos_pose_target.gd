class_name MythosPoseTarget
extends RefCounted
## Lo que una pose le pide al rig del fénix (MythosRig): altura en metros,
## ángulos y aleteo en grados, escala y segundos de un aleteo. reset() deja
## el vuelo normal y cada pose cambia solo lo suyo. El rig guarda dos: lo que
## pide la pose y lo que se ve ahora, que lo persigue (approach).

var height: float = 0.0
var pitch: float = 0.0
var wing: float = 0.0
var hand: float = 0.0
var sweep: float = 0.0
var fold: float = 0.0
var legs: float = 0.0
var flap: float = 0.0
var hand_flap: float = 0.0
var scale: float = 1.0
var period: float = 1.0
## Grados que lleva el pico abierto.
var jaw: float = 0.0
## Metros que el cuerpo se lanza hacia adelante con cada golpe de alas.
var lunge: float = 0.0


func reset(fly_height: float, fly_pitch: float, fly_flap: float, fly_hand_flap: float,
		fly_period: float) -> void:
	height = fly_height
	pitch = fly_pitch
	wing = 0.0
	hand = -6.0
	sweep = 0.0
	fold = 0.0
	legs = -fly_pitch * 0.45
	flap = fly_flap
	hand_flap = fly_hand_flap
	scale = 1.0
	period = fly_period
	jaw = 0.0
	lunge = 0.0


## Acerca cada valor al de `target` en la fracción `blend` (0-1). El período
## no se persigue: la fase del aleteo ya es continua.
func approach(target: MythosPoseTarget, blend: float) -> void:
	height = lerpf(height, target.height, blend)
	pitch = lerpf(pitch, target.pitch, blend)
	wing = lerpf(wing, target.wing, blend)
	hand = lerpf(hand, target.hand, blend)
	sweep = lerpf(sweep, target.sweep, blend)
	fold = lerpf(fold, target.fold, blend)
	legs = lerpf(legs, target.legs, blend)
	flap = lerpf(flap, target.flap, blend)
	hand_flap = lerpf(hand_flap, target.hand_flap, blend)
	scale = lerpf(scale, target.scale, blend)
	jaw = lerpf(jaw, target.jaw, blend)
	lunge = lerpf(lunge, target.lunge, blend)
	period = target.period
