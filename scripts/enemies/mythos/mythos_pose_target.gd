class_name MythosPoseTarget
extends RefCounted
## Lo que una pose le pide al rig del fénix (MythosRig): altura en metros,
## ángulos y aleteo en grados, escala y segundos de un aleteo. reset() deja
## el vuelo normal y cada pose cambia solo lo suyo.

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
