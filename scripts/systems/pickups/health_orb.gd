class_name HealthOrb
extends MagnetPickup
## Orbe de curación que sueltan las élites (por probabilidad) y los jefes
## (cantidad fija): el chasis compartido MagnetPickup más una curación fija
## — que a propósito NO escala con vueltas ni dificultad — y un pulso de
## escala en reposo. Un tope suave global evita que una pelea de jefe
## alfombre la arena de curas; como el chasis deja el grupo vivo antes de
## cada liberación al pool, el tope solo cuenta orbes que están en el suelo.

## Todo orbe vivo (soltado y sin recoger) está en este grupo: quien suelta
## orbes lo cuenta para el tope y la aspiradora de subida de nivel los
## alcanza por él.
const LIVE_GROUP: StringName = &"health_orbs"
## Tope global de orbes vivos; en el tope, quien suelta se salta el drop.
const SOFT_CAP: int = 6

## Fracción (0-1) del HP máx. del jugador que cura al recogerlo.
@export var heal_fraction: float = 0.15
## Amplitud del pulso de escala en reposo (0.08 = ±8%) y su velocidad, el
## latido que lo hace verse vivo.
@export var pulse_amount: float = 0.08
@export var pulse_speed: float = 5.0


## Ajuste del chasis compartido para el orbe: menos alcance y menos vida
## que una gema de XP, y un giro más lento. Se pone aquí porque el chasis es
## compartido; un valor guardado en HealthOrb.tscn igual ganaría (las
## propiedades de la escena se aplican después de _init).
func _init() -> void:
	magnet_radius = 3.5
	lifetime = 45.0
	spin_speed = 1.8
	bob_amplitude = 0.1


## True si la arena ya tiene SOFT_CAP orbes vivos. Quien suelta lo revisa
## antes de pedir otro (los orbes guardados o en liberación ya dejaron el
## grupo, así que nunca cuentan contra el tope).
static func at_soft_cap(tree: SceneTree) -> bool:
	return tree.get_node_count_in_group(LIVE_GROUP) >= SOFT_CAP


func live_group() -> StringName:
	return LIVE_GROUP


func _idle_visuals(_delta: float) -> void:
	_visual.scale = Vector3.ONE * (1.0 + pulse_amount * sin(_age * pulse_speed))


func _on_collected(collector: Node3D) -> void:
	var health := Health.find_in(collector)
	if health != null:
		# Health.heal recorta a max_hp (sin sobrecura) y no hace nada si murió.
		health.heal(health.max_hp * heal_fraction)
	Sfx.play(&"heal")
