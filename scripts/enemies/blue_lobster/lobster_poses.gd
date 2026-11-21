class_name LobsterPoses
extends RefCounted
## Las poses de la Langosta Azul: qué le pide cada una al rig (LobsterRig).
## Son datos: cada fila de TABLE dice solo lo que esa pose cambia respecto de
## la de ronda (STALK). El rig llega a la pose de a poco y los gestos y la
## vida propia (LobsterGestures, LobsterMotion) se suman encima.

# --- Edita aquí: las poses -------------------------------------------------------
# Campos de cada fila (todos opcionales; lo que falta queda como en STALK):
#   height    altura del centro del tórax sobre el suelo (unidades del modelo)
#   pitch     inclinación del tórax en grados (positivo = cabeza arriba)
#   roll      ladeo en grados (180 = panza arriba)
#   yaw       giro de todo el cuerpo en grados; se multiplica por el lado que
#             lleva adelante (la Embestida va de costado)
#   arms      los dos brazos iguales: [levantar, abrir, codo, pinza]
#   lead      solo el brazo que golpea: [levantar, abrir, codo, pinza]
#   guard     solo el otro brazo
#   wrist     grados que levanta las dos muñecas
#   tail_curl grados que cada segmento de la cola se enrosca hacia abajo
#   tail_yaw  grados que cada segmento se va hacia el lado que lleva adelante
#   fan       cuánto abre el abanico de la cola (0-1)
#   antenna   grados que echa las antenas hacia atrás
#   maw       grados que abre la boca
#   tuck      cuánto recoge las patas (0 = apoyadas, 1 = recogidas)
const TABLE: Dictionary = {
	# Ronda: las pinzas en alto y abiertas a los lados, por encima del raider
	# que tiene delante (así no lo atraviesan cuando lo rodea de cerca).
	LobsterRig.Pose.STALK: {
		"height": 0.82, "pitch": 8.0, "arms": [30.0, 24.0, -4.0, 28.0], "tail_curl": 5.0,
		"fan": 0.35,
	},
	# Se alza con UNA pinza en alto y bien abierta: el aviso del pinzazo.
	LobsterRig.Pose.REAR: {
		"height": 0.96, "pitch": 22.0, "lead": [58.0, 24.0, -22.0, 52.0],
		"guard": [12.0, 22.0, 6.0, 22.0], "tail_curl": 9.0, "fan": 0.8, "antenna": 26.0,
		"maw": 14.0,
	},
	# El pinzazo: se lanza hacia adelante y la pinza se cierra abajo.
	LobsterRig.Pose.SNAP: {
		"height": 0.6, "pitch": -11.0, "lead": [-14.0, -14.0, -40.0, 2.0],
		"guard": [16.0, 30.0, 0.0, 24.0], "tail_curl": -6.0, "fan": 0.5, "antenna": 12.0,
	},
	# Amenaza: erguida, las dos pinzas en alto y abiertas (el rugido y la entrada).
	LobsterRig.Pose.THREAT: {
		"height": 1.0, "pitch": 28.0, "arms": [50.0, 38.0, -10.0, 52.0], "wrist": 10.0,
		"tail_curl": 10.0, "fan": 1.0, "antenna": 30.0, "maw": 22.0,
	},
	# Agazapada, con la cola enroscada debajo: toma impulso.
	LobsterRig.Pose.CROUCH: {
		"height": 0.46, "pitch": -6.0, "arms": [-4.0, 12.0, 14.0, 10.0], "tail_curl": 24.0,
		"fan": 0.2, "antenna": 36.0,
	},
	# En el aire, subiendo: patas recogidas, cola estirada y pinzas arriba.
	LobsterRig.Pose.LEAP: {
		"height": 0.78, "pitch": 30.0, "arms": [42.0, 30.0, -8.0, 44.0], "tail_curl": -14.0,
		"fan": 1.0, "antenna": 46.0, "tuck": 1.0,
	},
	# Cae con las pinzas por delante.
	LobsterRig.Pose.DIVE: {
		"height": 0.78, "pitch": -34.0, "arms": [-22.0, 12.0, -32.0, 46.0],
		"tail_curl": -20.0, "fan": 1.0, "antenna": 50.0, "tuck": 1.0,
	},
	# Recién caída: aplastada contra el suelo, con las pinzas clavadas.
	LobsterRig.Pose.SLAM: {
		"height": 0.4, "pitch": -8.0, "arms": [-26.0, 30.0, -10.0, 6.0], "tail_curl": 0.0,
		"fan": 0.9, "antenna": 18.0,
	},
	# Con un hombro adelante, baja y con las pinzas abiertas: el aviso de la Embestida.
	LobsterRig.Pose.SIDE: {
		"height": 0.6, "yaw": 30.0, "arms": [16.0, 50.0, -6.0, 42.0], "tail_curl": 12.0,
		"tail_yaw": 5.0, "fan": 0.6, "antenna": 40.0,
	},
	# La Embestida: con ese hombro adelante y a ras de suelo, las pinzas como guadañas.
	LobsterRig.Pose.DASH: {
		"height": 0.5, "roll": -9.0, "yaw": 24.0, "arms": [8.0, 58.0, -24.0, 50.0],
		"tail_curl": 4.0, "tail_yaw": 9.0, "fan": 0.9, "antenna": 58.0, "tuck": 0.55,
	},
	# La cola enroscada hacia un lado: el aviso del Coletazo.
	LobsterRig.Pose.COIL: {
		"height": 0.54, "pitch": -4.0, "arms": [6.0, 28.0, 4.0, 26.0], "tail_curl": 3.0,
		"tail_yaw": 17.0, "fan": 1.0, "antenna": 20.0,
	},
	# El Coletazo: la cola estirada barre mientras el cuerpo gira.
	LobsterRig.Pose.SWEEP: {
		"height": 0.5, "arms": [10.0, 40.0, -6.0, 30.0], "tail_curl": -3.0, "tail_yaw": -7.0,
		"fan": 1.0, "antenna": 44.0, "tuck": 0.45,
	},
	# Se entierra de cabeza, con la cola arriba.
	LobsterRig.Pose.DIG: {
		"height": 0.26, "pitch": -28.0, "arms": [-30.0, 8.0, 10.0, 20.0], "tail_curl": -18.0,
		"fan": 0.4, "antenna": 10.0, "tuck": 0.6,
	},
	# Bajo tierra: todo recogido; solo asoman los ojos y las antenas.
	LobsterRig.Pose.TUNNEL: {
		"height": 0.3, "pitch": 6.0, "arms": [-10.0, -4.0, 30.0, 6.0], "tail_curl": 2.0,
		"fan": 0.1, "antenna": -14.0, "tuck": 1.0,
	},
	# Sale de la tierra hacia arriba, con las pinzas por delante.
	LobsterRig.Pose.ERUPT: {
		"height": 0.9, "pitch": 42.0, "arms": [66.0, 30.0, -14.0, 52.0], "wrist": 12.0,
		"tail_curl": 12.0, "fan": 1.0, "antenna": 22.0, "maw": 26.0, "tuck": 0.8,
	},
	# Muerta: panza arriba, patas y cola encogidas.
	LobsterRig.Pose.DEAD: {
		"height": 0.42, "pitch": -6.0, "roll": 180.0, "arms": [34.0, 18.0, 52.0, 10.0],
		"tail_curl": 26.0, "fan": 0.1, "antenna": 54.0, "maw": 10.0, "tuck": 1.0,
	},
}


## Rellena `want` con lo que pide `pose`. `lead_left` dice qué brazo golpea en
## las poses de una sola pinza y `side` (1 o -1) qué flanco lleva adelante en
## las poses de costado.
static func fill(want: LobsterPoseTarget, pose: LobsterRig.Pose, lead_left: bool,
		side: float) -> void:
	want.reset()
	_apply(want, TABLE[LobsterRig.Pose.STALK], lead_left, side)
	if pose != LobsterRig.Pose.STALK and TABLE.has(pose):
		_apply(want, TABLE[pose], lead_left, side)


static func _apply(want: LobsterPoseTarget, row: Dictionary, lead_left: bool,
		side: float) -> void:
	for key: String in row:
		var value: Variant = row[key]
		match key:
			"arms":
				var both: Array = value
				want.set_arms(float(both[0]), float(both[1]), float(both[2]), float(both[3]))
			"lead":
				var one: Array = value
				want.set_arm(lead_left, float(one[0]), float(one[1]), float(one[2]), float(one[3]))
			"guard":
				var other: Array = value
				want.set_arm(not lead_left, float(other[0]), float(other[1]), float(other[2]),
						float(other[3]))
			"wrist":
				want.wrist_left = float(value)
				want.wrist_right = float(value)
			"yaw", "tail_yaw":
				want.set(key, float(value) * side)
			"roll":
				# El ladeo acompaña al flanco; quedar panza arriba no tiene lado.
				var roll := float(value)
				want.roll = roll if absf(roll) >= 90.0 else roll * side
			_:
				want.set(key, float(value))
