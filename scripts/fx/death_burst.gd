class_name DeathBurst
extends GPUParticles3D
## Estallido de un solo uso de esquirlas de colores (muertes de enemigos,
## destellos de cofres y santuarios). El tinte viaja en el color por
## partícula hacia un material sin sombreado de color por vértice compartido;
## el material de proceso es local a la escena, así cada instancia del pool
## tiene su copia y el material de dibujo nunca se duplica. Del pool:
## Juice.burst() saca uno de Pools y llama a fire(); el `amount` de la escena
## es el tamaño del búfer (pensado para el estallido de jefe más grande) y
## fire() emite la cantidad pedida con amount_ratio, así el reuso nunca
## vuelve a reservar el búfer de partículas.

var _fire_seq: int = 0


## Contrato del pool: los estallidos guardados quedan apagados.
func pool_reset() -> void:
	emitting = false


## Lanza un estallido de `particles` esquirlas y programa su vuelta al pool.
## Llamar con el nodo ya dentro del árbol y colocado.
func fire(tint: Color, particles: int) -> void:
	var particle_material := process_material as ParticleProcessMaterial
	if particle_material != null:
		particle_material.color = tint
	# Recortado al búfer de la escena, nunca agrandado: subir `amount` en
	# ejecución reserva el búfer de nuevo y el cambio se queda, así una
	# instancia que sirvió a un jefe pagaría ese búfer para siempre.
	# Estallidos más grandes = un `amount` mayor en la escena (ver
	# Juice.boss_burst_amount).
	var wanted := clampi(particles, 1, amount)
	amount_ratio = float(wanted) / float(amount)
	restart()
	# La señal `finished` nunca se emite con el renderizador falso de
	# headless, así que la liberación va por temporizador: sin escala de
	# tiempo para que la cámara lenta de una muerte de jefe no estire la
	# limpieza, pero PAUSABLE como todo efecto del pool, para que la pantalla
	# de cartas no recicle un estallido congelado en pantalla. El número de
	# secuencia descarta un temporizador viejo si esta instancia se volvió a
	# disparar entretanto.
	_fire_seq += 1
	get_tree().create_timer(lifetime + 0.3, false, false, true) \
			.timeout.connect(_on_burst_done.bind(_fire_seq))


func _on_burst_done(seq: int) -> void:
	if seq != _fire_seq:
		return
	Pools.release(self)
