class_name Tank
extends Grunt
## Armored tank: the same contact-attack chase as Grunt; everything that
## makes it a tank is scene data on Tank.tscn — slow move_speed, big body,
## high max_hp plus flat armor on its Health child, heavier contact_damage
## on a slower cooldown, and a near-zero separation_strength so a crowd
## barely shoves it (knockback resistance).
