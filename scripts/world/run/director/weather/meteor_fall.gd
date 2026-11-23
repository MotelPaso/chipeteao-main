class_name MeteorFall
extends Node3D
## Meteorito que cae del cielo durante el aviso de la lluvia de meteoritos:
## entra en diagonal desde lo alto y toca el suelo justo al impactar. Solo es
## visual: el daño, la explosión y la marca los pone WeatherDirector. Se crea
## con MeteorFall.spawn() y se borra solo al llegar al suelo.
## No va en ninguna escena: edita los valores aquí.

## Edita aquí: cómo se ve el meteorito al caer.
## Altura (metros) desde la que empieza a caer.
const START_HEIGHT: float = 28.0
## Distancia horizontal (metros) entre donde aparece y donde cae; más = más diagonal.
const START_SIDE_OFFSET: float = 12.0
## Radio (metros) de la roca.
const ROCK_RADIUS: float = 0.8
## Color de la roca encendida.
const ROCK_COLOR: Color = Color(1.0, 0.45, 0.15)
## Brillo de la roca (energía de emisión; 1 = sin brillo extra).
const ROCK_GLOW: float = 3.0
## Largo (metros) de la estela de fuego detrás de la roca.
const TAIL_LENGTH: float = 6.0
## Color de la estela; el alfa es su opacidad (0-1).
const TAIL_COLOR: Color = Color(1.0, 0.7, 0.25, 0.55)


## Lanza un meteorito que llega a `at` en `seconds` segundos (el aviso del
## impacto). No toca el RNG de la partida: el ángulo sale de un RNG propio.
static func spawn(host: Node, at: Vector3, seconds: float) -> void:
	if host == null or not host.is_inside_tree() or seconds <= 0.0:
		return
	var parent := host.get_tree().current_scene
	if parent == null:
		parent = host
	var meteor := MeteorFall.new()
	parent.add_child(meteor)
	meteor._fall(at, seconds)


## Arma la roca y la estela y la deja caer acelerando, como con gravedad.
func _fall(target: Vector3, seconds: float) -> void:
	var rng := RandomNumberGenerator.new()
	var angle := rng.randf() * TAU
	var side := Vector3(cos(angle), 0.0, sin(angle)) * START_SIDE_OFFSET
	var start := target + side + Vector3.UP * START_HEIGHT
	global_position = start
	_build_rock()
	_build_tail((start - target).normalized())
	var tween := create_tween()
	tween.tween_property(self, "global_position", target, seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _build_rock() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = ROCK_RADIUS
	mesh.height = ROCK_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = ROCK_COLOR
	material.emission_enabled = true
	material.emission = ROCK_COLOR
	material.emission_energy_multiplier = ROCK_GLOW
	var rock := MeshInstance3D.new()
	rock.mesh = mesh
	rock.material_override = material
	add_child(rock)


## Cono de fuego que apunta hacia atrás (`back`, hacia donde vino la roca):
## ancho junto a la roca y en punta al final.
func _build_tail(back: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.height = TAIL_LENGTH
	mesh.bottom_radius = ROCK_RADIUS * 0.9
	mesh.top_radius = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = TAIL_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tail := MeshInstance3D.new()
	tail.mesh = mesh
	tail.material_override = material
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El eje Y del cilindro apunta hacia atrás; su base queda en la roca.
	tail.basis = Basis(Quaternion(Vector3.UP, back))
	tail.position = back * TAIL_LENGTH * 0.5
	add_child(tail)
